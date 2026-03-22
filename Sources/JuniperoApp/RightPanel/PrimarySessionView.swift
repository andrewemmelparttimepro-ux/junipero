import SwiftUI
import Foundation

// MARK: - Primary Session Store

@MainActor
final class PrimarySessionStore: ObservableObject {
    @Published var messages: [PrimaryMessage] = []
    @Published var isLoading = false
    @Published var isStreaming = false
    @Published var streamingText = ""
    @Published var errorText: String?
    @Published var isConnected = false
    @Published var recallEnabled = false
    @Published var recallContext: String?

    let sessionKey: String
    private var anthropicClient: AnthropicClient?
    private var wsClient: GatewayWSClient?  // Legacy fallback
    private weak var rosterStore: AgentRosterStore?
    private weak var screenCaptureStore: ScreenCaptureStore?
    let cogneeClient = CogneeClient()
    /// Conversation history for the Anthropic API (messages sent in this session)
    private var conversationHistory: [AnthropicMessage] = []

    init(sessionKey: String = "main") {
        self.sessionKey = sessionKey
    }

    func bind(anthropicClient: AnthropicClient) {
        self.anthropicClient = anthropicClient
    }

    func bind(wsClient: GatewayWSClient) {
        self.wsClient = wsClient
    }

    func bindRoster(_ roster: AgentRosterStore) {
        self.rosterStore = roster
    }

    func bindScreenCapture(_ store: ScreenCaptureStore) {
        self.screenCaptureStore = store
    }

