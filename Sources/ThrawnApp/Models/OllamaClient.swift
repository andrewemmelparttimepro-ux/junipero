import Foundation
import SwiftUI

// MARK: - Ollama Client
//
// Local LLM client that talks to Ollama at localhost:11434.
// Replaces all cloud providers (Anthropic, Gemini, OpenAI).
// No API keys, no OAuth, no cloud — everything runs locally.
//
// Ollama API:
//   GET  /api/tags → list available models
//   POST /api/chat → streaming chat completions (NDJSON)

/// A message in the Ollama conversation format.
struct OllamaMessage: Codable {
    let role: String   // "user", "assistant", "system"
    let content: String

    init(role: String, text: String) {
        self.role = role
        self.content = text
    }
}

@MainActor
final class OllamaClient: ObservableObject {
    @Published var connected = false
    @Published var authenticating = false
    @Published var lastError: String?
    @Published var models: [String] = []
    @Published var selectedModel: String = ""

    private var baseURL = "http://localhost:11434"
    private var activeRuns: [String: Task<Void, Never>] = [:]

    private let modelKey = "thrawn.ollama.selectedModel"

    // Expose for compatibility with code that checks apiKeyConfigured
    var apiKeyConfigured: Bool { connected }

    init() {
        // Restore last selected model
        if let saved = UserDefaults.standard.string(forKey: modelKey), !saved.isEmpty {
            selectedModel = saved
        }
    }

    // MARK: - Connection

    func connect() {
        Task { await refreshConnectionStatus() }
    }

    func refreshConnectionStatus() async {
        authenticating = true
        let reachable = await fetchModels()
        authenticating = false
        connected = reachable

        if !reachable {
            lastError = "Cannot reach Ollama at \(baseURL). Is Ollama running?"
        } else {
            lastError = nil
        }
    }

    func refreshNow() {
        Task { await refreshConnectionStatus() }
    }

    // MARK: - Model Discovery

