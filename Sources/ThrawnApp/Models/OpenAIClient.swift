import Foundation
import SwiftUI

// MARK: - OpenAI API Client
//
// Same wrapper pattern as AnthropicClient and GeminiAPIClient.
// Talks to api.openai.com/v1/chat/completions with SSE streaming.
// API key auth (no OAuth available for third-party apps).

@MainActor
final class OpenAIClient: ObservableObject {
    @Published var connected = false
    @Published var authenticating = false
    @Published var lastError: String?
    @Published var apiKeyConfigured = false

    private var apiKey: String = ""
    private var model: String
    private var activeRuns: [String: Task<Void, Never>] = [:]
    private var baseURL = "https://api.openai.com/v1"

    init(model: String = AIProvider.chatgpt.defaultModel) {
        self.model = model
        loadKey()
    }

    // MARK: - Configuration

    private func loadKey() {
        // 1. Keychain (primary — written by setAPIKey or by the app itself)
        if let key = KeychainHelper.read(service: "com.thrawn.openai", account: "api-key"), !key.isEmpty {
            apiKey = key
            apiKeyConfigured = true
            return
        }
        // 2. File fallback — ~/Library/Application Support/Thrawn/openai-config.json
        //    Lets CLI tools or external setup write the key without keychain ACL issues.
        //    On first successful read, promotes the key to keychain and deletes the file.
        let configURL = ThrawnPaths.appSupportDir.appendingPathComponent("openai-config.json")
        if let data = try? Data(contentsOf: configURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let key = json["apiKey"], !key.isEmpty {
            apiKey = key
            apiKeyConfigured = true
            // Promote to keychain so future launches skip the file
            KeychainHelper.save(service: "com.thrawn.openai", account: "api-key", value: key)
            try? FileManager.default.removeItem(at: configURL)
            return
        }
        apiKey = ""
        apiKeyConfigured = false
    }

    func setAPIKey(_ key: String) {
        KeychainHelper.save(service: "com.thrawn.openai", account: "api-key", value: key)
        apiKey = key
        apiKeyConfigured = true
        Task { await refreshConnectionStatus() }
    }

    func setModel(_ model: String) {
        self.model = model
    }

    func setBaseURL(_ url: String?) {
        let trimmed = (url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = trimmed.isEmpty ? "https://api.openai.com/v1" : trimmed
    }

    // MARK: - Connection

    func connect() {
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
                lastError = "Invalid API key."
                return false
            }
            return http.statusCode == 200
        } catch {
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
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String, String?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard apiKeyConfigured else {
            onError("No API key configured.")
            return
        }

        let runTask = Task { [weak self] in
            guard let self else { return }
            defer { self.activeRuns.removeValue(forKey: sessionKey) }

            // Build messages array
            var messages: [[String: Any]] = []

            if let systemPrompt, !systemPrompt.isEmpty {
                messages.append(["role": "system", "content": systemPrompt])
            }

            // History
            for msg in history {
                messages.append(["role": msg.role, "content": msg.text])
            }

            // Current user message
            if let imageData {
                let base64 = imageData.base64EncodedString()
                messages.append([
                    "role": "user",
                    "content": [
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]],
                        ["type": "text", "text": text]
                    ]
                ])
            } else {
                messages.append(["role": "user", "content": text])
            }

            let body: [String: Any] = [
                "model": self.model,
                "messages": messages,
                "stream": true,
                "max_tokens": 8192
            ]

            guard let url = URL(string: "\(self.baseURL)/chat/completions") else {
                onError("Invalid API URL.")
                return
            }

            guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
                onError("Could not encode request.")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(self.apiKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 600

            await self.streamOpenAISSE(request: request, onDelta: onDelta, onComplete: onComplete, onError: onError)
        }

        activeRuns[sessionKey]?.cancel()
        activeRuns[sessionKey] = runTask
    }

    func abort(sessionKey: String = "main") {
        activeRuns[sessionKey]?.cancel()
        activeRuns.removeValue(forKey: sessionKey)
    }

    // MARK: - SSE Streaming (OpenAI format)

    private func streamOpenAISSE(
        request: URLRequest,
        maxRetries: Int = 3,
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String, String?) -> Void,
        onError: @escaping (String) -> Void
    ) async {
        var lastError = "Unknown error"

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
                    onError("Authentication failed. Check your API key.")
                    return
                }

                if http.statusCode == 429 {
                    lastError = "Rate limited."
                    let backoff: UInt64 = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: backoff)
                    continue
                }

                if http.statusCode != 200 {
                    var errorBody = ""
                    for try await line in bytes.lines {
                        errorBody += line
                        if errorBody.count > 500 { break }
                    }
                    onError("API error (\(http.statusCode)): \(String(errorBody.prefix(300)))")
                    return
                }

                // Parse OpenAI SSE stream
                // data: {"choices":[{"delta":{"content":"..."}}]}
                // data: [DONE]
                var fullText = ""

                for try await line in bytes.lines {
                    guard !Task.isCancelled else { return }

                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst(6))

                    if payload == "[DONE]" {
                        self.connected = true
                        self.lastError = nil
                        onComplete(fullText, self.model)
                        return
                    }

                    guard let jsonData = payload.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let first = choices.first,
                          let delta = first["delta"] as? [String: Any],
                          let content = delta["content"] as? String else {
                        continue
                    }

                    fullText += content
                    onDelta(content)
                }

                if !fullText.isEmpty {
                    onComplete(fullText, self.model)
                    return
                }

                lastError = "Stream ended without response"
                continue

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
}

// MARK: - OpenAI Message Model

struct OpenAIMessage {
    let role: String  // "system", "user", "assistant"
    let text: String
}