    func connect() {
        // Native API: just check if configured
        if let client = anthropicClient, client.apiKeyConfigured {
            isConnected = true
            // Load persisted messages if any (native mode has no external history)
            return
        }

        // Legacy gateway fallback
        guard let wsClient else {
            isConnected = false
            return
        }
        if !wsClient.connected {
            wsClient.connect()
            wsClient.refreshNow()
        }
        Task {
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 150_000_000)
                if wsClient.connected { break }
            }
            isConnected = wsClient.connected
            if isConnected { loadHistory() }
        }
    }

    func loadHistory() {
        // Native mode: no external history to load (conversations are in-memory)
        guard anthropicClient == nil || !(anthropicClient?.apiKeyConfigured ?? false) else { return }

        // Legacy gateway fallback
        guard let wsClient else { return }
        wsClient.fetchHistory(sessionKey: sessionKey) { [weak self] entries in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.messages = entries.compactMap { entry in
                    let text = entry.resolvedContent
                    let images = entry.resolvedImages
                    guard !text.isEmpty || !images.isEmpty else { return nil }
                    return PrimaryMessage(
                        role: entry.role == "assistant" ? .assistant : .user,
                        text: text,
                        model: entry.model,
                        timestamp: Self.parseDate(entry.timestamp),
                        images: images
                    )
                }
            }
        }
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMsg = PrimaryMessage(role: .user, text: trimmed)
        messages.append(userMsg)
        isLoading = true
        isStreaming = false
        streamingText = ""
        errorText = nil

        // Primary: native Anthropic API
        if let client = anthropicClient, client.apiKeyConfigured {
            Task { await doSendNative(trimmed) }
            return
        }

        // Fallback: legacy gateway
        guard let wsClient else {
            errorText = "No API key configured. Open Settings to add your Anthropic API key."
            isLoading = false
            return
        }
        if !wsClient.connected {
            wsClient.connect()
            wsClient.refreshNow()
            Task {
                for _ in 0..<40 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    if wsClient.connected { break }
                }
                await self.doSendLegacy(trimmed)
            }
        } else {
            Task { await doSendLegacy(trimmed) }
        }
    }

    // MARK: - Native Anthropic Send (Primary)

    private func doSendNative(_ text: String) async {
        guard let client = anthropicClient else {
            errorText = "API client not available."
            isLoading = false
            return
        }

        // Cognee memory recall (optional enhancement)
        var finalText = text
        if recallEnabled {
            recallContext = nil
            if let context = await cogneeClient.recall(query: text, maxResults: 5) {
                recallContext = context
                finalText = "[Memory Recall — the following context was retrieved from Cognee knowledge graph]\n\(context)\n\n[User Message]\n\(text)"
            }
        }

        // Screenshot attachment
        let imagePayload = screenCaptureStore?.pendingScreenshot
        screenCaptureStore?.clear()

        // Light up jewel
        rosterStore?.markSessionActive(sessionKey, detail: "Processing request…")

        // Track in conversation history
        conversationHistory.append(AnthropicMessage(role: "user", text: finalText))

        // Build history (all but the last user message, which goes as `text`)
        let history = conversationHistory.count > 1 ? Array(conversationHistory.dropLast()) : []

        await withCheckedContinuation { continuation in
            var resumed = false
            client.send(
                text: finalText,
                imageData: imagePayload,
                history: history,
                systemPrompt: "You are Thrawn, a strategic AI command agent. You serve the user directly. Be precise, thorough, and proactive.",
                sessionKey: sessionKey,
                onDelta: { [weak self] delta in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.isStreaming = true
                        self.streamingText += delta
                    }
                },
                onComplete: { [weak self] finalText, model in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let text = finalText.isEmpty ? self.streamingText : finalText
                        self.messages.append(PrimaryMessage(role: .assistant, text: text, model: model))
                        self.conversationHistory.append(AnthropicMessage(role: "assistant", text: text))
                        self.isLoading = false
                        self.isStreaming = false
                        self.streamingText = ""
                        self.rosterStore?.markSessionComplete(self.sessionKey, detail: "Response received")
                        if !resumed { resumed = true; continuation.resume() }
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        // Remove the failed user message from history
                        if self.conversationHistory.last?.role == "user" {
                            self.conversationHistory.removeLast()
                        }
                        self.errorText = error
                        self.isLoading = false
                        self.isStreaming = false
                        self.streamingText = ""
                        self.rosterStore?.markSessionError(self.sessionKey, detail: error)
                        if !resumed { resumed = true; continuation.resume() }
                    }
                }
            )
        }
    }

    // MARK: - Legacy Gateway Send (Fallback)

    private func doSendLegacy(_ text: String) async {
        guard let wsClient else {
            errorText = "Gateway client is not ready yet."
            isLoading = false
            return
        }

        var finalText = text
        if recallEnabled {
            recallContext = nil
            if let context = await cogneeClient.recall(query: text, maxResults: 5) {
                recallContext = context
                finalText = "[Memory Recall — the following context was retrieved from Cognee knowledge graph]\n\(context)\n\n[User Message]\n\(text)"
            }
        }

        let imagePayload = screenCaptureStore?.pendingScreenshot
        screenCaptureStore?.clear()
        rosterStore?.markSessionActive(sessionKey, detail: "Processing request…")

        await withCheckedContinuation { continuation in
            var resumed = false
            wsClient.send(
                text: finalText,
                imageData: imagePayload,
                sessionKey: sessionKey,
                onDelta: { [weak self] delta in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.isStreaming = true
                        self.streamingText += delta
                    }
                },
                onComplete: { [weak self] finalText, model in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let text = finalText.isEmpty ? self.streamingText : finalText
                        self.messages.append(PrimaryMessage(role: .assistant, text: text, model: model))
                        self.isLoading = false
                        self.isStreaming = false
                        self.streamingText = ""
                        self.rosterStore?.markSessionComplete(self.sessionKey, detail: "Response received")
                        if !resumed { resumed = true; continuation.resume() }
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.errorText = error
                        self.isLoading = false
                        self.isStreaming = false
                        self.streamingText = ""
                        self.rosterStore?.markSessionError(self.sessionKey, detail: error)
                        if !resumed { resumed = true; continuation.resume() }
                    }
                }
            )
        }
    }

    func abort() {
        anthropicClient?.abort(sessionKey: sessionKey)
        wsClient?.abort(sessionKey: sessionKey)
        isLoading = false
        isStreaming = false
        streamingText = ""
    }

    private static func parseDate(_ timestampMs: Double?) -> Date? {
        guard let timestampMs else { return nil }
        return Date(timeIntervalSince1970: timestampMs / 1000)
    }
}

// MARK: - Message Model

/// An image block extracted from a gateway content response
struct MessageImageBlock: Identifiable {
    let id = UUID()
    var image: NSImage?         // Decoded from base64
    var imageURL: URL?          // For URL-sourced images
    var mediaType: String       // "image/png", "image/jpeg", etc.
}

struct PrimaryMessage: Identifiable {
    let id = UUID()
    var role: MessageRole
    var text: String
    var model: String?
    var timestamp: Date?
    var images: [MessageImageBlock] = []

    enum MessageRole {
        case user, assistant
    }
}

// MARK: - Primary Session View

