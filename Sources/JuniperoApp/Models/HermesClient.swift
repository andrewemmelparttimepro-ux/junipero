import Foundation

// MARK: - Hermes Agent Configuration

struct HermesConfig: Codable {
    var baseURL: String
    var model: String
    var apiKey: String?
    var timeoutSeconds: Double
    var ollamaFallbackEnabled: Bool
    var ollamaBaseURL: String
    var ollamaModel: String

    static let `default` = HermesConfig(
        baseURL: "http://127.0.0.1:8642",
        model: "hermes-agent",
        apiKey: nil,
        timeoutSeconds: 60,
        ollamaFallbackEnabled: true,
        ollamaBaseURL: "http://127.0.0.1:11434",
        ollamaModel: "qwen2.5-coder:7b"
    )

    enum CodingKeys: String, CodingKey {
        case baseURL, model, apiKey, timeoutSeconds
        case ollamaFallbackEnabled, ollamaBaseURL, ollamaModel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = HermesConfig.default
        self.baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? defaults.baseURL
        self.model = try container.decodeIfPresent(String.self, forKey: .model) ?? defaults.model
        self.apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        self.timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? defaults.timeoutSeconds
        self.ollamaFallbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .ollamaFallbackEnabled) ?? defaults.ollamaFallbackEnabled
        self.ollamaBaseURL = try container.decodeIfPresent(String.self, forKey: .ollamaBaseURL) ?? defaults.ollamaBaseURL
        self.ollamaModel = try container.decodeIfPresent(String.self, forKey: .ollamaModel) ?? defaults.ollamaModel
    }

    init(
        baseURL: String, model: String, apiKey: String?,
        timeoutSeconds: Double, ollamaFallbackEnabled: Bool,
        ollamaBaseURL: String, ollamaModel: String
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.timeoutSeconds = timeoutSeconds
        self.ollamaFallbackEnabled = ollamaFallbackEnabled
        self.ollamaBaseURL = ollamaBaseURL
        self.ollamaModel = ollamaModel
    }
}

// MARK: - Hermes Client Error

enum HermesClientError: LocalizedError {
    case invalidURL(String)
    case unauthorized
    case emptyResponse
    case serverStatus(Int, String)
    case decodeFailed
    case allBackendsFailed(String)
    case hermesNotRunning

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "Invalid Hermes URL: \(value)"
        case .unauthorized:
            return "Hermes rejected authentication."
        case .emptyResponse:
            return "Hermes returned an empty response."
        case .serverStatus(let status, let message):
            return "Hermes error \(status): \(message)"
        case .decodeFailed:
            return "Could not decode Hermes response."
        case .allBackendsFailed(let message):
            return message
        case .hermesNotRunning:
            return "Hermes Agent is not running. Junipero will attempt to start it."
        }
    }
}

// MARK: - Hermes Client

