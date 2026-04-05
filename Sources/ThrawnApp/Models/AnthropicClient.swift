import Foundation
import SwiftUI

// MARK: - Anthropic Messages API Client
//
// Native HTTPS client that talks directly to api.anthropic.com.
// No gateway, no CLI, no external processes — App Store compliant.
// Supports streaming SSE for real-time deltas.

// MARK: - Configuration

struct AnthropicConfig {
    var apiKey: String
    var model: String
    var baseURL: String
    var maxTokens: Int

    static let defaultModel = "claude-sonnet-4-6"
    static let defaultBaseURL = "https://api.anthropic.com"
    static let defaultMaxTokens = 8192
    static let apiVersion = "2023-06-01"

    /// Load config from Keychain + user defaults.
    static func load() -> AnthropicConfig {
        let key = KeychainHelper.read(service: "com.thrawn.anthropic", account: "api-key") ?? ""
        let model = UserDefaults.standard.string(forKey: "thrawn.anthropic.model") ?? defaultModel
        let baseURL = UserDefaults.standard.string(forKey: "thrawn.anthropic.baseURL") ?? defaultBaseURL
        let maxTokens = UserDefaults.standard.integer(forKey: "thrawn.anthropic.maxTokens")
        return AnthropicConfig(
            apiKey: key,
            model: model,
            baseURL: baseURL,
            maxTokens: maxTokens > 0 ? maxTokens : defaultMaxTokens
        )
    }

    var isConfigured: Bool { !apiKey.isEmpty }
}

// MARK: - Keychain Helper (simple wrapper)