struct PrimarySessionView: View {
    @EnvironmentObject var anthropic: AnthropicClient
    @EnvironmentObject var gatewayWS: GatewayWSClient
    @EnvironmentObject var bootstrap: ThrawnBootstrap
    @EnvironmentObject var roster: AgentRosterStore
    @EnvironmentObject var screenCapture: ScreenCaptureStore
    @StateObject private var store: PrimarySessionStore
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool
    @State private var scrollTarget: UUID?

    let agentName: String
    let agentInitial: String

    init(sessionKey: String = "main", agentName: String = "Thrawn", agentInitial: String = "T") {
        _store = StateObject(wrappedValue: PrimarySessionStore(sessionKey: sessionKey))
        self.agentName = agentName
        self.agentInitial = agentInitial
    }

    var body: some View {
        ZStack {
            Color.obsidian.ignoresSafeArea()

            VStack(spacing: 0) {
                // Connection status bar (only shown when not connected)
                if !anthropic.connected && !gatewayWS.connected {
                    HStack(spacing: 8) {
                        ProgressView().progressViewStyle(.circular).scaleEffect(0.6).tint(Color(red: 0.95, green: 0.70, blue: 0.20))
                        Text(connectionStatusText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 0.95, green: 0.70, blue: 0.20))
                        Spacer()
                    }
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Color(red: 0.95, green: 0.70, blue: 0.20).opacity(0.10))
                    .overlay(alignment: .bottom) { Rectangle().fill(Color(red: 0.95, green: 0.70, blue: 0.20).opacity(0.20)).frame(height: 1) }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Recall context indicator
                if let recallContext = store.recallContext, !recallContext.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 0.55, green: 0.82, blue: 0.95))
                        Text("Memory context attached (\(recallContext.count) chars)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 0.55, green: 0.82, blue: 0.95))
                        Spacer()
                        Button { store.recallContext = nil } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(red: 0.55, green: 0.82, blue: 0.95).opacity(0.70))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 6)
                    .background(Color(red: 0.55, green: 0.82, blue: 0.95).opacity(0.08))
                    .overlay(alignment: .bottom) { Rectangle().fill(Color(red: 0.55, green: 0.82, blue: 0.95).opacity(0.15)).frame(height: 1) }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            if store.messages.isEmpty && !store.isLoading {
                                ThrawnWelcomePrompt(agentName: agentName, agentInitial: agentInitial)
                                    .padding(.top, 60)
                            }

                            ForEach(store.messages) { msg in
                                PrimaryMessageBubble(message: msg, agentInitial: agentInitial)
                                    .id(msg.id)
                            }

                            if store.isStreaming {
                                PrimaryStreamingBubble(text: store.streamingText, agentInitial: agentInitial)
                                    .id("streaming")
                            } else if store.isLoading {
                                PrimaryThinkingBubble(agentInitial: agentInitial)
                                    .id("thinking")
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .onChange(of: store.messages.count) { _ in
                        withAnimation(.easeOut(duration: 0.25)) {
                            if let last = store.messages.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: store.streamingText) { _ in
                        withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                    }
                    .onChange(of: store.isLoading) { _ in
                        withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Error banner
                if let err = store.errorText {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color.sithGlow)
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundColor(Color.sithGlow)
                            .lineLimit(2)
                        Spacer()
                        Button { store.errorText = nil } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(Color.sithGlow.opacity(0.70))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Color.sithRed.opacity(0.15))
                    .overlay(alignment: .top) { Rectangle().fill(Color.sithGlow.opacity(0.25)).frame(height: 1) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Input bar
                inputBar
            }
            .animation(.easeInOut(duration: 0.18), value: anthropic.connected || gatewayWS.connected)
            .animation(.easeInOut(duration: 0.18), value: store.errorText != nil)
            .animation(.easeInOut(duration: 0.18), value: store.recallContext != nil)
            .animation(.easeInOut(duration: 0.18), value: screenCapture.pendingScreenshot != nil)
        }
        .onAppear {
            store.bind(anthropicClient: anthropic)
            store.bind(wsClient: gatewayWS)
            store.bindRoster(roster)
            store.bindScreenCapture(screenCapture)
            store.connect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                inputFocused = true
            }
        }
    }

    private var connectionStatusText: String {
        if !anthropic.apiKeyConfigured {
            return "No API key — open Settings to configure"
        }
        if anthropic.authenticating {
            return "Connecting to Anthropic API…"
        }
        if let error = anthropic.lastError {
            return error
        }
        return "Reconnecting…"
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.chissPrimary.opacity(0.12))
                .frame(height: 1)

            // Screenshot preview strip
            if let thumbnail = screenCapture.pendingThumbnail {
                HStack(spacing: 10) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color(red: 0.55, green: 0.82, blue: 0.95).opacity(0.50), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("SCREEN CAPTURE ATTACHED")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1)
                            .foregroundColor(Color(red: 0.55, green: 0.82, blue: 0.95))
                        Text(screenCapture.fileSizeLabel + " — will be sent with your next message")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.45))
                    }

                    Spacer()

                    Button { screenCapture.clear() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(red: 0.55, green: 0.82, blue: 0.95).opacity(0.60))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Color(red: 0.55, green: 0.82, blue: 0.95).opacity(0.06))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(red: 0.55, green: 0.82, blue: 0.95).opacity(0.12)).frame(height: 1)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Screen capture error
            if let captureErr = screenCapture.captureError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.95, green: 0.70, blue: 0.20))
                    Text(captureErr)
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.95, green: 0.70, blue: 0.20))
                        .lineLimit(2)
                    Spacer()
                    Button { screenCapture.captureError = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(red: 0.95, green: 0.70, blue: 0.20).opacity(0.70))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18).padding(.vertical, 6)
                .background(Color(red: 0.95, green: 0.70, blue: 0.20).opacity(0.08))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 10) {
                // Cognee recall toggle
                Button {
                    withAnimation(.spring(response: 0.28)) {
                        store.recallEnabled.toggle()
                    }
                } label: {
                    Image(systemName: store.recallEnabled ? "brain.head.profile.fill" : "brain.head.profile")
                        .font(.system(size: 16))
                        .foregroundColor(store.recallEnabled ? Color(red: 0.55, green: 0.82, blue: 0.95) : Color.chissPrimary.opacity(0.35))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(store.recallEnabled ? "Memory recall ON — Cognee context will be attached" : "Memory recall OFF — tap to enable")

                TextField("Command \(agentName)…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.92))
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .onSubmit { if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { send() } }

                if store.cogneeClient.isRecalling {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.55)
                        .tint(Color(red: 0.55, green: 0.82, blue: 0.95))
                        .frame(width: 22, height: 22)
                }

                if store.isLoading {
                    Button {
                        store.abort()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Color.sithGlow)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Button { send() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(
                                inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.chissPrimary.opacity(0.30)
                                    : Color.chissPrimary
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(Color.obsidianMid.opacity(0.95))
    }

    private func send() {
        let text = inputText
        inputText = ""
        store.send(text)
    }
}

// MARK: - Welcome Prompt

private struct ThrawnWelcomePrompt: View {
    let agentName: String
    let agentInitial: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.chissDeep)
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.chissPrimary.opacity(0.40), radius: 18)
                Text(agentInitial)
                    .font(.system(size: 32, weight: .bold, design: .serif))
                    .foregroundColor(Color.chissPrimary)
            }
            Text("\(agentName) Command Console")
                .font(.system(size: 17, weight: .bold, design: .serif))
                .tracking(2)
                .foregroundColor(Color.chissPrimary)
                .shadow(color: Color.chissPrimary.opacity(0.40), radius: 10)
            Text("Ready for your command.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white.opacity(0.40))
        }
    }
}

