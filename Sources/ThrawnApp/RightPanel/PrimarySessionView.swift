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
    /// Agent ID for specialist chats. Nil = Thrawn (main chat).
    let agentId: String?
    private var ollamaClient: OllamaClient?
    private var openaiClient: OpenAIClient?
    private var openClawClient: GatewayWSClient?
    private weak var agentRuntime: AgentRuntimeCoordinator?
    private weak var devOpsBrain: DevOpsBrainStore?
    private weak var rosterStore: AgentRosterStore?
    private weak var screenCaptureStore: ScreenCaptureStore?
    private weak var executionService: ExecutionService?
    let cogneeClient = CogneeClient()
    /// Conversation history for Ollama
    private var conversationHistory: [OllamaMessage] = []
    private let conversationFileURL: URL
    /// Max tool execution rounds per user message (prevent infinite loops)
    private let maxToolRounds = 8

    init(
        sessionKey: String = "main",
        agentId: String? = nil,
        storageRoot: URL = ThrawnPaths.appSupportDir
            .appendingPathComponent("agent-conversations", isDirectory: true)
    ) {
        self.sessionKey = sessionKey
        self.agentId = agentId
        let identity = "\(agentId ?? "thrawn")-\(sessionKey)"
        let safeIdentity = identity.map {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-"
        }
        self.conversationFileURL = storageRoot
            .appendingPathComponent(String(safeIdentity).lowercased())
            .appendingPathExtension("json")
        SystemPromptBuilder.ensureWorkspaceDirs()
        loadConversation()
    }

    func bind(ollamaClient: OllamaClient) {
        self.ollamaClient = ollamaClient
    }

    func bindOpenAI(_ client: OpenAIClient) {
        self.openaiClient = client
    }

    func bindOpenClaw(_ client: GatewayWSClient) {
        self.openClawClient = client
    }

    func bindAgentRuntime(_ runtime: AgentRuntimeCoordinator) {
        self.agentRuntime = runtime
    }

    func bindDevOpsBrain(_ store: DevOpsBrainStore) {
        self.devOpsBrain = store
    }

    func bindRoster(_ roster: AgentRosterStore) {
        self.rosterStore = roster
    }

    func bindScreenCapture(_ store: ScreenCaptureStore) {
        self.screenCaptureStore = store
    }

    func bindExecution(_ service: ExecutionService) {
        self.executionService = service
    }

    func connect() {
        let resolvedAgentID = agentId ?? "thrawn"
        let backend = resolveRoute().backend
        if agentRuntime?.isReady(backend, agentID: resolvedAgentID) == true {
            isConnected = true
            return
        }
        if openaiClient?.apiKeyConfigured == true {
            isConnected = true
            return
        }
        isConnected = false
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMsg = PrimaryMessage(role: .user, text: trimmed)
        messages.append(userMsg)
        saveConversation()
        isLoading = true
        isStreaming = false
        streamingText = ""
        errorText = nil

        let route = resolveRoute()
        switch route.backend {
        case .codex, .grok, .claude:
            guard agentRuntime?.isReady(
                route.backend,
                agentID: agentId ?? "thrawn"
            ) == true else {
                errorText = "\(route.backend.gatewayDisplayName) runtime is unavailable. Confirm its CLI is installed and signed in."
                isLoading = false
                return
            }
        case .xai:
            guard let openai = openaiClient, openai.hasAPIKey(service: ProviderRouter.xaiKeychainService) else {
                errorText = "xAI key not configured for this agent."
                isLoading = false
                return
            }
        case .openclaw:
            guard openClawClient != nil else {
                errorText = "OpenClaw gateway client not available."
                isLoading = false
                return
            }
        case .openai:
            guard let openai = openaiClient, openai.apiKeyConfigured else {
                errorText = "GLM-5.2 key not configured. Add your Z.ai key in Settings."
                isLoading = false
                return
            }
        case .ollama:
            guard ollamaClient != nil, ollamaClient?.connected == true else {
                errorText = "Ollama not connected. Make sure Ollama is running on localhost:11434."
                isLoading = false
                return
            }
        }

        Task { await doSendRouted(trimmed, route: route) }
    }

    // MARK: - Route Resolution
    //
    // For specialist agent chats, check their spec tier and resolve to a
    // concrete backend. Main chat is Thrawn, so it uses Thrawn's configured
    // tier instead of forcing the local Ollama path.

    private func resolveRoute() -> RoutedProvider {
        let resolvedAgentId = agentId ?? "thrawn"
        if let override = ToolRegistry.specStore?.spec(id: resolvedAgentId)?.modelOverride {
            return RoutedProvider(
                backend: override.provider,
                model: override.model,
                isFallback: false,
                reasoningEffort: override.reasoningEffort,
                allowFallback: override.allowFallback
            )
        }
        if Self.isThrawnCoreAgent(resolvedAgentId) {
            return ProviderRouter.thrawnCoreRoute(openAIConfigured: openaiClient?.apiKeyConfigured ?? false)
        }
        if Self.usesSharedDevOpsBrain(resolvedAgentId),
           let devOpsBrain {
            return devOpsBrain.route(openAIConfigured: openaiClient?.apiKeyConfigured ?? false)
        }
        guard let specStore = ToolRegistry.specStore else {
            return resolveConcreteRoute(for: .premium)
        }
        let tier = specStore.resolvedTier(forAgentId: resolvedAgentId)
        return resolveConcreteRoute(for: tier)
    }

    private func resolveConcreteRoute(for tier: ModelTier) -> RoutedProvider {
        ProviderRouter().resolve(tier: tier)
    }

    private static func usesSharedDevOpsBrain(_ agentId: String) -> Bool {
        false
    }

    private static func isThrawnCoreAgent(_ agentId: String) -> Bool {
        agentId == "thrawn"
    }

    // MARK: - Routed Send (with tool execution loop)

    private func doSendRouted(_ text: String, route: RoutedProvider) async {
        guard ollamaClient != nil || openaiClient != nil || openClawClient != nil || agentRuntime != nil else {
            errorText = "No agent runtime or API fallback is available."
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

        // Build system prompt — agent-specific for specialist chats,
        // Thrawn identity for the main command session.
        let accessMode = executionService?.accessMode ?? .fullOperation
        let modelLabel: String
        switch route.backend {
        case .codex:   modelLabel = agentRuntime?.runtimeLabel ?? "Codex CLI"
        case .grok:    modelLabel = "Grok CLI · \(route.model)"
        case .claude:  modelLabel = "Claude Code · \(route.model)"
        case .xai:     modelLabel = "xAI (\(ProviderRouter.xaiModel))"
        case .ollama:  modelLabel = "Ollama (\(ollamaClient?.selectedModel ?? ProviderRouter.localModel))"
        case .openclaw: modelLabel = "OpenClaw legacy (\(ProviderRouter.premiumOpenClawLabel))"
        case .openai:  modelLabel = "GLM (\(ProviderRouter.premiumOpenAILabel))"
        }
        let systemPrompt: String
        if let agentId {
            systemPrompt = SystemPromptBuilder.buildAgentPrompt(
                agentId: agentId,
                accessMode: accessMode,
                modelLabel: modelLabel
            )
        } else {
            systemPrompt = SystemPromptBuilder.buildMainPrompt(
                accessMode: accessMode,
                modelLabel: modelLabel
            )
        }

        // Track in conversation history
        conversationHistory.append(OllamaMessage(role: "user", text: finalText))
        saveConversation()

        // === ReAct Loop: send → get response → extract tools → execute → feed back → repeat ===
        var currentText = finalText
        var currentImage = imagePayload
        var toolRound = 0

        while toolRound < maxToolRounds {
            let history = conversationHistory.count > 1 ? Array(conversationHistory.dropLast()) : []

            // Send to the resolved backend and wait for full response
            let response: SendResult
            switch route.backend {
            case .codex, .grok, .claude:
                response = await sendAndWaitAgentRuntime(
                    text: currentText,
                    systemPrompt: systemPrompt,
                    route: route
                )
            case .openclaw:
                let openClawResponse = await sendAndWaitOpenClaw(
                    text: currentText,
                    model: route.model
                )
                response = openClawResponse
            case .openai, .xai:
                response = await sendAndWaitOpenAI(
                    text: currentText,
                    history: history,
                    systemPrompt: systemPrompt,
                    route: route
                )
            case .ollama:
                response = await sendAndWait(
                    client: ollamaClient!,
                    text: currentText,
                    imageData: currentImage,
                    history: history,
                    systemPrompt: systemPrompt,
                    model: route.model
                )
            }

            // Clear image after first round
            currentImage = nil

            switch response {
            case .success(let text, let model):
                // Add assistant response to history
                conversationHistory.append(OllamaMessage(role: "assistant", text: text))

                // Show the response in the UI
                messages.append(PrimaryMessage(role: .assistant, text: text, model: model))
                saveConversation()

                // Codex and Grok are complete agent runtimes. Their own tools,
                // permissions, and continuation semantics are authoritative;
                // never wrap their output in the legacy fenced-bash loop.
                if route.backend.isSubscriptionGateway {
                    isLoading = false
                    isStreaming = false
                    streamingText = ""
                    rosterStore?.markSessionComplete(sessionKey, detail: "Response received")
                    return
                }

                // Extract bash commands from the response
                let commands = AgentScheduler.extractBashCommands(from: text)

                guard !commands.isEmpty else {
                    isLoading = false
                    isStreaming = false
                    streamingText = ""
                    rosterStore?.markSessionComplete(sessionKey, detail: "Response received")
                    return
                }
                guard let exec = executionService else {
                    errorText = "Execution service is not available."
                    isLoading = false
                    isStreaming = false
                    streamingText = ""
                    rosterStore?.markSessionComplete(sessionKey, detail: "Execution unavailable")
                    return
                }

                // Execute commands and collect results
                var toolResults: [String] = []
                for command in commands {
                    rosterStore?.markSessionActive(sessionKey, detail: "Executing: \(String(command.prefix(40)))…")

                    let result = await exec.run(command, agentId: "thrawn")

                    var resultBlock = "$ \(command)\n"
                    if !result.stdout.isEmpty {
                        resultBlock += result.stdout
                    }
                    if !result.stderr.isEmpty {
                        resultBlock += (result.stdout.isEmpty ? "" : "\n") + "[stderr] \(result.stderr)"
                    }
                    resultBlock += "\n[exit code: \(result.exitCode)]"
                    toolResults.append(resultBlock)
                }

                // Show tool output in the UI
                let toolOutputText = toolResults.joined(separator: "\n\n")
                messages.append(PrimaryMessage(role: .user, text: "```\n\(toolOutputText)\n```", model: nil))

                // Feed tool results back to the model as the next user message
                let feedbackText = """
                [TOOL EXECUTION RESULTS]
                The following commands were executed on the host system:

                \(toolOutputText)

                [END TOOL RESULTS]
                Continue with the task. If more commands are needed, output them in ```bash fences. \
                If the task is complete, summarize what was done.
                """

                conversationHistory.append(OllamaMessage(role: "user", text: feedbackText))
                saveConversation()
                currentText = feedbackText
                toolRound += 1

                // Brief pause between rounds
                try? await Task.sleep(nanoseconds: 200_000_000)

            case .failure(let error):
                // Remove the failed user message from history
                if conversationHistory.last?.role == "user" {
                    conversationHistory.removeLast()
                }
                saveConversation()
                errorText = error
                isLoading = false
                isStreaming = false
                streamingText = ""
                rosterStore?.markSessionError(sessionKey, detail: error)
                return
            }
        }

        // Hit max tool rounds
        messages.append(PrimaryMessage(
            role: .assistant,
            text: "[Tool execution limit reached (\(maxToolRounds) rounds). Pausing for Commander input.]",
            model: nil
        ))
        saveConversation()
        isLoading = false
        isStreaming = false
        streamingText = ""
    }

    // MARK: - Send and Wait Helper

    private enum SendResult {
        case success(String, String?)
        case failure(String)
    }

    private func sendAndWait(
        client: OllamaClient,
        text: String,
        imageData: Data?,
        history: [OllamaMessage],
        systemPrompt: String,
        model: String? = nil
    ) async -> SendResult {
        await withCheckedContinuation { continuation in
            var resumed = false
            self.streamingText = ""

            client.send(
                text: text,
                imageData: imageData,
                history: history,
                systemPrompt: systemPrompt,
                sessionKey: sessionKey,
                model: model,
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
                        self.isStreaming = false
                        self.streamingText = ""
                        if !resumed { resumed = true; continuation.resume(returning: .success(text, model)) }
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.isStreaming = false
                        self.streamingText = ""
                        if !resumed { resumed = true; continuation.resume(returning: .failure(error)) }
                    }
                }
            )
        }
    }

    // MARK: - Subscription Agent Runtime Send and Wait

    private func sendAndWaitAgentRuntime(
        text: String,
        systemPrompt: String,
        route: RoutedProvider
    ) async -> SendResult {
        guard let agentRuntime else {
            return .failure("\(route.backend.gatewayDisplayName) runtime is unavailable.")
        }
        self.streamingText = ""
        do {
            let result = try await agentRuntime.run(
                prompt: text,
                options: AgentSessionOptions(
                    sessionKey: "primary:\(sessionKey)",
                    agentID: agentId ?? "thrawn",
                    provider: route.backend,
                    developerInstructions: systemPrompt,
                    model: route.model,
                    reasoningEffort: route.reasoningEffort,
                    approvalPolicy: .onRequest,
                    sandbox: .fullOperation
                )
            ) { [weak self] event in
                guard let self else { return }
                switch event {
                case .textDelta(let delta):
                    self.isStreaming = true
                    self.streamingText += delta
                case .approvalRequired(let approval):
                    self.errorText = "Approval required: \(approval.title)"
                case .error(let detail):
                    self.errorText = detail
                case .reasoningDelta, .toolCall, .fileChange, .usage, .completed:
                    break
                }
            }
            let finalText = result.text.isEmpty ? streamingText : result.text
            isStreaming = false
            streamingText = ""
            return .success(finalText, result.model)
        } catch {
            isStreaming = false
            streamingText = ""
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - OpenClaw Send and Wait

    private func sendAndWaitOpenClaw(
        text: String,
        model: String
    ) async -> SendResult {
        guard let client = openClawClient else { return .failure("OpenClaw client not available.") }
        return await withCheckedContinuation { continuation in
            var resumed = false
            self.streamingText = ""
            client.send(
                text: text,
                sessionKey: "thrawn-primary-\(sessionKey)",
                model: model,
                thinking: ProviderRouter.premiumOpenClawThinkingLevel,
                onDelta: { [weak self] delta in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.isStreaming = true
                        self.streamingText += delta
                    }
                },
                onComplete: { [weak self] finalText, returnedModel in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let text = finalText.isEmpty ? self.streamingText : finalText
                        self.isStreaming = false
                        self.streamingText = ""
                        if !resumed { resumed = true; continuation.resume(returning: .success(text, returnedModel ?? model)) }
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.isStreaming = false
                        self.streamingText = ""
                        if !resumed { resumed = true; continuation.resume(returning: .failure(error)) }
                    }
                }
            )
        }
    }

    // MARK: - OpenAI Send and Wait

    private func sendAndWaitOpenAI(
        text: String,
        history: [OllamaMessage],
        systemPrompt: String,
        route: RoutedProvider
    ) async -> SendResult {
        guard let client = openaiClient else { return .failure("OpenAI client not available.") }
        let openaiHistory = history.map { OpenAIMessage(role: $0.role, text: $0.content) }
        return await withCheckedContinuation { continuation in
            var resumed = false
            self.streamingText = ""
            let providerLabel = route.backend == .xai ? "xAI" : "GLM"
            client.send(
                text: text,
                history: openaiHistory,
                systemPrompt: systemPrompt,
                sessionKey: sessionKey,
                modelOverride: route.model,
                reasoningEffortOverride: route.reasoningEffort,
                baseURLOverride: route.backend == .xai ? ProviderRouter.xaiBaseURL : nil,
                apiKeyServiceOverride: route.backend == .xai ? ProviderRouter.xaiKeychainService : nil,
                providerLabel: providerLabel,
                includeReasoningControls: route.backend != .xai,
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
                        self.isStreaming = false
                        self.streamingText = ""
                        if !resumed { resumed = true; continuation.resume(returning: .success(text, model ?? ProviderRouter.premiumOpenAIModel)) }
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.isStreaming = false
                        self.streamingText = ""
                        if !resumed { resumed = true; continuation.resume(returning: .failure(error)) }
                    }
                }
            )
        }
    }

    func abort() {
        Task { [weak agentRuntime] in
            await agentRuntime?.cancel(sessionKey: "primary:\(sessionKey)")
        }
        ollamaClient?.cancelAll()
        isLoading = false
        isStreaming = false
        streamingText = ""
    }

    private struct ConversationSnapshot: Codable {
        let messages: [PrimaryMessage]
        let history: [OllamaMessage]
    }

    private func loadConversation() {
        guard let data = try? Data(contentsOf: conversationFileURL),
              let snapshot = try? JSONDecoder().decode(
                  ConversationSnapshot.self,
                  from: data
              ) else {
            return
        }
        messages = snapshot.messages
        conversationHistory = snapshot.history
    }

    private func saveConversation() {
        do {
            try FileManager.default.createDirectory(
                at: conversationFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let snapshot = ConversationSnapshot(
                messages: messages,
                history: conversationHistory
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: conversationFileURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: conversationFileURL.path
            )
        } catch {
            FlightRecorder.logError(
                source: "agent-conversation:\(agentId ?? "thrawn")",
                message: "Could not persist local context: \(error.localizedDescription)"
            )
        }
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

struct PrimaryMessage: Identifiable, Codable {
    let id: UUID
    var role: MessageRole
    var text: String
    var model: String?
    var timestamp: Date?
    var images: [MessageImageBlock] = []

    init(
        id: UUID = UUID(),
        role: MessageRole,
        text: String,
        model: String? = nil,
        timestamp: Date? = nil,
        images: [MessageImageBlock] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.model = model
        self.timestamp = timestamp
        self.images = images
    }

    enum MessageRole: String, Codable, Equatable {
        case user
        case assistant
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case model
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        role = try values.decode(MessageRole.self, forKey: .role)
        text = try values.decode(String.self, forKey: .text)
        model = try values.decodeIfPresent(String.self, forKey: .model)
        timestamp = try values.decodeIfPresent(Date.self, forKey: .timestamp)
        images = []
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(role, forKey: .role)
        try values.encode(text, forKey: .text)
        try values.encodeIfPresent(model, forKey: .model)
        try values.encodeIfPresent(timestamp, forKey: .timestamp)
    }
}

// MARK: - Primary Session View

struct PrimarySessionView: View {
    @EnvironmentObject var ollama: OllamaClient
    @EnvironmentObject var openai: OpenAIClient
    @EnvironmentObject var openclaw: GatewayWSClient
    @EnvironmentObject var agentRuntime: AgentRuntimeCoordinator
    @EnvironmentObject var devOpsBrain: DevOpsBrainStore
    @EnvironmentObject var bootstrap: ThrawnBootstrap
    @EnvironmentObject var roster: AgentRosterStore
    @EnvironmentObject var screenCapture: ScreenCaptureStore
    @EnvironmentObject var execution: ExecutionService
    @StateObject private var store: PrimarySessionStore
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool
    @State private var scrollTarget: UUID?

    let agentName: String
    let agentInitial: String
    let agentId: String?

    init(sessionKey: String = "main", agentName: String = "Thrawn", agentInitial: String = "T", agentId: String? = nil) {
        _store = StateObject(wrappedValue: PrimarySessionStore(sessionKey: sessionKey, agentId: agentId))
        self.agentName = agentName
        self.agentInitial = agentInitial
        self.agentId = agentId
    }

    var body: some View {
        ZStack {
            Color.obsidian.ignoresSafeArea()

            VStack(spacing: 0) {
                // Connection status bar (only shown when not connected)
                if !brainConnected {
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
                                PrimaryStreamingBubble(text: store.streamingText, agentName: agentName, agentInitial: agentInitial)
                                    .id("streaming")
                            } else if store.isLoading {
                                PrimaryThinkingBubble(agentName: agentName, agentInitial: agentInitial)
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
                        if err.contains("No provider connected") || err.contains("API client not available") {
                            Button {
                                store.errorText = nil
                                bootstrap.showSetup = true
                            } label: {
                                Text("Open Settings")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color.sithGlow)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.sithGlow.opacity(0.50), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
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
            .animation(.easeInOut(duration: 0.18), value: brainConnected)
            .animation(.easeInOut(duration: 0.18), value: store.errorText != nil)
            .animation(.easeInOut(duration: 0.18), value: store.recallContext != nil)
            .animation(.easeInOut(duration: 0.18), value: screenCapture.pendingScreenshot != nil)
        }
        .onAppear {
            store.bind(ollamaClient: ollama)
            store.bindOpenAI(openai)
            store.bindOpenClaw(openclaw)
            store.bindAgentRuntime(agentRuntime)
            store.bindDevOpsBrain(devOpsBrain)
            store.bindRoster(roster)
            store.bindScreenCapture(screenCapture)
            store.bindExecution(execution)
            store.connect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                inputFocused = true
            }
        }
    }

    private var connectionStatusText: String {
        let backend = resolvedSessionBackend
        let resolvedAgentID = agentId ?? "thrawn"
        let status = agentRuntime.status(for: backend, agentID: resolvedAgentID)
        if backend == .grok || backend == .claude {
            return status.detail
        }
        if status.state == .ready {
            let account = status.account?.displayName ?? "Codex"
            return "\(account) · \(agentRuntime.runtimeLabel)"
        }
        if status.state == .starting {
            return "Starting Codex agent runtime…"
        }
        return status.detail
    }

    private var brainConnected: Bool {
        agentRuntime.isReady(
            resolvedSessionBackend,
            agentID: agentId ?? "thrawn"
        )
    }

    private var isThrawnCoreSession: Bool {
        let id = agentId ?? "thrawn"
        return id == "thrawn"
    }

    private var isStevenSession: Bool {
        agentId == "steven"
    }

    private var resolvedSessionBackend: ProviderBackend {
        let resolvedAgentID = agentId ?? "thrawn"
        return ToolRegistry.specStore?
            .spec(id: resolvedAgentID)?
            .modelOverride?
            .provider ?? .codex
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
    let agentName: String
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
                    Text(agentName.uppercased())
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .tracking(1.4)
                        .foregroundColor(Color.chissPrimary.opacity(0.62))
                    ThrawnActivitySpinner(active: true, diameter: 14, lineWidth: 2.0, trackOpacity: 0.18)
                }

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
    let agentName: String
    var agentInitial: String = "T"

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack {
                Circle().fill(Color.chissDeep).frame(width: 28, height: 28)
                    .shadow(color: Color.chissPrimary.opacity(0.40), radius: 8)
                Text(agentInitial).font(.system(size: 13, weight: .bold, design: .serif)).foregroundColor(Color.chissPrimary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(agentName.uppercased())
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .tracking(1.4)
                        .foregroundColor(Color.chissPrimary.opacity(0.62))
                    ThrawnActivitySpinner(active: true, diameter: 14, lineWidth: 2.0, trackOpacity: 0.18)
                }

                Text("\(agentName) is working...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.82))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.obsidianMid)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.chissPrimary.opacity(0.18), lineWidth: 1))
            )
            Spacer(minLength: 60)
        }
    }
}
