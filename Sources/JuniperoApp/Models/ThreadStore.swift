import Foundation
import SwiftUI

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
    private let client = OpenClawClient()
    private var threadDrafts: [UUID: String] = [:]
    private var queuedUserMessages: [UUID: [String]] = [:]
    private var draftSnapshotTask: Task<Void, Never>?
    private var preferenceObserver: NSObjectProtocol?

    private struct DraftState: Codable {
        var popupDraftText: String
        var threadDrafts: [String: String]
        var queuedMessages: [String: [String]]

        init(popupDraftText: String, threadDrafts: [String: String], queuedMessages: [String: [String]]) {
            self.popupDraftText = popupDraftText
            self.threadDrafts = threadDrafts
            self.queuedMessages = queuedMessages
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.popupDraftText = try c.decodeIfPresent(String.self, forKey: .popupDraftText) ?? ""
            self.threadDrafts = try c.decodeIfPresent([String: String].self, forKey: .threadDrafts) ?? [:]
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
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.storageDir = home.appendingPathComponent(".junipero", isDirectory: true)
        self.storageURL = storageDir.appendingPathComponent("threads.json")
        self.draftStateURL = storageDir.appendingPathComponent("drafts.json")
        self.draftEventLogURL = storageDir.appendingPathComponent("draft-events.log")
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        applyGuardrailPreset()
        preferenceObserver = NotificationCenter.default.addObserver(
            forName: JuniperoPreferencesStore.changedNotification,
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

    func sendMessage(_ text: String) {
        JuniperoPreferencesStore.incrementInteraction()
        let trimmed = sanitize(text)
        guard !trimmed.isEmpty else { return }

        var thread = ChatThread(
            messages: [ChatMessage(role: .user, text: trimmed)],
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
        Task { await ChatDiagnostics.shared.log("new-thread send thread=\(thread.id.uuidString) chars=\(trimmed.count)") }
    }

    func sendMessage(in threadId: UUID, text: String) {
        JuniperoPreferencesStore.incrementInteraction()
        let trimmed = sanitize(text)
        guard !trimmed.isEmpty else { return }
        guard let index = threads.firstIndex(where: { $0.id == threadId }) else { return }
        guard !threads[index].isLoading else {
            var queue = queuedUserMessages[threadId, default: []]
            queue.append(trimmed)
            queuedUserMessages[threadId] = Array(queue.suffix(maxQueuedPerThread))
            updateThreadDraft(threadId: threadId, text: "")
            lastErrorText = "Queued your message. It will send after the current reply."
            scheduleDraftSnapshotSave()
            Task { await ChatDiagnostics.shared.log("send-queued thread=\(threadId.uuidString) depth=\(queue.count)") }
            return
        }

        threads[index].messages.append(ChatMessage(role: .user, text: trimmed))
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
        // Replacing an in-flight task as part of normal send/retry should be silent.
        cancelTask(for: threadId, updateThreadState: false)
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

    private func performRequest(threadId: UUID, messages: [OpenClawClient.InputMessage]) async {
        do {
            let result = try await client.send(messages: messages)
            guard !Task.isCancelled else { return }
            updateThreadSuccess(threadId, response: result.text, model: result.model, latencyMs: result.latencyMs)
            connectivity = .online
            lastErrorText = nil
            await ChatDiagnostics.shared.log("request-ok thread=\(threadId.uuidString) model=\(result.model) latencyMs=\(result.latencyMs) outChars=\(result.text.count)")
        } catch is CancellationError {
            // handled by cancelRequest
        } catch {
            guard !Task.isCancelled else { return }
            let message = normalizeError(error)
            updateThreadFailure(threadId, error: message)
            connectivity = .offline
            lastErrorText = message
            await ChatDiagnostics.shared.log("request-fail thread=\(threadId.uuidString) error=\(message)")
        }
        inFlightTasks[threadId] = nil
        inFlightCount = inFlightTasks.count
    }

    private func updateThreadSuccess(_ id: UUID, response: String, model: String, latencyMs: Int) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[index].messages.append(ChatMessage(role: .assistant, text: response))
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

    private func buildInputMessages(for threadId: UUID) -> [OpenClawClient.InputMessage] {
        guard let thread = threads.first(where: { $0.id == threadId }) else { return [] }
        let history = thread.messages.suffix(maxInputHistoryMessages)
        var totalChars = 0
        var reversedSelection: [OpenClawClient.InputMessage] = []

        for msg in history.reversed() {
            let role = msg.role == .assistant ? "assistant" : "user"
            var content = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
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
            reversedSelection.append(OpenClawClient.InputMessage(role: role, content: content))
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
        let prefs = JuniperoPreferencesStore.load()
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
        let raw = (error as? LocalizedError)?.errorDescription ?? "Failed to reach O'Brien."
        let lower = raw.lowercased()

        if lower.contains("overloaded") || lower.contains("rate limit") || lower.contains("cooldown") {
            return "Provider is overloaded right now. Retry in a moment or use local fallback."
        }

        if lower.contains("image exceeds 5 mb") || lower.contains("exceeds 5 mb maximum") {
            return "Attachment is too large (max 5 MB). Resize or compress, then try again."
        }

        if lower.contains("unauthorized") || lower.contains("authentication token") || lower.contains("openclaw rejected authentication") {
            return "Authentication failed. Open Setup and verify your provider token."
        }

        if lower.contains("could not connect to the server")
            || lower.contains("cannot connect to host")
            || lower.contains("not connected to internet")
            || lower.contains("nsurlerrordomain code=-1004")
            || lower.contains("kcferror")
        {
            return "Cannot reach OpenClaw right now. Use Heal or check that OpenClaw is running."
        }

        if lower.contains("primary and fallback both failed") {
            let fallbackMissingModel = lower.contains("model")
                && lower.contains("not found")
                && (lower.contains("kimi") || lower.contains("ollama"))
            if fallbackMissingModel {
                return "Primary is offline and local fallback model is missing. Open Setup and tap Fix Missing Model."
            }
            return "Primary and fallback both failed. Open Setup, run diagnostics, then retry."
        }

        if lower.contains("openclaw error 404") && lower.contains("model") && lower.contains("not found") {
            return "Configured model was not found. Open Setup and select/install an available model."
        }

        // Prevent noisy framework/network dumps from reaching chat bubbles.
        if raw.count > 220 {
            return "Request failed. Open Setup > Run Diagnostics for full details."
        }

        return raw
    }

    private func cancelTask(for id: UUID, updateThreadState: Bool) {
        inFlightTasks[id]?.cancel()
        inFlightTasks[id] = nil
        inFlightCount = max(0, inFlightTasks.count)
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
                self.threadDrafts = Dictionary(uniqueKeysWithValues: state.threadDrafts.compactMap { key, value in
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
                self.threadDrafts = [:]
                self.queuedUserMessages = [:]
            }
        }
        replayDraftEvents()
    }

    private func saveDraftState() {
        do {
            let serializableDrafts = Dictionary(uniqueKeysWithValues: threadDrafts.map { ($0.key.uuidString, $0.value) })
            let serializableQueues = Dictionary(uniqueKeysWithValues: queuedUserMessages.map { ($0.key.uuidString, $0.value) })
            let state = DraftState(
                popupDraftText: popupDraftText,
                threadDrafts: serializableDrafts,
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

        if !FileManager.default.fileExists(atPath: draftEventLogURL.path) {
            try? data.write(to: draftEventLogURL, options: .atomic)
            return
        }

        if let handle = try? FileHandle(forWritingTo: draftEventLogURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
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
                threadDrafts.removeAll()
            }
        }
    }

    private func truncateDraftEventLog() {
        try? Data().write(to: draftEventLogURL, options: .atomic)
    }
}