// MARK: - Message Bubbles

struct PrimaryMessageBubble: View {
    let message: PrimaryMessage
    var agentInitial: String = "T"

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isUser { Spacer(minLength: 60) }

            if !isUser {
                ZStack {
                    Circle().fill(Color.chissDeep).frame(width: 28, height: 28)
                    Text(agentInitial).font(.system(size: 13, weight: .bold, design: .serif)).foregroundColor(Color.chissPrimary)
                }
                .shadow(color: Color.chissPrimary.opacity(0.30), radius: 6)
                .alignmentGuide(.bottom) { d in d[.bottom] }
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Image previews (if any)
                ForEach(message.images) { img in
                    MessageImagePreview(imageBlock: img)
                        .padding(.bottom, message.text.isEmpty ? 0 : 4)
                }

                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 13))
                        .foregroundColor(isUser ? .white : Color.white.opacity(0.90))
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(isUser
                                    ? LinearGradient(colors: [Color.chissDeep, Color(red: 0.12, green: 0.22, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [Color.obsidianMid, Color.obsidianMid], startPoint: .top, endPoint: .bottom))
                                .shadow(color: isUser ? Color.chissPrimary.opacity(0.18) : .clear, radius: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(isUser ? Color.chissPrimary.opacity(0.28) : Color.chissPrimary.opacity(0.12), lineWidth: 1)
                        )
                }

                if let model = message.model, !model.isEmpty, !isUser {
                    Text(model.components(separatedBy: "/").last ?? model)
                        .font(.system(size: 9.5))
                        .foregroundColor(Color.chissPrimary.opacity(0.40))
                }
            }

            if !isUser { Spacer(minLength: 60) }
            if isUser {
                ZStack {
                    Circle().fill(Color.white.opacity(0.10)).frame(width: 28, height: 28)
                    Text("A").font(.system(size: 12, weight: .bold)).foregroundColor(Color.white.opacity(0.60))
                }
                .alignmentGuide(.bottom) { d in d[.bottom] }
            }
        }
    }
}

