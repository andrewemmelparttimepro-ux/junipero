import Foundation
import SwiftUI

// MARK: - GLM API Client
//
// Kept under the existing OpenAIClient type name so current SwiftUI
// environment bindings keep working. The implementation targets Z.ai's
// OpenAI-compatible Chat Completions API for GLM-5.2.

@MainActor
final class OpenAIClient: ObservableObject {
    @Published var connected = false
    @Published var authenticating = false
    @Published var lastError: String?
    @Published var apiKeyConfigured = false

    private var apiKey: String = ""
    private var providerAPIKeys: [String: String] = [:]
    private var model: String
    private var reasoningEffort: String
    private var activeRuns: [String: Task<Void, Never>] = [:]
    private var baseURL = ProviderRouter.glmBaseURL

    init(
        model: String = AIProvider.chatgpt.defaultModel,
        reasoningEffort: String = ProviderRouter.premiumOpenAIReasoningEffort
    ) {
        self.model = model
        self.reasoningEffort = reasoningEffort
        loadKey()
    }

    // MARK: - Configuration

    private func loadKey() {
        // macOS may display an authorization dialog for every Keychain read when
        // an app is rebuilt or re-signed. Status checks happen during SwiftUI
        // rendering, so Keychain access here can multiply into dozens of blocking
        // dialogs. Runtime provider credentials are deliberately loaded only from
        // environment variables or private app-support files.
        apiKey = loadProviderKey(service: ProviderRouter.glmKeychainService)
        apiKeyConfigured = !apiKey.isEmpty
        providerAPIKeys[ProviderRouter.glmKeychainService] = apiKey

        let xaiKey = loadProviderKey(service: ProviderRouter.xaiKeychainService)
        providerAPIKeys[ProviderRouter.xaiKeychainService] = xaiKey
    }

