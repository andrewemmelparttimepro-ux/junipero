import Foundation
import SwiftUI

struct GatewayHistoryContent: Codable {
    var type: String?
    var text: String?
    var thinking: String?
    var content: String?
    // Image content blocks from Claude API responses
    var source: GatewayImageSource?
}

struct GatewayImageSource: Codable {
    var type: String?          // "base64" or "url"
    var media_type: String?    // "image/png", "image/jpeg", etc.
    var data: String?          // base64 data (for type=base64)
    var url: String?           // URL (for type=url)
}

struct GatewayHistoryEntry: Codable {
    var role: String
    var content: [GatewayHistoryContent]?
    var text: String?
    var createdAt: String?
    var model: String?
    var aborted: Bool?
    var timestamp: Double?
    var errorMessage: String?
    var stopReason: String?

    var resolvedContent: String {
        let blocks = content ?? []
        let joined = blocks.compactMap { block -> String? in
            if let text = block.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
            if let text = block.content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
            return nil
        }.joined(separator: "\n\n")

        if !joined.isEmpty {
            return joined
        }

        return text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Extract image data from content blocks (base64 or URL images)
    var resolvedImages: [MessageImageBlock] {
        guard let blocks = content else { return [] }
        return blocks.compactMap { block -> MessageImageBlock? in
            guard block.type == "image", let source = block.source else { return nil }
            if source.type == "base64", let data = source.data, let mediaType = source.media_type {
                guard let decoded = Data(base64Encoded: data) else { return nil }
                guard let nsImage = NSImage(data: decoded) else { return nil }
                return MessageImageBlock(image: nsImage, mediaType: mediaType)
            }
            if source.type == "url", let urlStr = source.url, let url = URL(string: urlStr) {
                // For URL images, we'll load them async later; store the URL
                return MessageImageBlock(imageURL: url, mediaType: source.media_type ?? "image/png")
            }
            return nil
        }
    }

    var isTerminalAssistantReply: Bool {
        guard role == "assistant" else { return false }
        if stopReason == "toolUse" {
            return false
        }
        if let errorMessage, !errorMessage.isEmpty {
            return true
        }
        return !resolvedContent.isEmpty
    }
}

private struct GatewayHistoryResponse: Codable {
    var sessionKey: String?
    var sessionId: String?
    var messages: [GatewayHistoryEntry]
}

private struct GatewaySendResponse: Codable {
    var runId: String?
    var status: String?
    var message: String?
    var error: String?
    var text: String?
    var content: String?
}

struct GatewayActiveSession: Codable {
    let key: String
    let label: String?
    let model: String?
    let updatedAtMs: Double?
}

private struct GatewaySessionsListResponse: Codable {
    let sessions: [GatewayActiveSession]
}


private enum GatewayCLIError: LocalizedError {
    case commandFailed(String)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        case .decodeFailed(let message):
            return message
        }
    }
}

struct GatewayWSConfig {
    var sessionKey: String
    var baseURL: String
    var token: String

    static let `default` = GatewayWSConfig.load()

    static func load() -> GatewayWSConfig {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var baseURL = "http://127.0.0.1:18789"
        var token = ""

        // Try to read token and port from openclaw.json
        let openclawConfig = home.appendingPathComponent(".openclaw/openclaw.json")
        if let data = try? Data(contentsOf: openclawConfig),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let gateway = json["gateway"] as? [String: Any] {
            if let port = gateway["port"] as? Int {
                baseURL = "http://127.0.0.1:\(port)"
            }
            if let auth = gateway["auth"] as? [String: Any],
               let t = auth["token"] as? String {
                token = t
            }
        }

        // Also check junipero config for baseURL override
        let juniperoConfig = home.appendingPathComponent(".junipero/config.json")
        if let data = try? Data(contentsOf: juniperoConfig),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let url = json["baseURL"] as? String, !url.isEmpty {
            baseURL = url
        }

        return GatewayWSConfig(sessionKey: "agent:main:main", baseURL: baseURL, token: token)
    }
}

// MARK: - HTTP-based Gateway Client

@MainActor
final class GatewayWSClient: ObservableObject {
    @Published var connected = false
    @Published var authenticating = false
    @Published var lastError: String?

