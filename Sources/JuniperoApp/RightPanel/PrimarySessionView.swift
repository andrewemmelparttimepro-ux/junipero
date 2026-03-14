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

    private let sessionKey = "main"
    var wsClient: GatewayWSClient

    init(wsClient: GatewayWSClient) {
        self.wsClient = wsClient
    }

    func connect() {
        if !wsClient.connected {
            wsClient.connect()
        }
        // Poll for connection
        Task {
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 150_000_000)
                if wsClient.connected { break }
            }
            isConnected = wsClient.connected
            if isConnected {
                loadHistory()
            }
        }
    }

    func loadHistory() {
        wsClient.fetchHistory(sessionKey: sessionKey) { [weak self] entries in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.messages = entries.compactMap { entry in
                    let text = entry.resolvedContent
                    guard !text.isEmpty else { return nil }
                    return PrimaryMessage(
                        role: entry.role == "assistant" ? .assistant : .user,
                        text: text,
                        model: entry.model,
                        timestamp: Self.parseDate(entry.createdAt)
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

        // Ensure connected
        if !wsClient.connected {
            wsClient.connect()
            Task {
                for _ in 0..<40 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    if wsClient.connected { break }
                }
                await self.doSend(trimmed)
            }
        } else {
            Task { await doSend(trimmed) }
        }
    }

    private func doSend(_ text: String) async {
        await withCheckedContinuation { continuation in
            var resumed = false
            wsClient.send(
                text: text,
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
                        if !resumed { resumed = true; continuation.resume() }
                    }
                }
            )
        }
    }

    func abort() {
        wsClient.abort(sessionKey: sessionKey)
        isLoading = false
        isStreaming = false
        streamingText = ""
    }

    private static func parseDate(_ str: String?) -> Date? {
        guard let str else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: str) ?? ISO8601DateFormatter().date(from: str)
    }
}

// MARK: - Message Model

struct PrimaryMessage: Identifiable {
    let id = UUID()
    var role: MessageRole
    var text: String
    var model: String?
    var timestamp: Date?

    enum MessageRole {
        case user, assistant
    }
}

// MARK: - Primary Session View

struct PrimarySessionView: View {
    @EnvironmentObject var gatewayWS: GatewayWSClient
    @EnvironmentObject var bootstrap: ThrawnBootstrap
    @StateObject private var store: PrimarySessionStore
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool
    @State private var scrollTarget: UUID?

    init() {
        // Store gets injected via onAppear with the shared wsClient
        _store = StateObject(wrappedValue: PrimarySessionStore(wsClient: GatewayWSClient()))
    }

    var body: some View {
        ZStack {
            Color.obsidian.ignoresSafeArea()

            VStack(spacing: 0) {
                // Connection status bar (only shown when not connected)
                if !gatewayWS.connected {
                    HStack(spacing: 8) {
                        ProgressView().progressViewStyle(.circular).scaleEffect(0.6).tint(Color(red: 0.95, green: 0.70, blue: 0.20))
                        Text(gatewayWS.authenticating ? "Connecting to OpenClaw…" : "Reconnecting…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 0.95, green: 0.70, blue: 0.20))
                        Spacer()
                    }
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Color(red: 0.95, green: 0.70, blue: 0.20).opacity(0.10))
                    .overlay(alignment: .bottom) { Rectangle().fill(Color(red: 0.95, green: 0.70, blue: 0.20).opacity(0.20)).frame(height: 1) }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            if store.messages.isEmpty && !store.isLoading {
                                ThrawnWelcomePrompt()
                                    .padding(.top, 60)
                            }

                            ForEach(store.messages) { msg in
                                PrimaryMessageBubble(message: msg)
                                    .id(msg.id)
                            }

                            if store.isStreaming {
                                PrimaryStreamingBubble(text: store.streamingText)
                                    .id("streaming")
                            } else if store.isLoading {
                                PrimaryThinkingBubble()
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
            .animation(.easeInOut(duration: 0.18), value: gatewayWS.connected)
            .animation(.easeInOut(duration: 0.18), value: store.errorText != nil)
        }
        .onAppear {
            // Re-init store with the real shared wsClient
            store.wsClient = gatewayWS
            store.connect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                inputFocused = true
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.chissPrimary.opacity(0.12))
                .frame(height: 1)

            HStack(alignment: .bottom, spacing: 12) {
                TextField("Command Thrawn…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.92))
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .onSubmit { if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { send() } }

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
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.chissDeep)
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.chissPrimary.opacity(0.40), radius: 18)
                Text("T")
                    .font(.system(size: 32, weight: .bold, design: .serif))
                    .foregroundColor(Color.chissPrimary)
            }
            Text("Thrawn Command Console")
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

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isUser { Spacer(minLength: 60) }

            if !isUser {
                ZStack {
                    Circle().fill(Color.chissDeep).frame(width: 28, height: 28)
                    Text("T").font(.system(size: 13, weight: .bold, design: .serif)).foregroundColor(Color.chissPrimary)
                }
                .shadow(color: Color.chissPrimary.opacity(0.30), radius: 6)
                .alignmentGuide(.bottom) { d in d[.bottom] }
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
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

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack {
                Circle().fill(Color.chissDeep).frame(width: 28, height: 28)
                    .shadow(color: Color.chissPrimary.opacity(0.40), radius: 8)
                Text("T").font(.system(size: 13, weight: .bold, design: .serif)).foregroundColor(Color.chissPrimary)
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
                        // Blinking cursor
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

private struct PrimaryThinkingBubble: View {
    @State private var dotOpacity: [Double] = [0.3, 0.3, 0.3]

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack {
                Circle().fill(Color.chissDeep).frame(width: 28, height: 28)
                    .shadow(color: Color.chissPrimary.opacity(0.40), radius: 8)
                Text("T").font(.system(size: 13, weight: .bold, design: .serif)).foregroundColor(Color.chissPrimary)
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