    func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = trimmed
        apiKeyConfigured = !trimmed.isEmpty
        providerAPIKeys[ProviderRouter.glmKeychainService] = trimmed
        persistProviderKey(trimmed, service: ProviderRouter.glmKeychainService)
        Task { await refreshConnectionStatus() }
    }

    func setModel(_ model: String) {
        self.model = model
    }

    func setReasoningEffort(_ effort: String) {
        self.reasoningEffort = effort
    }

    func setBaseURL(_ url: String?) {
        let trimmed = (url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = trimmed.isEmpty ? ProviderRouter.glmBaseURL : trimmed
    }

    func hasAPIKey(service: String) -> Bool {
        guard let key = providerAPIKeys[service] else { return false }
        return !key.isEmpty
    }

    private func loadProviderKey(service: String) -> String {
        let env = ProcessInfo.processInfo.environment
        let environmentKey: String?
        let configFileName: String

        switch service {
        case ProviderRouter.xaiKeychainService:
            environmentKey = env["XAI_API_KEY"]
            configFileName = ProviderRouter.xaiConfigFileName
        default:
            environmentKey = env["ZAI_API_KEY"] ?? env["GLM_API_KEY"]
            configFileName = ProviderRouter.glmConfigFileName
        }

        if let key = environmentKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }

        let configURL = ThrawnPaths.appSupportDir.appendingPathComponent(configFileName)
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let key = json["apiKey"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            return ""
        }
        return key
    }

    private func persistProviderKey(_ key: String, service: String) {
        let configFileName = service == ProviderRouter.xaiKeychainService
            ? ProviderRouter.xaiConfigFileName
            : ProviderRouter.glmConfigFileName
        let configURL = ThrawnPaths.appSupportDir.appendingPathComponent(configFileName)

        do {
            try FileManager.default.createDirectory(
                at: ThrawnPaths.appSupportDir,
                withIntermediateDirectories: true
            )
            if key.isEmpty {
                try? FileManager.default.removeItem(at: configURL)
                return
            }
            let data = try JSONSerialization.data(withJSONObject: ["apiKey": key])
            try data.write(to: configURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        } catch {
            lastError = "Could not save API key: \(error.localizedDescription)"
        }
    }

    // MARK: - Connection

    func connect() {
        loadKey()
        Task { await refreshConnectionStatus() }
    }

    func refreshConnectionStatus() async {
        guard apiKeyConfigured else {
            connected = false
            return
        }
        authenticating = true

        let reachable = await checkReachability()
        authenticating = false
        connected = reachable
    }

    private func checkReachability() async -> Bool {
        guard let url = URL(string: "\(baseURL)/models") else { return false }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            if http.statusCode == 401 {
                lastError = "Invalid GLM API key."
                return false
            }
            if !(200...299).contains(http.statusCode) {
                lastError = "GLM reachability check failed with HTTP \(http.statusCode)."
                return false
            }
            lastError = nil
            return true
        } catch {
            lastError = "Could not reach GLM: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Send Message (Streaming)

    func send(
        text: String,
        imageData: Data? = nil,
        history: [OpenAIMessage] = [],
        systemPrompt: String? = nil,
        sessionKey: String = "main",
        modelOverride: String? = nil,
        reasoningEffortOverride: String? = nil,
        baseURLOverride: String? = nil,
        apiKeyServiceOverride: String? = nil,
        providerLabel: String = "GLM",
        includeReasoningControls: Bool = true,
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String, String?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        let cachedAPIKey = apiKeyServiceOverride.flatMap { providerAPIKeys[$0] } ?? apiKey

        let runTask = Task { [weak self] in
            guard let self else { return }
            defer { self.activeRuns.removeValue(forKey: sessionKey) }

            guard !cachedAPIKey.isEmpty else {
                onError("No \(providerLabel) API key configured.")
                return
            }

            var messages: [[String: Any]] = []
            let requestModel = modelOverride ?? self.model
            let requestReasoningEffort = reasoningEffortOverride ?? self.reasoningEffort
            let requestBaseURL = baseURLOverride ?? self.baseURL

            if let systemPrompt, !systemPrompt.isEmpty {
                messages.append(["role": "system", "content": systemPrompt])
            }

            for msg in history {
                messages.append(["role": msg.role, "content": msg.text])
            }

            if let imageData {
                let base64 = imageData.base64EncodedString()
                messages.append([
                    "role": "user",
                    "content": [
                        ["type": "text", "text": text],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
                    ]
                ])
            } else {
                messages.append(["role": "user", "content": text])
            }

            var body: [String: Any] = [
                "model": requestModel,
                "messages": messages,
                "stream": false,
                "max_tokens": 65536,
                "temperature": 0.6,
                "top_p": 0.95
            ]

            if includeReasoningControls {
                body["thinking"] = ["type": "enabled"]
                if !requestReasoningEffort.isEmpty {
                    body["reasoning_effort"] = requestReasoningEffort
                }
            }

            guard let url = URL(string: "\(requestBaseURL)/chat/completions") else {
                onError("Invalid \(providerLabel) API URL.")
                return
            }

            guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
                onError("Could not encode \(providerLabel) request.")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(cachedAPIKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 600

            await self.sendGLMResponse(
                request: request,
                responseModel: requestModel,
                providerLabel: providerLabel,
                onDelta: onDelta,
                onComplete: onComplete,
                onError: onError
            )
        }

        activeRuns[sessionKey]?.cancel()
        activeRuns[sessionKey] = runTask
    }

    func abort(sessionKey: String = "main") {
        activeRuns[sessionKey]?.cancel()
        activeRuns.removeValue(forKey: sessionKey)
    }

    // MARK: - Chat Completions API

    private func sendGLMResponse(
        request: URLRequest,
        responseModel: String,
        providerLabel: String,
        maxRetries: Int = 3,
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String, String?) -> Void,
        onError: @escaping (String) -> Void
    ) async {
        var lastError = "Unknown error"

        for attempt in 1...maxRetries {
            guard !Task.isCancelled else { return }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    lastError = "Non-HTTP response"
                    continue
                }

                if http.statusCode == 401 || http.statusCode == 403 {
                    self.lastError = "Invalid \(providerLabel) API key."
                    onError("\(providerLabel) authentication failed. Check the API key.")
                    return
                }

                if http.statusCode == 429 {
                    let errorMessage = Self.extractErrorMessage(from: data)
                    if Self.isInsufficientQuota(errorMessage) {
                        self.lastError = errorMessage
                        onError("\(providerLabel) quota exhausted: \(errorMessage)")
                        return
                    }
                    lastError = errorMessage.isEmpty ? "\(providerLabel) rate limited." : errorMessage
                    let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                        .flatMap { UInt64($0) }
                    let backoff: UInt64 = (retryAfter ?? UInt64(pow(2.0, Double(attempt)))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: backoff)
                    continue
                }

                if http.statusCode != 200 {
                    let errorMessage = Self.extractErrorMessage(from: data)
                    let detail = errorMessage.isEmpty
                        ? String((String(data: data, encoding: .utf8) ?? "").prefix(300))
                        : errorMessage
                    onError("\(providerLabel) API error (\(http.statusCode)): \(detail)")
                    return
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    onError("Could not parse \(providerLabel) response.")
                    return
                }

                if let error = json["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "GLM request failed."
                    onError(message)
                    return
                }

                guard let text = Self.extractOutputText(from: json), !text.isEmpty else {
                    onError("\(providerLabel) returned no text.")
                    return
                }

                self.connected = true
                self.lastError = nil
                onDelta(text)
                onComplete(text, responseModel)
                return

            } catch is CancellationError {
                return
            } catch {
                lastError = error.localizedDescription
            }

            if attempt < maxRetries {
                let backoff: UInt64 = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try? await Task.sleep(nanoseconds: backoff)
            }
        }

        onError(lastError)
    }

    private static func extractOutputText(from json: [String: Any]) -> String? {
        if let choices = json["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any] {
            if let content = message["content"] as? String {
                return content
            }
            if let content = message["content"] as? [[String: Any]] {
                let chunks = content.compactMap { block -> String? in
                    if let text = block["text"] as? String { return text }
                    if let text = block["content"] as? String { return text }
                    return nil
                }
                return chunks.joined()
            }
        }

        if let direct = json["output_text"] as? String {
            return direct
        }

        guard let output = json["output"] as? [[String: Any]] else { return nil }
        var chunks: [String] = []

        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for block in content {
                if let text = block["text"] as? String {
                    chunks.append(text)
                }
            }
        }

        return chunks.joined()
    }

    private static func extractErrorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        guard let error = json["error"] as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        let message = error["message"] as? String ?? "GLM request failed."
        if let code = error["code"] as? String, !code.isEmpty {
            return "\(message) [\(code)]"
        }
        return message
    }

    private static func isInsufficientQuota(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("insufficient_quota") || lower.contains("exceeded your current quota")
    }
}

// MARK: - OpenAI Message Model

struct OpenAIMessage {
    let role: String  // "system", "user", "assistant"
    let text: String
}