    private var monitorTask: Task<Void, Never>?
    private var activeRuns: [String: Task<Void, Never>] = [:]
    private var config: GatewayWSConfig
    private let reconnectPollIntervalNs: UInt64 = 2_000_000_000
    private let healthyPollIntervalNs: UInt64 = 30_000_000_000
    private let session: URLSession

    init(config: GatewayWSConfig = .default) {
        self.config = config
        let urlConfig = URLSessionConfiguration.default
        urlConfig.timeoutIntervalForRequest = 15
        urlConfig.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: urlConfig)
    }

    func connect() {
        guard monitorTask == nil else { return }

        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshConnectionStatus()
                let pause = self.connected ? self.healthyPollIntervalNs : self.reconnectPollIntervalNs
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: pause)
            }
        }
    }

    func refreshNow() {
        Task { [weak self] in
            await self?.refreshConnectionStatus()
        }
    }

    func prewarmHistory(sessionKey: String = "main") {
        let resolvedSessionKey = normalizeSessionKey(sessionKey)
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.loadHistoryHTTP(sessionKey: resolvedSessionKey, limit: 20)
        }
    }

    func connectAndPrewarm(sessionKey: String = "main") {
        connect()
        refreshNow()
        let resolvedSessionKey = normalizeSessionKey(sessionKey)
        Task { [weak self] in
            guard let self else { return }
            for _ in 0..<20 {
                guard !Task.isCancelled else { return }
                if self.connected {
                    self.prewarmHistory(sessionKey: resolvedSessionKey)
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    func disconnect() {
        monitorTask?.cancel()
        monitorTask = nil

        for task in activeRuns.values {
            task.cancel()
        }
        activeRuns.removeAll()

        connected = false
        authenticating = false
    }

    // MARK: - Send (HTTP POST primary, CLI RPC fallback)
    //
    // PRIMARY: POST /v1/chat/completions — returns complete response directly.
    // No polling, no WebSocket, instant results. Retries up to 3 times with
    // exponential backoff on transient failures.
    //
    // FALLBACK: CLI chat.send + chat.history polling — only if HTTP fails
    // with a non-transient error (e.g., endpoint not available).

    func send(
        text: String,
        imageData: Data? = nil,
        sessionKey: String = "main",
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String, String?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        let resolvedSessionKey = normalizeSessionKey(sessionKey)
        let runTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.activeRuns.removeValue(forKey: resolvedSessionKey)
            }

            // Quick HTTP health check (~20ms)
            let healthy = await self.httpHealthCheck()
            if healthy {
                self.connected = true
                self.lastError = nil
            } else {
                self.connected = false
                self.lastError = "OpenClaw gateway is unavailable."
                onError("OpenClaw gateway is not reachable. Check that it's running.")
                return
            }

            let hasImage = imageData != nil
            await ChatDiagnostics.shared.log(
                "gateway-send start session=\(resolvedSessionKey) chars=\(text.count) hasImage=\(hasImage) connected=\(self.connected) method=HTTP"
            )

            // PRIMARY PATH: HTTP POST /v1/chat/completions
            let httpResult = await self.sendViaHTTP(text: text, imageData: imageData, sessionKey: resolvedSessionKey)

            guard !Task.isCancelled else {
                await ChatDiagnostics.shared.log("gateway-send cancelled")
                return
            }

            switch httpResult {
            case .success(let (responseText, model)):
                self.lastError = nil
                await ChatDiagnostics.shared.log(
                    "gateway-http-send complete model=\(model ?? "-") chars=\(responseText.count)"
                )
                onDelta(responseText)
                onComplete(responseText, model)
                return

            case .failure(let error):
                await ChatDiagnostics.shared.log(
                    "gateway-http-send all-attempts-failed error=\(error.localizedDescription)"
                )
                // FALLBACK: CLI send + poll (no image support in CLI fallback)
                await ChatDiagnostics.shared.log("gateway-send falling back to CLI")
                await self.sendViaCLI(
                    text: text,
                    sessionKey: resolvedSessionKey,
                    onDelta: onDelta,
                    onComplete: onComplete,
                    onError: onError
                )
            }
        }

        activeRuns[resolvedSessionKey]?.cancel()
        activeRuns[resolvedSessionKey] = runTask
    }

    // MARK: - HTTP Send (Primary Path)

    private struct ChatCompletionResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable {
                var role: String?
                var content: String?
            }
            var message: Message?
            var finish_reason: String?
        }
        var id: String?
        var model: String?
        var choices: [Choice]?
    }

    private func sendViaHTTP(
        text: String,
        imageData: Data? = nil,
        sessionKey: String,
        maxRetries: Int = 3,
        model: String = "anthropic/claude-sonnet-4-6"
    ) async -> Result<(String, String?), Error> {
        guard let url = URL(string: "\(config.baseURL)/v1/chat/completions") else {
            return .failure(GatewayCLIError.commandFailed("Invalid gateway URL"))
        }

        // Build message content — plain text or multimodal with image
        let messageContent: Any
        if let imageData {
            let base64 = imageData.base64EncodedString()
            var contentBlocks: [[String: Any]] = [
                [
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
                ]
            ]
            contentBlocks.append([
                "type": "text",
                "text": text
            ])
            messageContent = contentBlocks
        } else {
            messageContent = text
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": messageContent]
            ],
            "stream": false,
            "user": sessionKey
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure(GatewayCLIError.commandFailed("Could not encode request body"))
        }

        var lastError: Error = GatewayCLIError.commandFailed("Unknown error")

        for attempt in 1...maxRetries {
            guard !Task.isCancelled else {
                return .failure(GatewayCLIError.commandFailed("Cancelled"))
            }

            let timeout: TimeInterval = attempt == 1 ? 300 : 300  // 5 min per attempt for agentic tasks

            await ChatDiagnostics.shared.log(
                "gateway-http-send attempt=\(attempt)/\(maxRetries) model=\(model) timeout=\(Int(timeout))s"
            )

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !config.token.isEmpty {
                request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
            }
            request.timeoutInterval = timeout

            do {
                // Use a dedicated URLSession with long timeout for chat requests
                let chatConfig = URLSessionConfiguration.default
                chatConfig.timeoutIntervalForRequest = timeout
                chatConfig.timeoutIntervalForResource = timeout + 30
                let chatSession = URLSession(configuration: chatConfig)
                defer { chatSession.invalidateAndCancel() }

                let (data, response) = try await chatSession.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    lastError = GatewayCLIError.commandFailed("Non-HTTP response")
                    continue
                }

                if httpResponse.statusCode == 200 {
                    // Parse the response
                    if let completion = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data),
                       let content = completion.choices?.first?.message?.content,
                       !content.isEmpty {
                        return .success((content, completion.model))
                    }

                    // Fallback: try raw JSON parsing
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String, !content.isEmpty {
                        let model = json["model"] as? String
                        return .success((content, model))
                    }

                    lastError = GatewayCLIError.commandFailed("Empty response from model")
                    await ChatDiagnostics.shared.log("gateway-http-send empty-response attempt=\(attempt)")
                    continue

                } else if httpResponse.statusCode >= 500 {
                    // Server error — retry
                    lastError = GatewayCLIError.commandFailed("Server error \(httpResponse.statusCode)")
                    await ChatDiagnostics.shared.log("gateway-http-send server-error status=\(httpResponse.statusCode) attempt=\(attempt)")
                } else if httpResponse.statusCode == 429 {
                    // Rate limited — retry with longer backoff
                    lastError = GatewayCLIError.commandFailed("Rate limited")
                    await ChatDiagnostics.shared.log("gateway-http-send rate-limited attempt=\(attempt)")
                } else {
                    // Client error (4xx) — don't retry
                    let bodyStr = String(data: data, encoding: .utf8) ?? "no body"
                    lastError = GatewayCLIError.commandFailed("HTTP \(httpResponse.statusCode): \(String(bodyStr.prefix(200)))")
                    await ChatDiagnostics.shared.log("gateway-http-send client-error status=\(httpResponse.statusCode) attempt=\(attempt)")
                    return .failure(lastError)
                }

            } catch let error as URLError where error.code == .timedOut {
                lastError = error
                await ChatDiagnostics.shared.log("gateway-http-send timeout attempt=\(attempt)")
            } catch let error as URLError where error.code == .networkConnectionLost || error.code == .notConnectedToInternet {
                lastError = error
                await ChatDiagnostics.shared.log("gateway-http-send network-error attempt=\(attempt) error=\(error.localizedDescription)")
            } catch {
                lastError = error
                await ChatDiagnostics.shared.log("gateway-http-send error attempt=\(attempt) error=\(error.localizedDescription)")
            }

            // Exponential backoff before retry
            if attempt < maxRetries {
                let backoffNs: UInt64 = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try? await Task.sleep(nanoseconds: backoffNs)
            }
        }

        return .failure(lastError)
    }

    // MARK: - CLI Send Fallback

    private func sendViaCLI(
        text: String,
        sessionKey: String,
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String, String?) -> Void,
        onError: @escaping (String) -> Void
    ) async {
        // Step 1: Capture baseline history count BEFORE sending
        let baselineCount: Int
        do {
            let baseline = try await self.loadHistoryCLI(sessionKey: sessionKey, limit: 5)
            baselineCount = baseline.count
        } catch {
            baselineCount = 0
        }

        guard !Task.isCancelled else { return }

        // Step 2: Send via CLI RPC
        let sendResult = await self.gatewayCall(
            method: "chat.send",
            params: [
                "sessionKey": sessionKey,
                "message": text,
                "idempotencyKey": UUID().uuidString
            ],
            timeoutMs: 30_000
        )

        guard !Task.isCancelled else { return }

        let sendOK: Bool
        if sendResult.exitCode != 0 {
            sendOK = false
        } else {
            let lower = sendResult.stdout.lowercased()
            sendOK = lower.contains("started") || lower.contains("runid") || lower.contains("run_id")
        }

        if !sendOK {
            let errMsg = String(sendResult.stderr.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = !errMsg.isEmpty ? errMsg : "CLI send failed"
            await ChatDiagnostics.shared.log("gateway-cli-send failed detail=\(detail)")
            onError("Could not send message to OpenClaw. Gateway may be restarting.")
            return
        }

        await ChatDiagnostics.shared.log("gateway-cli-send accepted, polling for response")

        // Step 3: Poll chat.history
        var lastResolvedText = ""
        var pollsWithNoChange = 0
        let maxPolls = 45
        let pollIntervalNs: UInt64 = 4_000_000_000

        for pollIndex in 0..<maxPolls {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: pollIntervalNs)

            do {
                let history = try await self.loadHistoryCLI(sessionKey: sessionKey, limit: baselineCount + 10)
                let newMessages = history.count > baselineCount ? Array(history.suffix(from: baselineCount)) : []
                let latestAssistant = newMessages.last(where: { $0.role == "assistant" })

                if let reply = latestAssistant {
                    let replyText = reply.resolvedContent

                    if !replyText.isEmpty, replyText != lastResolvedText {
                        let delta = replyText.hasPrefix(lastResolvedText)
                            ? String(replyText.dropFirst(lastResolvedText.count))
                            : replyText
                        lastResolvedText = replyText
                        if !delta.isEmpty { onDelta(delta) }
                        pollsWithNoChange = 0
                    } else {
                        pollsWithNoChange += 1
                    }

                    if let errorMessage = reply.errorMessage, !errorMessage.isEmpty {
                        onError(errorMessage); return
                    }
                    if reply.stopReason == "aborted" {
                        onError("Run aborted."); return
                    }
                    if reply.isTerminalAssistantReply {
                        self.lastError = nil
                        onComplete(replyText, reply.model); return
                    }
                } else {
                    pollsWithNoChange += 1
                }

                if pollsWithNoChange >= 30 {
                    onError("No response from OpenClaw after \(pollsWithNoChange * 4)s.")
                    return
                }
            } catch {
                pollsWithNoChange += 1
            }
        }

        onError("Timed out waiting for response (~3 minutes).")
    }

    // MARK: - Fetch History

    func fetchHistory(
        sessionKey: String = "main",
        onHistory: @escaping ([GatewayHistoryEntry]) -> Void
    ) {
        let resolvedSessionKey = normalizeSessionKey(sessionKey)
        Task { [weak self] in
            guard let self else { return }
            do {
                let history = try await self.loadHistoryHTTP(sessionKey: resolvedSessionKey, limit: 30)
                self.lastError = nil
                onHistory(history)
            } catch {
                // Fallback to CLI
                do {
                    let history = try await self.loadHistoryCLI(sessionKey: resolvedSessionKey, limit: 30)
                    self.lastError = nil
                    onHistory(history)
                } catch {
                    self.lastError = (error as? LocalizedError)?.errorDescription ?? "Could not load chat history."
                }
            }
        }
    }

    /// Fetch currently active sessions from the Gateway.
    func sessionsList() async -> [GatewayActiveSession] {
        let result = await gatewayCall(
            method: "sessions.list",
            params: ["limit": 20, "activeMinutes": 5],
            timeoutMs: 5000
        )
        guard result.exitCode == 0 else { return [] }
        guard let response = try? decodeJSON(GatewaySessionsListResponse.self, from: result.stdout) else {
            return []
        }
        return response.sessions
    }

    func abort(sessionKey: String = "main") {
        let resolvedSessionKey = normalizeSessionKey(sessionKey)
        activeRuns[resolvedSessionKey]?.cancel()
        activeRuns.removeValue(forKey: resolvedSessionKey)

        Task { [weak self] in
            guard let self else { return }
            _ = await self.gatewayCall(
                method: "chat.abort",
                params: ["sessionKey": resolvedSessionKey],
                timeoutMs: 10_000
            )
            await ChatDiagnostics.shared.log("gateway-send abort session=\(resolvedSessionKey)")
        }
    }

    // MARK: - HTTP History Loading

    private func loadHistoryHTTP(sessionKey: String, limit: Int) async throws -> [GatewayHistoryEntry] {
        // Use WebSocket RPC call via a lightweight HTTP approach:
        // Since the gateway doesn't expose chat.history over REST, we use the CLI.
        // But we add a fast-path: try to connect via a quick WebSocket call.
        // For now, use CLI with a short timeout as there's no HTTP endpoint for history.
        return try await loadHistoryCLI(sessionKey: sessionKey, limit: limit)
    }

    private func loadHistoryCLI(sessionKey: String, limit: Int) async throws -> [GatewayHistoryEntry] {
        let result = await gatewayCall(
            method: "chat.history",
            params: [
                "sessionKey": sessionKey,
                "limit": limit
            ],
            timeoutMs: 15_000
        )

        guard result.exitCode == 0 else {
            throw GatewayCLIError.commandFailed(
                String(commandErrorMessage(from: result, fallback: "Could not load chat history.").prefix(200))
            )
        }

        let decoded = try decodeJSON(GatewayHistoryResponse.self, from: result.stdout)
        return decoded.messages
    }

    // MARK: - Health Check (HTTP — instant, no CLI overhead)

    private func refreshConnectionStatus() async {
        authenticating = true

        // Use HTTP health check — ~20ms instead of ~3s via CLI
        let healthy = await httpHealthCheck()
        authenticating = false

        if healthy {
            connected = true
            lastError = nil
        } else {
            connected = false
            lastError = "OpenClaw gateway is unavailable."
        }
    }

    private func httpHealthCheck() async -> Bool {
        guard let url = URL(string: "\(config.baseURL)/health") else { return false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }
            // Parse {"ok":true,"status":"live"}
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ok = json["ok"] as? Bool {
                return ok
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Helpers

    private func gatewayCall(method: String, params: [String: Any], timeoutMs: Int) async -> ShellCommandResult {
        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: params, options: [])
        } catch {
            return ShellCommandResult(exitCode: 1, stdout: "", stderr: "Could not encode OpenClaw params: \(error.localizedDescription)")
        }

        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            return ShellCommandResult(exitCode: 1, stdout: "", stderr: "Could not encode OpenClaw params as UTF-8.")
        }

        let command = "openclaw gateway call \(shellQuote(method)) --json --timeout \(timeoutMs) --params \(shellQuote(jsonString))"
        return await ShellCommand.run(command)
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw GatewayCLIError.decodeFailed("OpenClaw returned unreadable output.")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw GatewayCLIError.decodeFailed("OpenClaw returned unexpected JSON.")
        }
    }

    private func commandErrorMessage(from result: ShellCommandResult, fallback: String) -> String {
        let candidates = [
            result.stderr.trimmingCharacters(in: .whitespacesAndNewlines),
            result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        ]

        for item in candidates where !item.isEmpty {
            return String(item.prefix(500))
        }

        return fallback
    }

    private func normalizeSessionKey(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return config.sessionKey }
        if trimmed == "main" {
            return config.sessionKey
        }
        return trimmed
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