    /// Fetch available models from Ollama. Returns true if reachable.
    @discardableResult
    func fetchModels() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }

            // Parse {"models": [{"name": "llama3:latest", ...}, ...]}
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelList = json["models"] as? [[String: Any]] else { return false }

            let names = modelList.compactMap { $0["name"] as? String }.sorted()
            self.models = names

            // Auto-select: restore saved model if still available, otherwise pick first
            if !names.isEmpty {
                if selectedModel.isEmpty || !names.contains(selectedModel) {
                    // Prefer a larger model if available
                    let preferred = names.first(where: { $0.contains("llama") || $0.contains("qwen") || $0.contains("mistral") }) ?? names[0]
                    selectedModel = preferred
                    UserDefaults.standard.set(preferred, forKey: modelKey)
                }
            }

            return !names.isEmpty
        } catch {
            return false
        }
    }

    func selectModel(_ model: String) {
        selectedModel = model
        UserDefaults.standard.set(model, forKey: modelKey)
    }

    // MARK: - Send Message (Streaming)

    func send(
        text: String,
        imageData: Data? = nil,
        history: [OllamaMessage] = [],
        systemPrompt: String? = nil,
        sessionKey: String = "main",
        model: String? = nil,
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String, String?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        let effectiveModel = model ?? selectedModel
        guard connected, !effectiveModel.isEmpty else {
            onError("Ollama not connected or no model selected.")
            return
        }

        // Cancel existing run for this session
        activeRuns[sessionKey]?.cancel()

        let task = Task.detached { [weak self, baseURL] in
            let selectedModel = effectiveModel
            guard let self else { return }

            do {
                guard let url = URL(string: "\(baseURL)/api/chat") else {
                    await MainActor.run { onError("Invalid Ollama URL.") }
                    return
                }

                // Build messages array
                var messages: [[String: Any]] = []

                // System prompt
                if let sys = systemPrompt, !sys.isEmpty {
                    messages.append(["role": "system", "content": sys])
                }

                // History
                for msg in history {
                    messages.append(["role": msg.role, "content": msg.content])
                }

                // Current user message
                var userMessage: [String: Any] = ["role": "user", "content": text]
                if let imageData {
                    // Ollama supports images as base64 in an "images" array
                    let base64 = imageData.base64EncodedString()
                    userMessage["images"] = [base64]
                }
                messages.append(userMessage)

                let body: [String: Any] = [
                    "model": selectedModel,
                    "messages": messages,
                    "stream": true
                ]

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                request.timeoutInterval = 600  // 10 min for long generations

                // Retry the request on transient failures (5xx, 429, flaky network during
                // clamshell-sleep DarkWake cycles). Retries happen BEFORE streaming starts —
                // once we begin consuming tokens we can't safely replay.
                let maxAttempts = 3
                let baseDelays: [Double] = [0.8, 2.4, 6.0]  // seconds, before jitter

                var asyncBytes: URLSession.AsyncBytes!
                var response: URLResponse!
                var lastErrorDetail: String = ""
                var attempt = 0

                streamOpen: while attempt < maxAttempts {
                    attempt += 1
                    if Task.isCancelled { return }

                    do {
                        let (b, r) = try await URLSession.shared.bytes(for: request)
                        guard let http = r as? HTTPURLResponse else {
                            lastErrorDetail = "Invalid response from Ollama."
                            break streamOpen
                        }

                        if (200..<300).contains(http.statusCode) {
                            asyncBytes = b
                            response = r
                            break streamOpen
                        }

                        // Non-2xx. Decide whether to retry.
                        let retryable = http.statusCode == 429 || (500...504).contains(http.statusCode)
                        let errMsg: String
                        switch http.statusCode {
                        case 404:
                            errMsg = "Model '\(selectedModel)' not found. Try pulling it: ollama pull \(selectedModel)"
                        case 500:
                            errMsg = "Ollama server error. Check Ollama logs."
                        default:
                            errMsg = "Ollama returned HTTP \(http.statusCode)."
                        }

                        if retryable && attempt < maxAttempts {
                            lastErrorDetail = errMsg
                            let base = baseDelays[min(attempt - 1, baseDelays.count - 1)]
                            let jitter = Double.random(in: 0.75...1.25)
                            try? await Task.sleep(nanoseconds: UInt64(base * jitter * 1_000_000_000))
                            continue
                        }

                        // Terminal HTTP error (non-retryable or retries exhausted).
                        let suffix = attempt > 1 ? " (after \(attempt) attempts)" : ""
                        await MainActor.run { onError(errMsg + suffix) }
                        return

                    } catch is CancellationError {
                        return
                    } catch let urlErr as URLError {
                        // Transient network errors map to retryable URLError codes.
                        let transient: Set<URLError.Code> = [
                            .timedOut, .networkConnectionLost, .notConnectedToInternet,
                            .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                            .resourceUnavailable, .internationalRoamingOff
                        ]
                        lastErrorDetail = "Ollama error: \(urlErr.localizedDescription)"

                        if transient.contains(urlErr.code) && attempt < maxAttempts {
                            let base = baseDelays[min(attempt - 1, baseDelays.count - 1)]
                            let jitter = Double.random(in: 0.75...1.25)
                            try? await Task.sleep(nanoseconds: UInt64(base * jitter * 1_000_000_000))
                            continue
                        }

                        let suffix = attempt > 1 ? " (after \(attempt) attempts)" : ""
                        await MainActor.run { onError(lastErrorDetail + suffix) }
                        return
                    }
                }

                guard asyncBytes != nil, response != nil else {
                    let suffix = attempt > 1 ? " (after \(attempt) attempts)" : ""
                    await MainActor.run { onError(lastErrorDetail.isEmpty ? "Ollama unreachable." : lastErrorDetail + suffix) }
                    return
                }

                var accumulated = ""

                for try await line in asyncBytes.lines {
                    if Task.isCancelled { break }

                    guard let lineData = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                        continue
                    }

                    // Ollama NDJSON format:
                    // {"model":"llama3","message":{"role":"assistant","content":"Hello"},"done":false}
                    // Final: {"model":"llama3","message":{"role":"assistant","content":""},"done":true}

                    if let message = json["message"] as? [String: Any],
                       let content = message["content"] as? String,
                       !content.isEmpty {
                        accumulated += content
                        await MainActor.run { onDelta(content) }
                    }

                    if let done = json["done"] as? Bool, done {
                        let modelName = json["model"] as? String ?? selectedModel
                        FlightRecorder.logLLM(
                            agent: "chat", model: selectedModel,
                            promptLength: text.count,
                            responseLength: accumulated.count,
                            durationMs: 0,
                            sessionKey: sessionKey,
                            systemPromptLength: systemPrompt?.count ?? 0,
                            success: true,
                            responseSummary: accumulated
                        )
                        await MainActor.run { onComplete(accumulated, modelName) }
                        return
                    }
                }

                // If we get here without "done":true, complete with what we have
                if !accumulated.isEmpty {
                    await MainActor.run { onComplete(accumulated, selectedModel) }
                } else if !Task.isCancelled {
                    await MainActor.run { onError("Empty response from Ollama.") }
                }

            } catch is CancellationError {
                // Task was cancelled — don't report error
            } catch {
                FlightRecorder.logLLM(
                    agent: "chat", model: selectedModel,
                    promptLength: text.count, responseLength: 0,
                    durationMs: 0, sessionKey: sessionKey,
                    success: false, error: error.localizedDescription
                )
                await MainActor.run { onError("Ollama error: \(error.localizedDescription)") }
            }
        }

        activeRuns[sessionKey] = task
    }

    // MARK: - Convenience

    /// Stop all active runs.
    func cancelAll() {
        for (_, task) in activeRuns { task.cancel() }
        activeRuns.removeAll()
    }
}