private struct PrimaryStreamingBubble: View {
    let text: String
    var agentInitial: String = "T"

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack {
                Circle().fill(Color.chissDeep).frame(width: 28, height: 28)
                    .shadow(color: Color.chissPrimary.opacity(0.40), radius: 8)
                Text(agentInitial).font(.system(size: 13, weight: .bold, design: .serif)).foregroundColor(Color.chissPrimary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(text.isEmpty ? " " : text)
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.90))
                        .textSelection(.enabled)
                    if text.isEmpty {
                        ProgressView().progressViewStyle(.circular).scaleEffect(0.50).tint(Color.chissPrimary)
                    } else {
                        Rectangle()
                            .fill(Color.chissPrimary)
                            .frame(width: 2, height: 14)
                            .opacity(0.80)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.obsidianMid)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.chissPrimary.opacity(0.22), lineWidth: 1))
                )
                Text("streaming…")
                    .font(.system(size: 9.5))
                    .foregroundColor(Color.chissPrimary.opacity(0.45))
            }
            Spacer(minLength: 60)
        }
    }
}

// MARK: - Message Image Preview

/// Renders an inline image preview inside a chat bubble.
/// Handles both pre-decoded NSImage (from base64) and URL-loaded images.
struct MessageImagePreview: View {
    let imageBlock: MessageImageBlock
    @State private var loadedImage: NSImage?
    @State private var isExpanded = false

    var displayImage: NSImage? { imageBlock.image ?? loadedImage }

    var body: some View {
        Group {
            if let img = displayImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: isExpanded ? .fit : .fill)
                    .frame(maxWidth: isExpanded ? 600 : 280, maxHeight: isExpanded ? 500 : 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.chissPrimary.opacity(0.20), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.30), radius: 6)
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }
                    .help("Click to \(isExpanded ? "shrink" : "expand")")
            } else if imageBlock.imageURL != nil {
                // Loading state for URL images
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.obsidianMid)
                    .frame(width: 280, height: 120)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.6)
                            .tint(Color.chissPrimary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.chissPrimary.opacity(0.15), lineWidth: 1)
                    )
            }
        }
        .onAppear { loadURLImageIfNeeded() }
    }

    private func loadURLImageIfNeeded() {
        guard let url = imageBlock.imageURL, imageBlock.image == nil, loadedImage == nil else { return }
        Task.detached(priority: .userInitiated) {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            guard let img = NSImage(data: data) else { return }
            Task { @MainActor in loadedImage = img }
        }
    }
}

private struct PrimaryThinkingBubble: View {
    var agentInitial: String = "T"
    @State private var dotOpacity: [Double] = [0.3, 0.3, 0.3]

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack {
                Circle().fill(Color.chissDeep).frame(width: 28, height: 28)
                    .shadow(color: Color.chissPrimary.opacity(0.40), radius: 8)
                Text(agentInitial).font(.system(size: 13, weight: .bold, design: .serif)).foregroundColor(Color.chissPrimary)
            }
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.chissPrimary)
                        .frame(width: 6, height: 6)
                        .opacity(dotOpacity[i])
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.obsidianMid)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.chissPrimary.opacity(0.18), lineWidth: 1))
            )
            Spacer(minLength: 60)
        }
        .onAppear {
            animateDots()
        }
    }

    private func animateDots() {
        for i in 0..<3 {
            withAnimation(Animation.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.18)) {
                dotOpacity[i] = 1.0
            }
        }
    }
}
