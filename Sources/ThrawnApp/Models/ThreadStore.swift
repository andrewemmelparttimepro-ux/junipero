import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ThreadStore: ObservableObject {
    enum Connectivity {
        case unknown
        case online
        case offline
    }

    @Published var threads: [ChatThread] = []
    @Published var selectedThreadId: UUID?
    @Published var allThreadsMode: Bool = false
    @Published var connectivity: Connectivity = .unknown
    @Published var inFlightCount: Int = 0
    @Published var lastErrorText: String?
    @Published var popupDraftText: String = ""
    @Published var popupAttachments: [ChatAttachment] = []

    private let storageURL: URL
    private let draftStateURL: URL
    private let draftEventLogURL: URL
    private let storageDir: URL
    private let maxStoredThreads = 200
    private var maxMessageLength = 4000
    private var maxInputHistoryMessages = 36
    private var maxTotalInputChars = 16_000
    private var maxQueuedPerThread = 6
    private var inFlightTasks: [UUID: Task<Void, Never>] = [:]
    /// Native Anthropic API client — set via `bindAnthropicClient(_:)` from app entry.
    /// Falls back to a local instance if not bound (shouldn't happen in normal flow).
    private(set) var anthropic: AnthropicClient?
    /// Gemini API client — set via `bindGeminiClient(_:)` from app entry.
    private(set) var geminiClient: GeminiAPIClient?
    private(set) var geminiOAuth: GeminiOAuthClient?
    /// OpenAI API client — set via `bindOpenAIClient(_:)` from app entry.
    private(set) var openAIClient: OpenAIClient?
    /// Legacy gateway client — kept temporarily for backward compat. Will be removed.
    let gatewayWS = GatewayWSClient()
    private var threadDrafts: [UUID: String] = [:]
    private var threadAttachments: [UUID: [ChatAttachment]] = [:]
    private var queuedUserMessages: [UUID: [String]] = [:]
    private var draftSnapshotTask: Task<Void, Never>?
    private var preferenceObserver: NSObjectProtocol?

    private struct DraftState: Codable {
        var popupDraftText: String
        var popupAttachments: [ChatAttachment]
        var threadDrafts: [String: String]
        var threadAttachments: [String: [ChatAttachment]]
        var queuedMessages: [String: [String]]

        init(
            popupDraftText: String,
            popupAttachments: [ChatAttachment],
            threadDrafts: [String: String],
            threadAttachments: [String: [ChatAttachment]],
            queuedMessages: [String: [String]]
        ) {
            self.popupDraftText = popupDraftText
            self.popupAttachments = popupAttachments
            self.threadDrafts = threadDrafts
            self.threadAttachments = threadAttachments
            self.queuedMessages = queuedMessages
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.popupDraftText = try c.decodeIfPresent(String.self, forKey: .popupDraftText) ?? ""
            self.popupAttachments = try c.decodeIfPresent([ChatAttachment].self, forKey: .popupAttachments) ?? []
            self.threadDrafts = try c.decodeIfPresent([String: String].self, forKey: .threadDrafts) ?? [:]
            self.threadAttachments = try c.decodeIfPresent([String: [ChatAttachment]].self, forKey: .threadAttachments) ?? [:]
            self.queuedMessages = try c.decodeIfPresent([String: [String]].self, forKey: .queuedMessages) ?? [:]
        }
    }

    private struct DraftEvent: Codable {
        enum EventType: String, Codable {
            case popup
            case thread
            case clear
        }

        var type: EventType
        var threadId: String?
        var text: String
        var timestamp: Date
    }

    init() {
        self.storageDir = ThrawnPaths.appSupportDir
        self.storageURL = storageDir.appendingPathComponent("threads.json")
        self.draftStateURL = storageDir.appendingPathComponent("drafts.json")
        self.draftEventLogURL = storageDir.appendingPathComponent("draft-events.log")
        applyGuardrailPreset()
        preferenceObserver = NotificationCenter.default.addObserver(
            forName: ThrawnPreferencesStore.changedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyGuardrailPreset()
            }
        }
        loadThreads()
        loadDraftState()
    }

    /// Bind the shared AnthropicClient from the app entry point.
    func bindAnthropicClient(_ client: AnthropicClient) {
        self.anthropic = client
    }

    /// Bind the shared Gemini clients from the app entry point.
    func bindGeminiClient(_ client: GeminiAPIClient, oauth: GeminiOAuthClient) {
        self.geminiClient = client
        self.geminiOAuth = oauth
    }

    /// Bind the shared OpenAI client from the app entry point.
    func bindOpenAIClient(_ client: OpenAIClient) {
        self.openAIClient = client
    }

    deinit {
        if let preferenceObserver {
            NotificationCenter.default.removeObserver(preferenceObserver)
        }
    }

    var isSending: Bool {
        inFlightCount > 0
    }

    var unreadThreadCount: Int {
        threads.filter { $0.unreadCount > 0 }.count
    }

    func queuedCount(for threadId: UUID) -> Int {
        queuedUserMessages[threadId]?.count ?? 0
    }

    func clearQueuedMessages(for threadId: UUID) {
        queuedUserMessages.removeValue(forKey: threadId)
        scheduleDraftSnapshotSave()
    }

    func sendMessage(_ text: String, attachments: [ChatAttachment] = []) {
        ThrawnPreferencesStore.incrementInteraction()
        let trimmed = sanitize(text)
        let cleanAttachments = sanitizedAttachments(attachments)
        guard !trimmed.isEmpty || !cleanAttachments.isEmpty else { return }

        var thread = ChatThread(
            messages: [ChatMessage(role: .user, text: trimmed, attachments: cleanAttachments)],
            isLoading: true,
            state: .pending
        )
        let now = Date()
        thread.updatedAt = now
        threads.insert(thread, at: 0)
        threads = Array(threads.prefix(maxStoredThreads))
        selectedThreadId = thread.id
        saveThreads()
        runRequest(for: thread.id)
        updatePopupDraft("")
        clearPopupAttachments()
        Task { await ChatDiagnostics.shared.log("new-thread send thread=\(thread.id.uuidString) chars=\(trimmed.count)") }
    }

    func sendMessage(in threadId: UUID, text: String, attachments: [ChatAttachment] = []) {
        ThrawnPreferencesStore.incrementInteraction()
        let trimmed = sanitize(text)
        let cleanAttachments = sanitizedAttachments(attachments)
        guard !trimmed.isEmpty || !cleanAttachments.isEmpty else { return }
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        guard !threads[index].isLoading else {
            var queuedPayload = trimmed
            if !cleanAttachments.isEmpty {
                let attachmentBlock = cleanAttachments.map { $0.promptSegment }.joined(separator: "\n\n")
                queuedPayload = queuedPayload.isEmpty ? attachmentBlock : "\(queuedPayload)\n\n\(attachmentBlock)"
            }
            var queue = queuedUserMessages[threadId, default: []]
            queue.append(queuedPayload)
            queuedUserMessages[threadId] = Array(queue.suffix(maxQueuedPerThread))
            updateThreadDraft(threadId: threadId, text: "")
            if !cleanAttachments.isEmpty {
                clearAttachments(for: threadId)
            }
            lastErrorText = "Queued your message. It will send after the current reply."
            scheduleDraftSnapshotSave()
            Task { await ChatDiagnostics.shared.log("send-queued thread=\(threadId.uuidString) depth=\(queue.count)") }
            return
        }

        threads[index].messages.append(ChatMessage(role: .user, text: trimmed, attachments: cleanAttachments))
        threads[index].updatedAt = Date()
        threads[index].isLoading = true
        threads[index].state = .pending
        threads[index].errorMessage = nil
        threads[index].unreadCount = 0
        moveThreadToTop(threadId)
        selectedThreadId = threadId
        saveThreads()
        runRequest(for: threadId)
        updateThreadDraft(threadId: threadId, text: "")
        clearAttachments(for: threadId)
        Task { await ChatDiagnostics.shared.log("thread send thread=\(threadId.uuidString) chars=\(trimmed.count)") }
    }

    func retryThread(_ id: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[index].isLoading = true
        threads[index].state = .pending
        threads[index].errorMessage = nil
        threads[index].latencyMs = nil
        threads[index].updatedAt = Date()
        moveThreadToTop(id)
        selectedThreadId = id
        saveThreads()
        runRequest(for: id)
        Task { await ChatDiagnostics.shared.log("retry thread=\(id.uuidString)") }
    }

    func deleteThread(_ id: UUID) {
        cancelRequest(for: id)
        threads.removeAll { $0.id == id }
        queuedUserMessages.removeValue(forKey: id)
        if selectedThreadId == id {
            selectedThreadId = nil
        }
        saveThreads()
    }

    func clearAllThreads() {
        for id in inFlightTasks.keys {
            cancelRequest(for: id)
        }
        threads.removeAll()
        threadDrafts.removeAll()
        queuedUserMessages.removeAll()
        selectedThreadId = nil
        saveThreads()
        appendDraftEvent(type: .clear, threadId: nil, text: "")
        saveDraftState()
    }

    func cancelRequest(for id: UUID) {
        cancelTask(for: id, updateThreadState: true)
        Task { await ChatDiagnostics.shared.log("cancel thread=\(id.uuidString)") }
    }

    private func runRequest(for threadId: UUID) {
        // Cancel any existing task for this thread WITHOUT sending gateway abort.
        // Sending abort would kill the new request we're about to start (race condition).
        inFlightTasks[threadId]?.cancel()
        inFlightTasks[threadId] = nil
        inFlightCount = max(0, inFlightTasks.count)
        let messages = buildInputMessages(for: threadId)
        guard !messages.isEmpty else { return }
        Task { await ChatDiagnostics.shared.log("request-start thread=\(threadId.uuidString) msgs=\(messages.count)") }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRequest(threadId: threadId, messages: messages)
        }
        inFlightTasks[threadId] = task
        inFlightCount = inFlightTasks.count
    }

    private func performRequest(threadId: UUID, messages: [AnthropicMessage]) async {
        let startMs = Int(Date().timeIntervalSince1970 * 1000)
        let userText = messages.last(where: { $0.role == "user" })?.content.compactMap(\.text).joined(separator: "\n") ?? ""

        // Route based on ProviderStateStore's active provider
        let providerState = ProviderStateStore.load()
        let activeProvider = providerState.activeProvider

        // Try active provider first, then fall back to any connected provider
        switch activeProvider {
        case .gemini:
            if let client = geminiClient, (geminiOAuth?.authenticated == true || client.apiKeyConfigured) {
                await performGeminiRequest(client: client, threadId: threadId, userText: userText, startMs: startMs)
                return
            }
        case .claude:
            if let client = anthropic, client.apiKeyConfigured {
                await performAnthropicRequest(client: client, threadId: threadId, messages: messages, userText: userText, startMs: startMs)
                return
            }
        case .chatgpt:
            if let client = openAIClient, client.apiKeyConfigured {
                await performOpenAIRequest(client: client, threadId: threadId, userText: userText, startMs: startMs)
                return
            }
        }

        // Fallback: try any connected provider
        if let client = geminiClient, (geminiOAuth?.authenticated == true || client.apiKeyConfigured) {
            await performGeminiRequest(client: client, threadId: threadId, userText: userText, startMs: startMs)
            return
        }
        if let client = anthropic, client.apiKeyConfigured {
            await performAnthropicRequest(client: client, threadId: threadId, messages: messages, userText: userText, startMs: startMs)
            return
        }
        if let client = openAIClient, client.apiKeyConfigured {
            await performOpenAIRequest(client: client, threadId: threadId, userText: userText, startMs: startMs)
            return
        }

        // LEGACY FALLBACK: Gateway (will be removed)
        if !userText.isEmpty {
            if !gatewayWS.connected {
                gatewayWS.connect()
                gatewayWS.refreshNow()
                for _ in 0..<40 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    if gatewayWS.connected { break }
                }
            }

            if gatewayWS.connected {
                await performGatewayRequest(threadId: threadId, text: userText, startMs: startMs)
                return
            }
        }

        // No provider connected
        updateThreadFailure(threadId, error: "No provider connected. Open Settings to sign in with Google or add an API key.")
        inFlightTasks[threadId] = nil
        inFlightCount = inFlightTasks.count
    }

    // MARK: - Gemini API (Primary when signed in with Google)

    private func performGeminiRequest(client: GeminiAPIClient, threadId: UUID, userText: String, startMs: Int) async {
        let safetyTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let index = self.threads.firstIndex(where: { $0.id == threadId }),
                   self.threads[index].isLoading {
                    self.updateThreadFailure(threadId, error: "Request timed out after 10 minutes. Tap to retry.")
                    self.inFlightTasks[threadId] = nil
                    self.inFlightCount = self.inFlightTasks.count
                }
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            var accumulated = ""

            func safeResume() {
                guard !resumed else { return }
                resumed = true
                safetyTimeout.cancel()
                continuation.resume()
            }

            client.send(
                text: userText,
                systemPrompt: "You are Thrawn, a strategic AI command agent. You serve the user directly. Be precise, thorough, and proactive.",
                sessionKey: "thread:\(threadId.uuidString.lowercased())",
                onDelta: { [weak self] delta in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        accumulated += delta
                        if let index = self.threads.firstIndex(where: { $0.id == threadId }) {
                            if self.threads[index].messages.last?.role == .assistant {
                                let lastIdx = self.threads[index].messages.count - 1
                                self.threads[index].messages[lastIdx].text = accumulated
                            } else {
                                self.threads[index].messages.append(ChatMessage(role: .assistant, text: accumulated))
                            }
                        }
                    }
                },
                onComplete: { [weak self] finalText, model in
                    Task { @MainActor [weak self] in
                        let latencyMs = Int(Date().timeIntervalSince1970 * 1000) - startMs
                        let responseText = finalText.isEmpty ? accumulated : finalText
                        if let self {
                            self.updateThreadSuccess(threadId, response: responseText, model: model ?? "gemini", latencyMs: latencyMs)
                            self.connectivity = .online
                            self.lastErrorText = nil
                            self.inFlightTasks[threadId] = nil
                            self.inFlightCount = self.inFlightTasks.count
                        }
                        safeResume()
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        if let self {
                            self.updateThreadFailure(threadId, error: error)
                            self.connectivity = .offline
                            self.lastErrorText = error
                            self.inFlightTasks[threadId] = nil
                            self.inFlightCount = self.inFlightTasks.count
                        }
                        safeResume()
                    }
                }
            )
        }
    }

    // MARK: - Native Anthropic API (Primary Path)

    private func performAnthropicRequest(client: AnthropicClient, threadId: UUID, messages: [AnthropicMessage], userText: String, startMs: Int) async {
        // Build history: all messages except the last user message (which is the new one)
        let history = messages.count > 1 ? Array(messages.dropLast()) : []

        // Safety timeout: 10 minutes for complex tasks
        let safetyTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let index = self.threads.firstIndex(where: { $0.id == threadId }),
                   self.threads[index].isLoading {
                    self.updateThreadFailure(threadId, error: "Request timed out after 10 minutes. Tap to retry.")
                    self.inFlightTasks[threadId] = nil
                    self.inFlightCount = self.inFlightTasks.count
                }
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            var accumulated = ""

            func safeResume() {
                guard !resumed else { return }
                resumed = true
                safetyTimeout.cancel()
                continuation.resume()
            }

            client.send(
                text: userText,
                history: history,
                sessionKey: "thread:\(threadId.uuidString.lowercased())",
                onDelta: { [weak self] delta in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        accumulated += delta
                        if let index = self.threads.firstIndex(where: { $0.id == threadId }) {
                            if self.threads[index].messages.last?.role == .assistant {
                                let lastIdx = self.threads[index].messages.count - 1
                                self.threads[index].messages[lastIdx].text = accumulated
                            } else {
                                self.threads[index].messages.append(ChatMessage(role: .assistant, text: accumulated))
                            }
                        }
                    }
                },
                onComplete: { [weak self] finalText, model in
                    Task { @MainActor [weak self] in
                        let latencyMs = Int(Date().timeIntervalSince1970 * 1000) - startMs
                        let responseText = finalText.isEmpty ? accumulated : finalText
                        if let self {
                            self.updateThreadSuccess(threadId, response: responseText, model: model ?? "claude", latencyMs: latencyMs)
                            self.connectivity = .online
                            self.lastErrorText = nil
                            self.inFlightTasks[threadId] = nil
                            self.inFlightCount = self.inFlightTasks.count
                        }
                        safeResume()
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        if let self {
                            self.updateThreadFailure(threadId, error: error)
                            self.connectivity = .offline
                            self.lastErrorText = error
                            self.inFlightTasks[threadId] = nil
                            self.inFlightCount = self.inFlightTasks.count
                        }
                        safeResume()
                    }
                }
            )
        }
    }

    // MARK: - Legacy Gateway (will be removed)

    // MARK: - OpenAI API

    private func performOpenAIRequest(client: OpenAIClient, threadId: UUID, userText: String, startMs: Int) async {
        let safetyTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let index = self.threads.firstIndex(where: { $0.id == threadId }),
                   self.threads[index].isLoading {
                    self.updateThreadFailure(threadId, error: "Request timed out after 10 minutes. Tap to retry.")
                    self.inFlightTasks[threadId] = nil
                    self.inFlightCount = self.inFlightTasks.count
                }
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            var accumulated = ""

            func safeResume() {
                guard !resumed else { return }
                resumed = true
                safetyTimeout.cancel()
                continuation.resume()
            }

            // Build OpenAI history from thread messages
            var openAIHistory: [OpenAIMessage] = []
            if let thread = threads.first(where: { $0.id == threadId }) {
                for msg in thread.messages.dropLast() {
                    let role = msg.role == .assistant ? "assistant" : "user"
                    let content = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !content.isEmpty else { continue }
                    openAIHistory.append(OpenAIMessage(role: role, text: content))
                }
            }

            client.send(
                text: userText,
                history: openAIHistory,
                systemPrompt: "You are Thrawn, a strategic AI command agent. You serve the user directly. Be precise, thorough, and proactive.",
                sessionKey: "thread:\(threadId.uuidString.lowercased())",
                onDelta: { [weak self] delta in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        accumulated += delta
                        if let index = self.threads.firstIndex(where: { $0.id == threadId }) {
                            if self.threads[index].messages.last?.role == .assistant {
                                let lastIdx = self.threads[index].messages.count - 1
                                self.threads[index].messages[lastIdx].text = accumulated
                            } else {
                                self.threads[index].messages.append(ChatMessage(role: .assistant, text: accumulated))
                            }
                        }
                    }
                },
                onComplete: { [weak self] finalText, model in
                    Task { @MainActor [weak self] in
                        let latencyMs = Int(Date().timeIntervalSince1970 * 1000) - startMs
                        let responseText = finalText.isEmpty ? accumulated : finalText
                        if let self {
                            self.updateThreadSuccess(threadId, response: responseText, model: model ?? "gpt-4o", latencyMs: latencyMs)
                            self.connectivity = .online
                            self.lastErrorText = nil
                            self.inFlightTasks[threadId] = nil
                            self.inFlightCount = self.inFlightTasks.count
                        }
                        safeResume()
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        if let self {
                            self.updateThreadFailure(threadId, error: error)
                            self.connectivity = .offline
                            self.lastErrorText = error
                            self.inFlightTasks[threadId] = nil
                            self.inFlightCount = self.inFlightTasks.count
                        }
                        safeResume()
                    }
                }
            )
        }
    }

    // MARK: - Legacy Gateway (will be removed still)

    private func performGatewayRequest(threadId: UUID, text: String, startMs: Int) async {
        let safetyTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let index = self.threads.firstIndex(where: { $0.id == threadId }),
                   self.threads[index].isLoading {
                    self.updateThreadFailure(threadId, error: "Request timed out after 10 minutes. Tap to retry.")
                    self.inFlightTasks[threadId] = nil
                    self.inFlightCount = self.inFlightTasks.count
                }
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            var accumulated = ""

            func safeResume() {
                guard !resumed else { return }
                resumed = true
                safetyTimeout.cancel()
                continuation.resume()
            }

            gatewayWS.send(
                text: text,
                sessionKey: gatewaySessionKey(for: threadId),
                onDelta: { [weak self] delta in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        accumulated += delta
                        if let index = self.threads.firstIndex(where: { $0.id == threadId }) {
                            if self.threads[index].messages.last?.role == .assistant {
                                let lastIdx = self.threads[index].messages.count - 1
                                self.threads[index].messages[lastIdx].text = accumulated
                            } else {
                                self.threads[index].messages.append(ChatMessage(role: .assistant, text: accumulated))
                            }
                        }
                    }
                },
                onComplete: { [weak self] finalText, model in
                    Task { @MainActor [weak self] in
                        let latencyMs = Int(Date().timeIntervalSince1970 * 1000) - startMs
                        let responseText = finalText.isEmpty ? accumulated : finalText
                        if let self {
                            self.updateThreadSuccess(threadId, response: responseText, model: model ?? "gateway", latencyMs: latencyMs)
                            self.connectivity = .online
                            self.lastErrorText = nil
                            self.inFlightTasks[threadId] = nil
                            self.inFlightCount = self.inFlightTasks.count
                        }
                        safeResume()
                    }
                },
                onError: { [weak self] error in
                    Task { @MainActor [weak self] in
                        if let self {
                            self.updateThreadFailure(threadId, error: error)
                            self.connectivity = .offline
                            self.lastErrorText = error
                            self.inFlightTasks[threadId] = nil
                            self.inFlightCount = self.inFlightTasks.count
                        }
                        safeResume()
                    }
                }
            )
        }
    }

    private func updateThreadSuccess(_ id: UUID, response: String, model: String, latencyMs: Int) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        // If onDelta already added a streaming assistant message, update it instead of duplicating
        if let lastIdx = threads[index].messages.indices.last,
           threads[index].messages[lastIdx].role == .assistant {
            threads[index].messages[lastIdx].text = response
        } else {
            threads[index].messages.append(ChatMessage(role: .assistant, text: response))
        }
        threads[index].updatedAt = Date()
        threads[index].isLoading = false
        threads[index].state = .success
        threads[index].errorMessage = nil
        threads[index].modelUsed = model
        threads[index].latencyMs = latencyMs
        if selectedThreadId == id {
            threads[index].unreadCount = 0
        } else {
            threads[index].unreadCount += 1
        }
        moveThreadToTop(id)
        saveThreads()
        drainQueuedMessage(for: id)
    }

    private func updateThreadFailure(_ id: UUID, error: String) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[index].updatedAt = Date()
        threads[index].isLoading = false
        threads[index].state = .failed
        threads[index].errorMessage = error
        moveThreadToTop(id)
        saveThreads()
    }

    private func moveThreadToTop(_ id: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        if index == 0 { return }
        let item = threads.remove(at: index)
        threads.insert(item, at: 0)
    }

    private func drainQueuedMessage(for threadId: UUID) {
        guard var queue = queuedUserMessages[threadId], !queue.isEmpty else { return }
        let next = queue.removeFirst()
        if queue.isEmpty {
            queuedUserMessages.removeValue(forKey: threadId)
        } else {
            queuedUserMessages[threadId] = queue
        }

        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        threads[index].messages.append(ChatMessage(role: .user, text: next))
        threads[index].updatedAt = Date()
        threads[index].isLoading = true
        threads[index].state = .pending
        threads[index].errorMessage = nil
        moveThreadToTop(threadId)
        saveThreads()
        scheduleDraftSnapshotSave()
        runRequest(for: threadId)
        Task { await ChatDiagnostics.shared.log("send-drain thread=\(threadId.uuidString)") }
    }

    private func buildInputMessages(for threadId: UUID) -> [AnthropicMessage] {
        guard let thread = threads.first(where: { $0.id == threadId }) else { return [] }
        let history = thread.messages.suffix(maxInputHistoryMessages)
        var totalChars = 0
        var reversedSelection: [AnthropicMessage] = []

        for msg in history.reversed() {
            let role = msg.role == .assistant ? "assistant" : "user"
            var content = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if msg.role == .user, !msg.attachments.isEmpty {
                let attachmentBlock = msg.attachments.map { $0.promptSegment }.joined(separator: "\n\n")
                if content.isEmpty {
                    content = attachmentBlock
                } else {
                    content += "\n\n" + attachmentBlock
                }
            }
            guard !content.isEmpty else { continue }
            if content.count > 2_000 {
                content = String(content.suffix(2_000))
            }
            if totalChars + content.count > maxTotalInputChars {
                let room = maxTotalInputChars - totalChars
                guard room > 140 else { continue }
                content = String(content.suffix(room))
            }

            totalChars += content.count
            reversedSelection.append(AnthropicMessage(role: role, text: content))
            if totalChars >= maxTotalInputChars {
                break
            }
        }

        return reversedSelection.reversed()
    }

    private func sanitize(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxMessageLength))
    }

    private func applyGuardrailPreset() {
        let prefs = ThrawnPreferencesStore.load()
        switch prefs.effectiveLiabilityMode {
        case .idiot:
            maxMessageLength = 4000
            maxInputHistoryMessages = 36
            maxTotalInputChars = 16_000
            maxQueuedPerThread = 6
        case .myFault:
            maxMessageLength = 12_000
            maxInputHistoryMessages = 80
            maxTotalInputChars = 64_000
            maxQueuedPerThread = 24
        }
    }

    private func normalizeError(_ error: Error) -> String {
        let raw = (error as? LocalizedError)?.errorDescription ?? "Failed to reach Thrawn."
        let lower = raw.lowercased()

        if lower.contains("overloaded") || lower.contains("rate limit") || lower.contains("cooldown") {
            return "Provider is overloaded right now. Retry in a moment or use local fallback."
        }

        if lower.contains("image exceeds 5 mb") || lower.contains("exceeds 5 mb maximum") {
            return "Attachment is too large (max 5 MB). Resize or compress, then try again."
        }

        if lower.contains("unauthorized") || lower.contains("authentication token") || lower.contains("rejected authentication") || lower.contains("invalid api key") {
            return "Authentication failed. Check your API key in Settings."
        }

        if lower.contains("could not connect to the server")
            || lower.contains("cannot connect to host")
            || lower.contains("not connected to internet")
            || lower.contains("nsurlerrordomain code=-1004")
            || lower.contains("kcferror")
        {
            return "Cannot reach the AI service. Check your internet connection."
        }

        if lower.contains("model") && lower.contains("not found") {
            return "Configured model was not found. Check your model name in Settings."
        }

        // Prevent noisy framework/network dumps from reaching chat bubbles.
        if raw.count > 220 {
            return "Request failed. Open Settings > Run Diagnostics for details."
        }

        return raw
    }

    private func cancelTask(for id: UUID, updateThreadState: Bool) {
        inFlightTasks[id]?.cancel()
        inFlightTasks[id] = nil
        inFlightCount = max(0, inFlightTasks.count)
        // Cancel on both native and legacy clients
        anthropic?.abort(sessionKey: "thread:\(id.uuidString.lowercased())")
        geminiClient?.abort(sessionKey: "thread:\(id.uuidString.lowercased())")
        openAIClient?.abort(sessionKey: "thread:\(id.uuidString.lowercased())")
        gatewayWS.abort(sessionKey: gatewaySessionKey(for: id))
        guard updateThreadState else { return }
        if let index = threads.firstIndex(where: { $0.id == id }), threads[index].isLoading {
            threads[index].isLoading = false
            threads[index].state = .failed
            threads[index].errorMessage = "Request canceled."
            saveThreads()
        }
    }

    func draftText(for threadId: UUID) -> String {
        threadDrafts[threadId] ?? ""
    }

    func attachments(for threadId: UUID) -> [ChatAttachment] {
        threadAttachments[threadId] ?? []
    }

    func removeAttachment(threadId: UUID?, attachmentId: UUID) {
        if let threadId {
            var items = threadAttachments[threadId] ?? []
            items.removeAll { $0.id == attachmentId }
            if items.isEmpty {
                threadAttachments.removeValue(forKey: threadId)
            } else {
                threadAttachments[threadId] = items
            }
        } else {
            popupAttachments.removeAll { $0.id == attachmentId }
        }
        scheduleDraftSnapshotSave()
    }

    func clearPopupAttachments() {
        popupAttachments.removeAll()
        scheduleDraftSnapshotSave()
    }

    func clearAttachments(for threadId: UUID) {
        threadAttachments.removeValue(forKey: threadId)
        scheduleDraftSnapshotSave()
    }

    private func gatewaySessionKey(for threadId: UUID) -> String {
        "agent:thread:\(threadId.uuidString.lowercased())"
    }

    func handleFileDrop(providers: [NSItemProvider], threadId: UUID?) {
        Task {
            let urls = await Self.extractDroppedURLs(from: providers)
            guard !urls.isEmpty else { return }
            await MainActor.run {
                self.handleDroppedURLs(urls, threadId: threadId)
            }
        }
    }

    func handleDroppedURLs(_ urls: [URL], threadId: UUID?) {
        var added: [ChatAttachment] = []
        for url in urls {
            if let attachment = Self.ingestAttachment(from: url) {
                added.append(attachment)
            }
        }
        guard !added.isEmpty else {
            lastErrorText = "Couldn't attach dropped files. Max size is 25 MB each."
            return
        }

        if let threadId {
            var items = threadAttachments[threadId] ?? []
            items.append(contentsOf: added)
            threadAttachments[threadId] = Self.dedupAttachments(items)
        } else {
            popupAttachments = Self.dedupAttachments(popupAttachments + added)
        }
        lastErrorText = nil
        scheduleDraftSnapshotSave()
    }

    func markThreadRead(_ threadId: UUID) {
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        guard threads[index].unreadCount > 0 else { return }
        threads[index].unreadCount = 0
        saveThreads()
    }

    func updatePopupDraft(_ text: String) {
        popupDraftText = String(text.prefix(maxMessageLength))
        appendDraftEvent(type: .popup, threadId: nil, text: popupDraftText)
        scheduleDraftSnapshotSave()
    }

    func updateThreadDraft(threadId: UUID, text: String) {
        let capped = String(text.prefix(maxMessageLength))
        if capped.isEmpty {
            threadDrafts.removeValue(forKey: threadId)
        } else {
            threadDrafts[threadId] = capped
        }
        appendDraftEvent(type: .thread, threadId: threadId, text: capped)
        scheduleDraftSnapshotSave()
    }

    private func sanitizedAttachments(_ items: [ChatAttachment]) -> [ChatAttachment] {
        Self.dedupAttachments(items).prefix(6).map { $0 }
    }

    private func loadThreads() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([ChatThread].self, from: data)
            self.threads = Array(decoded.prefix(maxStoredThreads)).map { thread in
                if thread.isLoading {
                    var recovered = thread
                    recovered.isLoading = false
                    recovered.state = .failed
                    recovered.errorMessage = "Recovered after app restart before reply completed."
                    return recovered
                }
                return thread
            }
        } catch {
            let brokenName = "threads-corrupt-\(Int(Date().timeIntervalSince1970)).json"
            let brokenPath = storageDir.appendingPathComponent(brokenName)
            try? FileManager.default.moveItem(at: storageURL, to: brokenPath)
            self.threads = []
            self.lastErrorText = "Recovered from a corrupted local thread file."
        }
    }

    private func saveThreads() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Array(threads.prefix(maxStoredThreads)))
            try data.write(to: storageURL, options: .atomic)
        } catch {
            lastErrorText = "Failed to save local thread history."
        }
    }

    private func loadDraftState() {
        if FileManager.default.fileExists(atPath: draftStateURL.path) {
            do {
                let data = try Data(contentsOf: draftStateURL)
                let state = try JSONDecoder().decode(DraftState.self, from: data)
                self.popupDraftText = state.popupDraftText
                self.popupAttachments = state.popupAttachments
                self.threadDrafts = Dictionary(uniqueKeysWithValues: state.threadDrafts.compactMap { key, value in
                    guard let uuid = UUID(uuidString: key) else { return nil }
                    return (uuid, value)
                })
                self.threadAttachments = Dictionary(uniqueKeysWithValues: state.threadAttachments.compactMap { key, value in
                    guard let uuid = UUID(uuidString: key) else { return nil }
                    return (uuid, value)
                })
                self.queuedUserMessages = Dictionary(uniqueKeysWithValues: state.queuedMessages.compactMap { key, value in
                    guard let uuid = UUID(uuidString: key) else { return nil }
                    let clean = value.map(sanitize).filter { !$0.isEmpty }
                    guard !clean.isEmpty else { return nil }
                    return (uuid, Array(clean.suffix(maxQueuedPerThread)))
                })
            } catch {
                self.popupDraftText = ""
                self.popupAttachments = []
                self.threadDrafts = [:]
                self.threadAttachments = [:]
                self.queuedUserMessages = [:]
            }
        }
        replayDraftEvents()
    }

    private func saveDraftState() {
        do {
            let serializableDrafts = Dictionary(uniqueKeysWithValues: threadDrafts.map { ($0.key.uuidString, $0.value) })
            let serializableAttachments = Dictionary(uniqueKeysWithValues: threadAttachments.map { ($0.key.uuidString, $0.value) })
            let serializableQueues = Dictionary(uniqueKeysWithValues: queuedUserMessages.map { ($0.key.uuidString, $0.value) })
            let state = DraftState(
                popupDraftText: popupDraftText,
                popupAttachments: popupAttachments,
                threadDrafts: serializableDrafts,
                threadAttachments: serializableAttachments,
                queuedMessages: serializableQueues
            )
            let data = try JSONEncoder().encode(state)
            try data.write(to: draftStateURL, options: .atomic)
            truncateDraftEventLog()
        } catch {
            lastErrorText = "Failed to persist live drafts."
        }
    }

    private func scheduleDraftSnapshotSave() {
        draftSnapshotTask?.cancel()
        draftSnapshotTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.saveDraftState()
            }
        }
    }

    private func appendDraftEvent(type: DraftEvent.EventType, threadId: UUID?, text: String) {
        let event = DraftEvent(type: type, threadId: threadId?.uuidString, text: text, timestamp: Date())
        guard let payload = try? JSONEncoder().encode(event), let line = String(data: payload, encoding: .utf8) else { return }
        let record = line + "\n"
        guard let data = record.data(using: .utf8) else { return }
        let url = draftEventLogURL

        // File I/O off the main thread to prevent UI freezes on paste
        DispatchQueue.global(qos: .utility).async {
            if !FileManager.default.fileExists(atPath: url.path) {
                try? data.write(to: url, options: .atomic)
                return
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        }
    }

    private func replayDraftEvents() {
        guard let data = try? Data(contentsOf: draftEventLogURL), !data.isEmpty else { return }
        guard let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n")
        if lines.isEmpty { return }

        let decoder = JSONDecoder()
        for line in lines {
            guard let payload = line.data(using: .utf8), let event = try? decoder.decode(DraftEvent.self, from: payload) else {
                continue
            }
            switch event.type {
            case .popup:
                popupDraftText = String(event.text.prefix(maxMessageLength))
            case .thread:
                guard let idString = event.threadId, let id = UUID(uuidString: idString) else { continue }
                let capped = String(event.text.prefix(maxMessageLength))
                if capped.isEmpty {
                    threadDrafts.removeValue(forKey: id)
                } else {
                    threadDrafts[id] = capped
                }
            case .clear:
                popupDraftText = ""
                popupAttachments = []
                threadDrafts.removeAll()
                threadAttachments.removeAll()
            }
        }
    }

    private func truncateDraftEventLog() {
        try? Data().write(to: draftEventLogURL, options: .atomic)
    }

    private static func dedupAttachments(_ items: [ChatAttachment]) -> [ChatAttachment] {
        var seen = Set<String>()
        var output: [ChatAttachment] = []
        for item in items {
            let key = "\(item.filePath)|\(item.fileSizeBytes)"
            if seen.insert(key).inserted {
                output.append(item)
            }
        }
        return output
    }

    private static func extractDroppedURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            if let url = await loadFileURL(from: provider) {
                urls.append(url)
            }
        }
        return urls
    }

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                    let url = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL?
                {
                    continuation.resume(returning: url)
                    return
                }
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }
                continuation.resume(returning: nil)
            }
        }
    }

    private static func ingestAttachment(from url: URL) -> ChatAttachment? {
        let path = url.path
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0, size <= 25_000_000 else {
            return nil
        }

        let ext = url.pathExtension.lowercased()
        let textExtensions: Set<String> = [
            "txt", "md", "json", "jsonl", "csv", "tsv", "log", "yaml", "yml", "xml",
            "swift", "py", "js", "ts", "tsx", "jsx", "html", "css", "sh", "zsh", "bash", "rb", "go", "rs"
        ]

        var preview: String?
        if textExtensions.contains(ext),
            let handle = try? FileHandle(forReadingFrom: url)
        {
            let data = try? handle.read(upToCount: 8000)
            try? handle.close()
            if let data, let text = String(data: data, encoding: .utf8) {
                preview = String(text.prefix(3000))
            }
        }

        return ChatAttachment(
            fileName: url.lastPathComponent,
            filePath: path,
            fileSizeBytes: size,
            previewText: preview
        )
    }
}
