import Foundation
import SwiftUI

// MARK: - Gemini API Client
//
// Native HTTPS client for Google's Gemini API.
// Same wrapper pattern as AnthropicClient — HTTP + SSE + JSON.
// Uses OAuth2 tokens from GeminiOAuthClient.
// Also supports API key auth for users who prefer that.

@MainActor
final class GeminiAPIClient: ObservableObject {
    @Published var connected = false
    @Published var authenticating = false
    @Published var lastError: String?

    private var oauthClient: GeminiOAuthClient?
    private var apiKey: String?
    private var model: String
    private var activeRuns: [String: Task<Void, Never>] = [:]
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    @Published var apiKeyConfigured = false

    init(model: String = AIProvider.gemini.defaultModel) {
        self.model = model
        loadKey()
    }

    // MARK: - Configuration

    private func loadKey() {
        apiKey = KeychainHelper.read(service: "com.thrawn.gemini", account: "api-key")
        apiKeyConfigured = !(apiKey?.isEmpty ?? true)
    }

    func bindOAuth(_ client: GeminiOAuthClient) {
        self.oauthClient = client
    }

    func setAPIKey(_ key: String) {
        KeychainHelper.save(service: "com.thrawn.gemini", account: "api-key", value: key)
        self.apiKey = key
        self.apiKeyConfigured = true
        Task { await refreshConnectionStatus() }
    }

    func setModel(_ model: String) {
        self.model = model
    }

    // MARK: - Connection

    func connect() {
        Task { await refreshConnectionStatus() }
    }

    func refreshConnectionStatus() async {
        // Check if we have credentials (OAuth or API key)
        let hasOAuth = oauthClient?.authenticated ?? false
        let hasKey = !(apiKey?.isEmpty ?? true)

        guard hasOAuth || hasKey else {
            connected = false
            lastError = "Not signed in."
            return
        }

        authenticating = true

        // Try a lightweight request to verify
        let reachable = await checkReachability()
        authenticating = false
        connected = reachable

        if !reachable && lastError == nil {
            lastError = "Cannot reach Gemini API."
        }
    }

    private func checkReachability() async -> Bool {
        // Build URL — use API key in query if available, otherwise bare URL with Bearer auth
        let urlString: String
        if let key = apiKey, !key.isEmpty {
            urlString = "\(baseURL)/models?key=\(key)"
        } else {
            urlString = "\(baseURL)/models"
        }

        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        // Use Bearer token for OAuth
        if apiKey == nil || apiKey?.isEmpty == true {
            if let token = await oauthClient?.getAccessToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else {
                lastError = "No access token available."
                return false
            }
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }

            if http.statusCode == 401 || http.statusCode == 403 {
                // Try to parse the error for a helpful message
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    if message.contains("not enabled") || message.contains("API has not been used") {
                        lastError = "Enable the 'Generative Language API' in Google Cloud Console for your project."
                    } else {
                        lastError = "Auth failed: \(String(message.prefix(100)))"
                    }
                } else {
                    lastError = "Authentication failed. Please sign in again."
                }
                return false
            }
            if http.statusCode == 200 {
                lastError = nil
                return true
            }
            return false
        } catch {
            lastError = "Network error: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Send Message (Streaming)

    func send(
        text: String,
        imageData: Data? = nil,
        history: [GeminiMessage] = [],
        systemPrompt: String? = nil,
        sessionKey: String = "main",
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String, String?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        // Build auth query param
        let authParam: String
        if let key = apiKey, !key.isEmpty {
            authParam = "key=\(key)"
        } else {
            // OAuth — we'll set the header instead
            authParam = ""
        }

        let runTask = Task { [weak self] in
            guard let self else { return }
            defer { self.activeRuns.removeValue(forKey: sessionKey) }

            // Build the request body
            var contents: [[String: Any]] = []

            // History
            for msg in history {
                contents.append([
                    "role": msg.role,
                    "parts": [["text": msg.text]]
                ])
            }

            // Current user message
            var parts: [[String: Any]] = []
            if let imageData {
                parts.append([
                    "inline_data": [
                        "mime_type": "image/jpeg",
                        "data": imageData.base64EncodedString()
                    ]
                ])
            }
            parts.append(["text": text])
            contents.append([
                "role": "user",
                "parts": parts
            ])

            var body: [String: Any] = [
                "contents": contents,
                "generationConfig": [
                    "maxOutputTokens": 8192
                ]
            ]

            if let systemPrompt, !systemPrompt.isEmpty {
                body["systemInstruction"] = [
                    "parts": [["text": systemPrompt]]
                ]
            }

            // URL
            var urlString = "\(self.baseURL)/models/\(self.model):streamGenerateContent?alt=sse"
            if !authParam.isEmpty {
                urlString += "&\(authParam)"
            }

            guard let url = URL(string: urlString) else {
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
            request.timeoutInterval = 600

            // OAuth bearer token if no API key
            if authParam.isEmpty, let token = await self.oauthClient?.getAccessToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            await self.streamGeminiSSE(request: request, onDelta: onDelta, onComplete: onComplete, onError: onError)
        }

        activeRuns[sessionKey]?.cancel()
        activeRuns[sessionKey] = runTask
    }

    func abort(sessionKey: String = "main") {
        activeRuns[sessionKey]?.cancel()
        activeRuns.removeValue(forKey: sessionKey)
    }

    // MARK: - SSE Streaming (Gemini format)

    private func streamGeminiSSE(
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
                    // Read error body for details
                    var errorBody = ""
                    for try await line in bytes.lines {
                        errorBody += line
                        if errorBody.count > 1000 { break }
                    }
                    if errorBody.contains("not enabled") || errorBody.contains("API has not been used") {
                        self.lastError = "Generative Language API not enabled."
                        onError("Enable the 'Generative Language API' in your Google Cloud Console (project settings), then sign in again.")
                    } else if errorBody.contains("PERMISSION_DENIED") {
                        self.lastError = "Permission denied."
                        onError("Permission denied. You may need to enable the Generative Language API in Google Cloud Console.")
                    } else {
                        self.lastError = "Authentication failed."
                        onError("Authentication failed. Please sign out and sign in again.")
                    }
                    return
                }

                if http.statusCode == 429 {
                    lastError = "Rate limited."
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
                    var errorBody = ""
                    for try await line in bytes.lines {
                        errorBody += line
                        if errorBody.count > 500 { break }
                    }
                    onError("API error (\(http.statusCode)): \(String(errorBody.prefix(300)))")
                    return
                }

                // Parse Gemini SSE stream
                // Format: data: {"candidates":[{"content":{"parts":[{"text":"..."}]}}]}
                var fullText = ""

                for try await line in bytes.lines {
                    guard !Task.isCancelled else { return }

                    guard line.hasPrefix("data: ") else { continue }

                    let jsonString = String(line.dropFirst(6))
                    guard let jsonData = jsonString.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                          let candidates = json["candidates"] as? [[String: Any]],
                          let first = candidates.first,
                          let content = first["content"] as? [String: Any],
                          let parts = content["parts"] as? [[String: Any]] else {
                        continue
                    }

                    for part in parts {
                        if let text = part["text"] as? String {
                            fullText += text
                            onDelta(text)
                        }
                    }

                    // Check for finish reason
                    if let finishReason = first["finishReason"] as? String,
                       finishReason == "STOP" || finishReason == "MAX_TOKENS" {
                        self.connected = true
                        self.lastError = nil
                        onComplete(fullText, self.model)
                        return
                    }
                }

                // Stream ended
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

// MARK: - Gemini Message Model

struct GeminiMessage {
    let role: String  // "user" or "model"
    let text: String
}