enum KeychainHelper {
    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(service: String, account: String, value: String) {
        let data = Data(value.utf8)
        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - API Data Models

/// A message in the Anthropic conversation format.
struct AnthropicMessage: Codable {
    let role: String  // "user" or "assistant"
    let content: [AnthropicContentBlock]

    init(role: String, text: String) {
        self.role = role
        self.content = [.init(type: "text", text: text)]
    }

    init(role: String, content: [AnthropicContentBlock]) {
        self.role = role
        self.content = content
    }
}

struct AnthropicContentBlock: Codable {
    var type: String            // "text", "image"
    var text: String?
    var source: AnthropicImageSource?

    init(type: String, text: String) {
        self.type = type
        self.text = text
    }

    init(imageBase64: String, mediaType: String) {
        self.type = "image"
        self.source = AnthropicImageSource(type: "base64", media_type: mediaType, data: imageBase64)
    }
}

struct AnthropicImageSource: Codable {
    var type: String        // "base64"
    var media_type: String  // "image/jpeg", "image/png"
    var data: String        // base64 payload
}

/// Request body for POST /v1/messages
private struct MessagesRequest: Codable {
    let model: String
    let max_tokens: Int
    let messages: [AnthropicMessage]
    let stream: Bool
    var system: String?
}

/// Non-streaming response from POST /v1/messages
private struct MessagesResponse: Codable {
    struct Content: Codable {
        var type: String
        var text: String?
    }
    var id: String
    var model: String
    var content: [Content]
    var stop_reason: String?
    var usage: Usage?

    struct Usage: Codable {
        var input_tokens: Int?
        var output_tokens: Int?
    }
}

// MARK: - SSE Event Types

private enum SSEEventType: String {
    case messageStart = "message_start"
    case contentBlockStart = "content_block_start"
    case contentBlockDelta = "content_block_delta"
    case contentBlockStop = "content_block_stop"
    case messageDelta = "message_delta"
    case messageStop = "message_stop"
    case ping = "ping"
    case error = "error"
}

private struct SSEContentDelta: Codable {
    var type: String?       // "text_delta"
    var text: String?
}

private struct SSEDeltaEvent: Codable {
    var type: String?
    var index: Int?
    var delta: SSEContentDelta?
}

private struct SSEMessageStart: Codable {
    struct Message: Codable {
        var id: String?
        var model: String?
    }
    var type: String?
    var message: Message?
}

private struct SSEMessageDelta: Codable {
    struct Delta: Codable {
        var stop_reason: String?
    }
    var type: String?
    var delta: Delta?
    var usage: MessagesResponse.Usage?
}

private struct SSEError: Codable {
    struct ErrorDetail: Codable {
        var type: String?
        var message: String?
    }
    var type: String?
    var error: ErrorDetail?
}

// MARK: - Client

@MainActor
final class AnthropicClient: ObservableObject {
    @Published var connected = false          // API key configured + reachable
    @Published var authenticating = false
    @Published var lastError: String?
    @Published var apiKeyConfigured = false

    private var config: AnthropicConfig
    private var activeRuns: [String: Task<Void, Never>] = [:]
    private var monitorTask: Task<Void, Never>?

    init() {
        self.config = AnthropicConfig.load()
        self.apiKeyConfigured = config.isConfigured
    }

    /// Reload config (call after user enters/changes API key).
    func reloadConfig() {
        config = AnthropicConfig.load()
        apiKeyConfigured = config.isConfigured
        if config.isConfigured {
            Task { await refreshConnectionStatus() }
        } else {
            connected = false
        }
    }

    func setAPIKey(_ key: String) {
        KeychainHelper.save(service: "com.thrawn.anthropic", account: "api-key", value: key)
        reloadConfig()
    }

    func setModel(_ model: String) {
        UserDefaults.standard.set(model, forKey: "thrawn.anthropic.model")
        config.model = model
    }

    // MARK: - Connection Monitoring

    func connect() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshConnectionStatus()
                let pause: UInt64 = (self?.connected ?? false) ? 60_000_000_000 : 5_000_000_000
                try? await Task.sleep(nanoseconds: pause)
            }
        }
    }

    func disconnect() {
        monitorTask?.cancel()
        monitorTask = nil
        for task in activeRuns.values { task.cancel() }
        activeRuns.removeAll()
        connected = false
    }

    func refreshNow() {
        Task { await refreshConnectionStatus() }
    }

    private func refreshConnectionStatus() async {
        guard config.isConfigured else {
            connected = false
            lastError = "No API key configured."
            return
        }
        authenticating = true

        // Lightweight validation: hit the models endpoint or just try to start a messages request
        // We'll do a simple HEAD-like check by making a tiny request
        let reachable = await checkReachability()
        authenticating = false

        if reachable {
            connected = true
            lastError = nil
        } else {
            connected = false
            // Don't overwrite specific error messages
            if lastError == nil { lastError = "Cannot reach Anthropic API." }
        }
    }

    private func checkReachability() async -> Bool {
        guard let url = URL(string: "\(config.baseURL)/v1/messages") else { return false }
        // Send a minimal request that will fail fast but prove connectivity + auth
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(AnthropicConfig.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        // Empty messages array will return 400 (invalid) but proves auth works
        // A 401 means bad key. A timeout means unreachable.
        request.httpBody = Data(#"{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[]}"#.utf8)
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            // 400 = reached API, auth OK, just bad request (expected)
            // 200 = somehow worked
            // 401/403 = auth failed
            if http.statusCode == 401 || http.statusCode == 403 {
                lastError = "Invalid API key."
                return false
            }
            return http.statusCode == 400 || http.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Send Message (Streaming)

    /// Send a message with conversation history. Streams deltas in real-time.
    ///
    /// - Parameters:
    ///   - text: The user's message text.
    ///   - imageData: Optional image attachment (JPEG).
    ///   - history: Previous messages in the conversation for context.
    ///   - systemPrompt: Optional system prompt.
    ///   - sessionKey: Session identifier (for tracking active runs).
    ///   - onDelta: Called with each text chunk as it streams in.
    ///   - onComplete: Called with the full response text and model name.
    ///   - onError: Called if the request fails.
    func send(
        text: String,
        imageData: Data? = nil,
        history: [AnthropicMessage] = [],
        systemPrompt: String? = nil,
        sessionKey: String = "main",
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String, String?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard config.isConfigured else {
            onError("No API key configured. Open Settings to add your Anthropic API key.")
            return
        }

        let runTask = Task { [weak self] in
            guard let self else { return }
            defer { self.activeRuns.removeValue(forKey: sessionKey) }

            // Build the user message content blocks
            var contentBlocks: [AnthropicContentBlock] = []
            if let imageData {
                let base64 = imageData.base64EncodedString()
                contentBlocks.append(AnthropicContentBlock(imageBase64: base64, mediaType: "image/jpeg"))
            }
            contentBlocks.append(AnthropicContentBlock(type: "text", text: text))

            let userMessage = AnthropicMessage(role: "user", content: contentBlocks)

            // Combine history + new message
            var messages = history
            messages.append(userMessage)

            // Ensure messages alternate roles (Anthropic requires this)
            messages = Self.normalizeMessageOrder(messages)

            var requestBody = MessagesRequest(
                model: self.config.model,
                max_tokens: self.config.maxTokens,
                messages: messages,
                stream: true
            )
            if let systemPrompt, !systemPrompt.isEmpty {
                requestBody.system = systemPrompt
            }

            guard let url = URL(string: "\(self.config.baseURL)/v1/messages") else {
                onError("Invalid API URL.")
                return
            }

            guard let bodyData = try? JSONEncoder().encode(requestBody) else {
                onError("Could not encode request.")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue(self.config.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(AnthropicConfig.apiVersion, forHTTPHeaderField: "anthropic-version")
            request.timeoutInterval = 600  // 10 min for long agentic tasks

            await self.streamSSE(
                request: request,
                onDelta: onDelta,
                onComplete: onComplete,
                onError: onError
            )
        }

        activeRuns[sessionKey]?.cancel()
        activeRuns[sessionKey] = runTask
    }

    /// Cancel an active run.
    func abort(sessionKey: String = "main") {
        activeRuns[sessionKey]?.cancel()
        activeRuns.removeValue(forKey: sessionKey)
    }

    // MARK: - SSE Streaming

    private func streamSSE(
        request: URLRequest,
        maxRetries: Int = 3,
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String, String?) -> Void,
        onError: @escaping (String) -> Void
    ) async {
        var lastError: String = "Unknown error"

        for attempt in 1...maxRetries {
            guard !Task.isCancelled else { return }

            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)

                guard let http = response as? HTTPURLResponse else {
                    lastError = "Non-HTTP response"
                    continue
                }

                if http.statusCode == 401 || http.statusCode == 403 {
                    self.lastError = "Invalid API key."
                    onError("Authentication failed. Check your API key in Settings.")
                    return
                }

                if http.statusCode == 429 {
                    lastError = "Rate limited by Anthropic API."
                    let backoff: UInt64 = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: backoff)
                    continue
                }

                if http.statusCode == 529 {
                    lastError = "Anthropic API is overloaded. Retrying..."
                    let backoff: UInt64 = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: backoff)
                    continue
                }

                if http.statusCode >= 500 {
                    lastError = "Server error (\(http.statusCode))"
                    let backoff: UInt64 = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: backoff)
                    continue
                }

                if http.statusCode != 200 {
                    // Collect the error body
                    var errorBody = ""
                    for try await line in bytes.lines {
                        errorBody += line
                        if errorBody.count > 500 { break }
                    }
                    onError("API error (\(http.statusCode)): \(String(errorBody.prefix(300)))")
                    return
                }

                // Parse SSE stream
                var fullText = ""
                var modelName: String?
                var currentEvent = ""

                for try await line in bytes.lines {
                    guard !Task.isCancelled else { return }

                    if line.hasPrefix("event: ") {
                        currentEvent = String(line.dropFirst(7))
                        continue
                    }

                    if line.hasPrefix("data: ") {
                        let data = String(line.dropFirst(6))
                        guard let jsonData = data.data(using: .utf8) else { continue }

                        switch SSEEventType(rawValue: currentEvent) {
                        case .messageStart:
                            if let msg = try? JSONDecoder().decode(SSEMessageStart.self, from: jsonData) {
                                modelName = msg.message?.model
                            }

                        case .contentBlockDelta:
                            if let delta = try? JSONDecoder().decode(SSEDeltaEvent.self, from: jsonData),
                               let text = delta.delta?.text {
                                fullText += text
                                onDelta(text)
                            }

                        case .messageDelta:
                            // Contains stop_reason and final usage
                            break

                        case .messageStop:
                            self.connected = true
                            self.lastError = nil
                            onComplete(fullText, modelName)
                            return

                        case .error:
                            if let err = try? JSONDecoder().decode(SSEError.self, from: jsonData) {
                                let msg = err.error?.message ?? "Unknown streaming error"
                                if err.error?.type == "overloaded_error" {
                                    // Retry on overload
                                    lastError = msg
                                    break
                                }
                                onError(msg)
                                return
                            }

                        case .ping, .contentBlockStart, .contentBlockStop, .none:
                            break
                        }
                    }
                }

                // If we got here without message_stop, the stream ended unexpectedly
                if !fullText.isEmpty {
                    // Partial response — deliver what we have
                    onComplete(fullText, modelName)
                    return
                }

                lastError = "Stream ended without response"
                continue

            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .timedOut {
                lastError = "Request timed out"
            } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                lastError = "No internet connection"
                self.connected = false
            } catch {
                lastError = error.localizedDescription
            }

            // Exponential backoff
            if attempt < maxRetries {
                let backoff: UInt64 = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try? await Task.sleep(nanoseconds: backoff)
            }
        }

        onError(lastError)
    }

    // MARK: - Helpers

    /// Ensure messages alternate between user and assistant roles.
    /// Anthropic requires strictly alternating roles starting with user.
    static func normalizeMessageOrder(_ messages: [AnthropicMessage]) -> [AnthropicMessage] {
        guard !messages.isEmpty else { return messages }
        var result: [AnthropicMessage] = []

        for msg in messages {
            if let last = result.last, last.role == msg.role {
                // Same role back-to-back — merge text content
                var merged = last
                var blocks = last.content
                blocks.append(contentsOf: msg.content)
                merged = AnthropicMessage(role: last.role, content: blocks)
                result[result.count - 1] = merged
            } else {
                result.append(msg)
            }
        }

        // Must start with "user"
        if result.first?.role == "assistant" {
            result.insert(AnthropicMessage(role: "user", text: "(continued)"), at: 0)
        }

        return result
    }
}

