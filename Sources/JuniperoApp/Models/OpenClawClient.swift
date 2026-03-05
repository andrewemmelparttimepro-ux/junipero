import Foundation

struct OpenClawConfig: Codable {
    var baseURL: String
    var model: String
    var token: String?
    var timeoutSeconds: Double
    var ollamaFallbackEnabled: Bool
    var ollamaBaseURL: String
    var ollamaModel: String

    static let `default` = OpenClawConfig(
        baseURL: "http://127.0.0.1:18789",
        model: "anthropic/claude-sonnet-4-6",
        token: nil,
        timeoutSeconds: 45,
        ollamaFallbackEnabled: true,
        ollamaBaseURL: "http://127.0.0.1:11434",
        ollamaModel: "kimi-k2.5"
    )

    enum CodingKeys: String, CodingKey {
        case baseURL
        case model
        case token
        case timeoutSeconds
        case ollamaFallbackEnabled
        case ollamaBaseURL
        case ollamaModel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = OpenClawConfig.default
        self.baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? defaults.baseURL
        self.model = try container.decodeIfPresent(String.self, forKey: .model) ?? defaults.model
        self.token = try container.decodeIfPresent(String.self, forKey: .token)
        self.timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? defaults.timeoutSeconds
        self.ollamaFallbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .ollamaFallbackEnabled) ?? defaults.ollamaFallbackEnabled
        self.ollamaBaseURL = try container.decodeIfPresent(String.self, forKey: .ollamaBaseURL) ?? defaults.ollamaBaseURL
        self.ollamaModel = try container.decodeIfPresent(String.self, forKey: .ollamaModel) ?? defaults.ollamaModel
    }

    init(
        baseURL: String,
        model: String,
        token: String?,
        timeoutSeconds: Double,
        ollamaFallbackEnabled: Bool,
        ollamaBaseURL: String,
        ollamaModel: String
    ) {
        self.baseURL = baseURL
        self.model = model
        self.token = token
        self.timeoutSeconds = timeoutSeconds
        self.ollamaFallbackEnabled = ollamaFallbackEnabled
        self.ollamaBaseURL = ollamaBaseURL
        self.ollamaModel = ollamaModel
    }
}

enum OpenClawClientError: LocalizedError {
    case invalidURL(String)
    case unauthorized
    case emptyResponse
    case serverStatus(Int, String)
    case decodeFailed
    case allBackendsFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "Invalid OpenClaw URL: \(value)"
        case .unauthorized:
            return "OpenClaw rejected authentication token."
        case .emptyResponse:
            return "OpenClaw returned an empty response."
        case .serverStatus(let status, let message):
            return "OpenClaw error \(status): \(message)"
        case .decodeFailed:
            return "Couldn't decode OpenClaw response."
        case .allBackendsFailed(let message):
            return message
        }
    }
}