actor HermesClient {
    struct InputMessage {
        let role: String
        let content: String
    }

    private let session: URLSession
    private var cooldownUntil: Date?
    private var fallbackCooldownUntil: Date?

    init() {
        let config = Self.resolveConfig()
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = max(5, config.timeoutSeconds)
        sessionConfig.timeoutIntervalForResource = max(10, config.timeoutSeconds + 15)
        self.session = URLSession(configuration: sessionConfig)
    }

    // MARK: - Public API

    func send(message: String) async throws -> (text: String, model: String, latencyMs: Int) {
        let msgs = [InputMessage(role: "user", content: message)]
        return try await send(messages: msgs)
    }

    func send(messages: [InputMessage]) async throws -> (text: String, model: String, latencyMs: Int) {
        guard !messages.isEmpty else { throw HermesClientError.emptyResponse }
        let config = Self.resolveConfig()

        // Try Hermes gateway first
        if !Self.isCooldownActive(cooldownUntil) {
            do {
                let result = try await sendViaHermes(messages: messages, config: config)
                return result
            } catch {
                if Self.shouldCooldown(error) {
                    cooldownUntil = Date().addingTimeInterval(Self.cooldownSeconds(for: error))
                }
                await ChatDiagnostics.shared.log("hermes-fail error=\(String(describing: error))")
                // Fall through to Ollama fallback
                if !config.ollamaFallbackEnabled {
                    throw error
                }
            }
        }

        // Ollama fallback
        if config.ollamaFallbackEnabled && !Self.isCooldownActive(fallbackCooldownUntil) {
            do {
                let fallback = try await sendViaOllama(messages: messages, config: config)
                await ChatDiagnostics.shared.log("fallback-ok model=ollama/\(config.ollamaModel)")
                return fallback
            } catch {
                if Self.shouldCooldown(error) {
                    fallbackCooldownUntil = Date().addingTimeInterval(Self.cooldownSeconds(for: error))
                }
                await ChatDiagnostics.shared.log("fallback-fail error=\(String(describing: error))")
                throw HermesClientError.allBackendsFailed("Hermes and Ollama fallback both unreachable.")
            }
        }

        throw HermesClientError.allBackendsFailed("No available backends are currently reachable.")
    }

    func checkHealth() async -> Bool {
        let config = Self.resolveConfig()
        let endpoint = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/health"
        guard let url = URL(string: endpoint) else { return false }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 5
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    // MARK: - Hermes Gateway (OpenAI-compatible at port 8642)

    private func sendViaHermes(messages: [InputMessage], config: HermesConfig) async throws -> (text: String, model: String, latencyMs: Int) {
        let endpoint = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw HermesClientError.invalidURL(endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let key = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let payload: [String: Any] = [
            "model": config.model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        var lastError: Error?
        let maxAttempts = 3

        for attempt in 1...maxAttempts {
            do {
                let started = Date()
                let (data, response) = try await session.data(for: request)
                let latency = Int(Date().timeIntervalSince(started) * 1000)
                let parsed = try parseOpenAIResponse(data: data, response: response)
                let model = parsed.model ?? config.model
                return (parsed.text, model, latency)
            } catch {
                lastError = error
                if Self.shouldCooldown(error) { throw error }
                if attempt < maxAttempts && Self.shouldRetry(error) {
                    let delayNs = UInt64(attempt) * 400_000_000
                    try? await Task.sleep(nanoseconds: delayNs)
                    continue
                }
                throw error
            }
        }
        throw lastError ?? HermesClientError.decodeFailed
    }

    // MARK: - Ollama Fallback

    private func sendViaOllama(messages: [InputMessage], config: HermesConfig) async throws -> (text: String, model: String, latencyMs: Int) {
        let endpoint = config.ollamaBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/chat"
        guard let url = URL(string: endpoint) else {
            throw HermesClientError.invalidURL(endpoint)
        }

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

        guard let http = response as? HTTPURLResponse else { throw HermesClientError.decodeFailed }
        if !(200..<300).contains(http.statusCode) {
            let message = Self.extractErrorMessage(from: data)
            throw HermesClientError.serverStatus(http.statusCode, message)
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let msg = root["message"] as? [String: Any],
            let text = msg["content"] as? String
        else { throw HermesClientError.decodeFailed }

        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { throw HermesClientError.emptyResponse }
        return (clean, "ollama/\(config.ollamaModel)", latency)
    }

    // MARK: - Response Parsing

    private func parseOpenAIResponse(data: Data, response: URLResponse) throws -> (text: String, model: String?) {
        guard let http = response as? HTTPURLResponse else { throw HermesClientError.decodeFailed }

        if !(200..<300).contains(http.statusCode) {
            let message = Self.extractErrorMessage(from: data)
            if http.statusCode == 401 || http.statusCode == 403 {
                throw HermesClientError.unauthorized
            }
            throw HermesClientError.serverStatus(http.statusCode, message)
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let firstChoice = choices.first,
            let message = firstChoice["message"] as? [String: Any]
        else { throw HermesClientError.decodeFailed }

        let content = message["content"]
        let text = Self.extractAssistantText(from: content)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty { throw HermesClientError.emptyResponse }

        let model = root["model"] as? String
        return (text, model)
    }

    // MARK: - Helpers

    private static func extractAssistantText(from content: Any?) -> String? {
        if let text = content as? String { return text }
        if let parts = content as? [[String: Any]] {
            let joined = parts.compactMap { part -> String? in
                if let text = part["text"] as? String { return text }
                if let nested = part["content"] as? String { return nested }
                return nil
            }.joined(separator: "\n")
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private static func extractErrorMessage(from data: Data) -> String {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = root["error"] as? [String: Any],
           let message = error["message"] as? String, !message.isEmpty
        { return message }
        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        return "Unknown error"
    }

    private static func shouldRetry(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                return true
            default: return false
            }
        }
        if let e = error as? HermesClientError, case .serverStatus(let status, _) = e {
            return status == 429 || (500...599).contains(status)
        }
        return false
    }

    private static func shouldCooldown(_ error: Error) -> Bool {
        guard let e = error as? HermesClientError else { return false }
        if case .serverStatus(let status, let message) = e {
            if status == 429 || status == 503 { return true }
            return message.localizedCaseInsensitiveContains("overloaded")
                || message.localizedCaseInsensitiveContains("rate limit")
        }
        return false
    }

    private static func cooldownSeconds(for error: Error) -> TimeInterval {
        guard let e = error as? HermesClientError else { return 10 }
        if case .serverStatus(let status, _) = e, status == 429 { return 25 }
        return 12
    }

    private static func isCooldownActive(_ date: Date?) -> Bool {
        guard let date else { return false }
        return date > Date()
    }

    // MARK: - Config Resolution

    static func resolveConfig() -> HermesConfig {
        var config = HermesConfig.default

        if let homeConfig = readJuniperoConfig() {
            config.baseURL = homeConfig.baseURL
            config.model = homeConfig.model
            config.timeoutSeconds = homeConfig.timeoutSeconds
            config.ollamaFallbackEnabled = homeConfig.ollamaFallbackEnabled
            config.ollamaBaseURL = homeConfig.ollamaBaseURL
            config.ollamaModel = homeConfig.ollamaModel
            if let key = homeConfig.apiKey, !key.isEmpty {
                config.apiKey = key
            }
        }

        if let keychainToken = KeychainStore.loadProviderToken(), !keychainToken.isEmpty {
            config.apiKey = keychainToken
        }

        // Environment overrides
        if let envURL = ProcessInfo.processInfo.environment["JUNIPERO_HERMES_URL"], !envURL.isEmpty {
            config.baseURL = envURL
        }
        if let envModel = ProcessInfo.processInfo.environment["JUNIPERO_HERMES_MODEL"], !envModel.isEmpty {
            config.model = envModel
        }
        if let envKey = ProcessInfo.processInfo.environment["JUNIPERO_HERMES_KEY"], !envKey.isEmpty {
            config.apiKey = envKey
        }
        if let envOllamaURL = ProcessInfo.processInfo.environment["JUNIPERO_OLLAMA_URL"], !envOllamaURL.isEmpty {
            config.ollamaBaseURL = envOllamaURL
        }
        if let envOllamaModel = ProcessInfo.processInfo.environment["JUNIPERO_OLLAMA_MODEL"], !envOllamaModel.isEmpty {
            config.ollamaModel = envOllamaModel
        }
        if let envFallback = ProcessInfo.processInfo.environment["JUNIPERO_OLLAMA_FALLBACK_ENABLED"], !envFallback.isEmpty {
            config.ollamaFallbackEnabled = envFallback.lowercased() == "1" || envFallback.lowercased() == "true"
        }

        return config
    }

    private static func readJuniperoConfig() -> HermesConfig? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".junipero", isDirectory: true)
            .appendingPathComponent("config.json")
            .path
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(HermesConfig.self, from: data)
    }
}