// MARK: - Backward Compatibility Bridge
//
// Provides the same public API as the old GatewayWSClient so callers
// (ThreadStore, PrimarySessionView, etc.) can switch with minimal changes.

extension AnthropicClient {

    /// Bridge: send with the old GatewayWSClient signature.
    /// The `sessionKey` is used for run tracking only (not sent to API).
    func send(
        text: String,
        imageData: Data? = nil,
        sessionKey: String = "main",
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String, String?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        send(
            text: text,
            imageData: imageData,
            history: [],
            sessionKey: sessionKey,
            onDelta: onDelta,
            onComplete: onComplete,
            onError: onError
        )
    }

    /// Bridge: connectAndPrewarm (no-op for native client, just connect).
    func connectAndPrewarm(sessionKey: String = "main") {
        connect()
        refreshNow()
    }

    /// Bridge: fetchHistory is a no-op — native client doesn't have external history.
    /// Callers should use their own in-memory/persisted conversation history.
    func fetchHistory(
        sessionKey: String = "main",
        onHistory: @escaping ([GatewayHistoryEntry]) -> Void
    ) {
        // No external history in native mode.
        // Return empty — callers have their own conversation state.
        onHistory([])
    }

    /// Bridge: sessions list — not applicable for native API.
    /// Agent activity is detected via cron jobs.json state instead.
    func sessionsList() async -> [GatewayActiveSession] {
        return []
    }
}