actor OpenClawClient {
    struct InputMessage {
        let role: String
        let content: String
    }

    private let session: URLSession
    private let config: OpenClawConfig
    private var primaryCooldownUntil: Date?
    private var fallbackCooldownUntil: Date?

    init() {
        self.config = Self.resolveConfig()

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = max(5, config.timeoutSeconds)
        sessionConfig.timeoutIntervalForResource = max(10, config.timeoutSeconds + 10)
        self.session = URLSession(configuration: sessionConfig)
    }

    func send(message: String) async throws -> (text: String, model: String, latencyMs: Int) {
        let msgs = [InputMessage(role: "user", content: message)]
        return try await send(messages: msgs)
    }

    func send(messages: [InputMessage]) async throws -> (text: String, model: String, latencyMs: Int) {
        guard !messages.isEmpty else {
            throw OpenClawClientError.emptyResponse
        }
        var primaryError: Error?
        var fallbackError: Error?

        if !Self.isCooldownActive(primaryCooldownUntil) {
            do {
                return try await sendViaOpenClaw(messages: messages)
            } catch {
                primaryError = error
                if Self.shouldCooldown(error) {
                    primaryCooldownUntil = Date().addingTimeInterval(Self.cooldownSeconds(for: error))
                }
                await ChatDiagnostics.shared.log("primary-fail model=\(config.model) error=\(String(describing: error))")
            }
        }

        if config.ollamaFallbackEnabled && !Self.isCooldownActive(fallbackCooldownUntil) {
            do {
                let fallback = try await sendViaOllama(messages: messages)
                await ChatDiagnostics.shared.log("fallback-ok model=ollama/\(config.ollamaModel)")
                return fallback
            } catch {
                fallbackError = error
                if Self.shouldCooldown(error) {
                    fallbackCooldownUntil = Date().addingTimeInterval(Self.cooldownSeconds(for: error))
                }
                await ChatDiagnostics.shared.log("fallback-fail model=ollama/\(config.ollamaModel) error=\(String(describing: error))")
            }
        }

        if let primaryError {
            if let fallbackError {
                let primaryText = (primaryError as? LocalizedError)?.errorDescription ?? String(describing: primaryError)
                let fallbackText = (fallbackError as? LocalizedError)?.errorDescription ?? String(describing: fallbackError)
                throw OpenClawClientError.allBackendsFailed("Primary and fallback both failed. Primary: \(primaryText) | Fallback: \(fallbackText)")
            }
            throw primaryError
        }
        if let fallbackError {
            throw fallbackError
        }
        throw OpenClawClientError.allBackendsFailed("No available model backends are currently reachable.")
    }

    private func sendViaOpenClaw(messages: [InputMessage]) async throws -> (text: String, model: String, latencyMs: Int) {
        let endpointString = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/chat/completions"
        guard let url = URL(string: endpointString) else {
            throw OpenClawClientError.invalidURL(endpointString)
        }

        var lastError: Error?
        let maxAttempts = 3

        for attempt in 1...maxAttempts {
            do {
                let started = Date()
                let request = try buildRequest(url: url, messages: messages)
                let (data, response) = try await session.data(for: request)
                let latency = Int(Date().timeIntervalSince(started) * 1000)
                let parsed = try parseResponse(data: data, response: response)
                return (parsed.text, parsed.model ?? config.model, latency)
            } catch {
                lastError = error
                if Self.shouldCooldown(error) {
                    throw error
                }
                if attempt < maxAttempts && Self.shouldRetry(error) {
                    let delayNs = UInt64(attempt) * 400_000_000
                    try? await Task.sleep(nanoseconds: delayNs)
                    continue
                }
                throw error
            }
        }

        throw lastError ?? OpenClawClientError.decodeFailed
    }

    private func sendViaOllama(messages: [InputMessage]) async throws -> (text: String, model: String, latencyMs: Int) {
        let endpointString = config.ollamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/chat"
        guard let url = URL(string: endpointString) else {
            throw OpenClawClientError.invalidURL(endpointString)
        }

        var lastError: Error?
        let maxAttempts = 2
        for attempt in 1...maxAttempts {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let payload: [String: Any] = [
                    "model": config.ollamaModel,
                    "stream": false,
                    "messages": messages.map { ["role": $0.role, "content": $0.content] }
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                let started = Date()
                let (data, response) = try await session.data(for: request)
                let latency = Int(Date().timeIntervalSince(started) * 1000)

                guard let http = response as? HTTPURLResponse else {
                    throw OpenClawClientError.decodeFailed
                }
                if !(200..<300).contains(http.statusCode) {
                    let message = Self.extractErrorMessage(from: data)
                    throw OpenClawClientError.serverStatus(http.statusCode, message)
                }

                guard
                    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let msg = root["message"] as? [String: Any],
                    let text = msg["content"] as? String
                else {
                    throw OpenClawClientError.decodeFailed
                }

                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if clean.isEmpty {
                    throw OpenClawClientError.emptyResponse
                }
                return (clean, "ollama/\(config.ollamaModel)", latency)
            } catch {
                lastError = error
                if Self.shouldCooldown(error) {
                    throw error
                }
                if attempt < maxAttempts && Self.shouldRetry(error) {
                    let delayNs = UInt64(attempt) * 350_000_000
                    try? await Task.sleep(nanoseconds: delayNs)
                    continue
                }
                throw error
            }
        }
        throw lastError ?? OpenClawClientError.decodeFailed
    }

    private func buildRequest(url: URL, messages: [InputMessage]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = config.token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let payload: [String: Any] = [
            "model": config.model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    private func parseResponse(data: Data, response: URLResponse) throws -> (text: String, model: String?) {
        guard let http = response as? HTTPURLResponse else {
            throw OpenClawClientError.decodeFailed
        }

        if !(200..<300).contains(http.statusCode) {
            let message = Self.extractErrorMessage(from: data)
            if http.statusCode == 401 || http.statusCode == 403 {
                throw OpenClawClientError.unauthorized
            }
            throw OpenClawClientError.serverStatus(http.statusCode, message)
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let firstChoice = choices.first,
            let message = firstChoice["message"] as? [String: Any]
        else {
            throw OpenClawClientError.decodeFailed
        }

        let content = message["content"]
        let text = Self.extractAssistantText(from: content)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty {
            throw OpenClawClientError.emptyResponse
        }

        let model = root["model"] as? String
        return (text, model)
    }

    private static func extractAssistantText(from content: Any?) -> String? {
        if let text = content as? String {
            return text
        }
        if let parts = content as? [[String: Any]] {
            let joined = parts.compactMap { part -> String? in
                if let text = part["text"] as? String {
                    return text
                }
                if let nested = part["content"] as? String {
                    return nested
                }
                return nil
            }.joined(separator: "\n")
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private static func extractErrorMessage(from data: Data) -> String {
        if
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = root["error"] as? [String: Any],
            let message = error["message"] as? String,
            !message.isEmpty
        {
            return message
        }
        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        return "Unknown error"
    }

    private static func shouldRetry(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost:
                return true
            default:
                return false
            }
        }
        if let clientError = error as? OpenClawClientError {
            if case .serverStatus(let status, _) = clientError {
                return status == 429 || (500...599).contains(status)
            }
        }
        return false
    }

    private static func shouldCooldown(_ error: Error) -> Bool {
        guard let clientError = error as? OpenClawClientError else { return false }
        if case .serverStatus(let status, let message) = clientError {
            if status == 429 || status == 503 {
                return true
            }
            return message.localizedCaseInsensitiveContains("overloaded")
                || message.localizedCaseInsensitiveContains("rate limit")
                || message.localizedCaseInsensitiveContains("cooldown")
        }
        return false
    }

    private static func cooldownSeconds(for error: Error) -> TimeInterval {
        guard let clientError = error as? OpenClawClientError else { return 10 }
        if case .serverStatus(let status, _) = clientError, status == 429 {
            return 25
        }
        return 12
    }

    private static func isCooldownActive(_ date: Date?) -> Bool {
        guard let date else { return false }
        return date > Date()
    }

    private static func resolveConfig() -> OpenClawConfig {
        var config = OpenClawConfig.default

        if let homeConfig = readJuniperoConfig() {
            config.baseURL = homeConfig.baseURL
            config.model = homeConfig.model
            config.timeoutSeconds = homeConfig.timeoutSeconds
            config.ollamaFallbackEnabled = homeConfig.ollamaFallbackEnabled
            config.ollamaBaseURL = homeConfig.ollamaBaseURL
            config.ollamaModel = homeConfig.ollamaModel
            if let token = homeConfig.token, !token.isEmpty {
                config.token = token
            }
        }

        if let keychainToken = KeychainStore.loadProviderToken(), !keychainToken.isEmpty {
            config.token = keychainToken
        }

        if let discoveredToken = readOpenClawGatewayToken(), !discoveredToken.isEmpty {
            config.token = discoveredToken
        }

        if let envURL = ProcessInfo.processInfo.environment["JUNIPERO_OPENCLAW_URL"], !envURL.isEmpty {
            config.baseURL = envURL
        }
        if let envModel = ProcessInfo.processInfo.environment["JUNIPERO_OPENCLAW_MODEL"], !envModel.isEmpty {
            config.model = envModel
        }
        if let envToken = ProcessInfo.processInfo.environment["JUNIPERO_OPENCLAW_TOKEN"], !envToken.isEmpty {
            config.token = envToken
        }
        if let envOllamaURL = ProcessInfo.processInfo.environment["JUNIPERO_OLLAMA_URL"], !envOllamaURL.isEmpty {
            config.ollamaBaseURL = envOllamaURL
        }
        if let envOllamaModel = ProcessInfo.processInfo.environment["JUNIPERO_OLLAMA_MODEL"], !envOllamaModel.isEmpty {
            config.ollamaModel = envOllamaModel
        }
        if let envOllamaFallback = ProcessInfo.processInfo.environment["JUNIPERO_OLLAMA_FALLBACK_ENABLED"], !envOllamaFallback.isEmpty {
            config.ollamaFallbackEnabled = envOllamaFallback.lowercased() == "1" || envOllamaFallback.lowercased() == "true"
        }

        return config
    }

    private static func readJuniperoConfig() -> OpenClawConfig? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".junipero", isDirectory: true)
            .appendingPathComponent("config.json")
            .path
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(OpenClawConfig.self, from: data)
    }

    private static func readOpenClawGatewayToken() -> String? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("openclaw.json")
            .path
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let gateway = root["gateway"] as? [String: Any],
            let auth = gateway["auth"] as? [String: Any],
            let token = auth["token"] as? String
        else {
            return nil
        }
        return token
    }
}
