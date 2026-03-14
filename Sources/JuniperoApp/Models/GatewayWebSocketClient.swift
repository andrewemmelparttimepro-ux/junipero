import Foundation
import SwiftUI

// MARK: - Gateway WebSocket Protocol

struct GatewayMessage: Codable {
    let type: String
    var payload: GatewayPayload?

    struct GatewayPayload: Codable {
        // connect.params.auth
        var auth: GatewayAuth?
        // chat.send
        var text: String?
        var idempotencyKey: String?
        var sessionKey: String?
        // chat.history response entries
        var entries: [GatewayHistoryEntry]?
        // chat streaming
        var delta: String?
        var final: Bool?
        var runId: String?
        var status: String?
        var error: String?
        var model: String?
        var role: String?
        var content: String?

        enum CodingKeys: String, CodingKey {
            case auth, text, idempotencyKey, sessionKey, entries
            case delta, final, runId, status, error, model, role, content
        }
    }

    struct GatewayAuth: Codable {
        var token: String
    }
}

struct GatewayHistoryEntry: Codable {
    var role: String
    var content: String?
    var text: String?
    var createdAt: String?
    var model: String?
    var aborted: Bool?

    var resolvedContent: String { content ?? text ?? "" }
}

// MARK: - Gateway WebSocket Client

@MainActor
final class GatewayWSClient: NSObject, ObservableObject {
    @Published var connected: Bool = false
    @Published var authenticating: Bool = false
    @Published var lastError: String?

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var config: GatewayWSConfig
    private var onDelta: ((String) -> Void)?
    private var onComplete: ((String, String?) -> Void)?
    private var onError: ((String) -> Void)?
    private var onHistory: (([GatewayHistoryEntry]) -> Void)?
    private var pendingMessage: String?
    private var pendingKey: String?
    private var streamBuffer: String = ""
    private var currentModel: String = ""
    private var isStreaming: Bool = false
    private var pingTask: Task<Void, Never>?

    init(config: GatewayWSConfig = .default) {
        self.config = config
    }

    func connect() {
        guard webSocket == nil else { return }

        let wsURL = config.wsURL
        guard let url = URL(string: wsURL) else {
            lastError = "Invalid Gateway URL: \(wsURL)"
            return
        }

        authenticating = true
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 10
        urlSession = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: nil)
        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()
        startReceiving()
    }

    func disconnect() {
        pingTask?.cancel()
        pingTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession = nil
        connected = false
        authenticating = false
    }

    func send(
        text: String,
        sessionKey: String = "main",
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String, String?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        let key = UUID().uuidString
        self.onDelta = onDelta
        self.onComplete = onComplete
        self.onError = onError
        self.streamBuffer = ""
        self.currentModel = ""
        self.isStreaming = false

        let msg = GatewayMessage(
            type: "chat.send",
            payload: .init(
                auth: nil,
                text: text,
                idempotencyKey: key,
                sessionKey: sessionKey,
                entries: nil,
                delta: nil,
                final: nil,
                runId: nil,
                status: nil,
                error: nil,
                model: nil,
                role: nil,
                content: nil
            )
        )
        sendRaw(msg)
    }

    func fetchHistory(
        sessionKey: String = "main",
        onHistory: @escaping ([GatewayHistoryEntry]) -> Void
    ) {
        self.onHistory = onHistory
        let msg = GatewayMessage(
            type: "chat.history",
            payload: .init(
                auth: nil,
                text: nil,
                idempotencyKey: nil,
                sessionKey: sessionKey,
                entries: nil, delta: nil, final: nil, runId: nil,
                status: nil, error: nil, model: nil, role: nil, content: nil
            )
        )
        sendRaw(msg)
    }

    func abort(sessionKey: String = "main") {
        let msg = GatewayMessage(
            type: "chat.abort",
            payload: .init(
                auth: nil, text: nil, idempotencyKey: nil,
                sessionKey: sessionKey,
                entries: nil, delta: nil, final: nil, runId: nil,
                status: nil, error: nil, model: nil, role: nil, content: nil
            )
        )
        sendRaw(msg)
    }

    // MARK: - Private

    func sendRaw(_ message: GatewayMessage) {
        guard let data = try? JSONEncoder().encode(message),
              let text = String(data: data, encoding: .utf8) else { return }

        if connected {
            webSocket?.send(.string(text)) { _ in }
        } else {
            pendingMessage = text
            connect()
        }
    }

    func authenticate() {
        let auth = GatewayMessage(
            type: "connect.params.auth",
            payload: .init(
                auth: .init(token: config.token),
                text: nil, idempotencyKey: nil, sessionKey: nil,
                entries: nil, delta: nil, final: nil, runId: nil,
                status: nil, error: nil, model: nil, role: nil, content: nil
            )
        )
        guard let data = try? JSONEncoder().encode(auth),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocket?.send(.string(text)) { _ in }
    }

    func startReceiving() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.handle(message: message)
                    self.startReceiving()
                case .failure(let error):
                    self.connected = false
                    self.authenticating = false
                    self.lastError = error.localizedDescription
                    self.onError?(error.localizedDescription)
                    self.webSocket = nil
                    self.urlSession = nil
                    // Retry after 3s
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await self.connect()
                    }
                }
            }
        }
    }

    func handle(message: URLSessionWebSocketTask.Message) {
        var text: String?
        switch message {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8)
        @unknown default: break
        }
        guard let text else { return }
        guard let data = text.data(using: .utf8) else { return }
        guard let msg = try? JSONDecoder().decode(GatewayMessage.self, from: data) else { return }

        switch msg.type {
        case "connected", "connect.ok":
            authenticating = false
            connected = true
            lastError = nil
            authenticate()
            if let pending = pendingMessage {
                pendingMessage = nil
                webSocket?.send(.string(pending)) { _ in }
            }

        case "auth.ok":
            connected = true
            authenticating = false
            lastError = nil
            if let pending = pendingMessage {
                pendingMessage = nil
                webSocket?.send(.string(pending)) { _ in }
            }

        case "chat":
            // Streaming delta
            if let delta = msg.payload?.delta {
                streamBuffer += delta
                isStreaming = true
                onDelta?(delta)
            }
            if let model = msg.payload?.model, !model.isEmpty {
                currentModel = model
            }
            // Completion
            if msg.payload?.final == true {
                let finalText = streamBuffer.isEmpty ? (msg.payload?.content ?? "") : streamBuffer
                onComplete?(finalText, currentModel.isEmpty ? nil : currentModel)
                streamBuffer = ""
                isStreaming = false
            }

        case "chat.history":
            if let entries = msg.payload?.entries {
                onHistory?(entries)
                onHistory = nil
            }

        case "chat.abort":
            onError?("Run aborted.")
            streamBuffer = ""
            isStreaming = false

        case "error":
            let errMsg = msg.payload?.error ?? "Gateway error"
            lastError = errMsg
            onError?(errMsg)

        case "chat.send":
            // Ack — status: started is normal
            if let status = msg.payload?.status, status == "error" {
                let errMsg = msg.payload?.error ?? "Send failed"
                lastError = errMsg
                onError?(errMsg)
            }

        default:
            break
        }
    }

    func startPing() {
        pingTask?.cancel()
        pingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000) // 20s
                webSocket?.sendPing { _ in }
            }
        }
    }
}

extension GatewayWSClient: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor [weak self] in
            self?.authenticating = true
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor [weak self] in
            self?.connected = false
            self?.authenticating = false
            self?.webSocket = nil
        }
    }
}

// MARK: - Config

struct GatewayWSConfig {
    var host: String
    var port: Int
    var token: String
    var sessionKey: String

    static let `default` = GatewayWSConfig.load()

    var wsURL: String { "ws://\(host):\(port)" }

    static func load() -> GatewayWSConfig {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw/openclaw.json")

        if let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let gw = json["gateway"] as? [String: Any],
           let auth = gw["auth"] as? [String: Any],
           let token = auth["token"] as? String {
            let port = gw["port"] as? Int ?? 18789
            return GatewayWSConfig(host: "127.0.0.1", port: port, token: token, sessionKey: "main")
        }

        // Fallback
        return GatewayWSConfig(host: "127.0.0.1", port: 18789, token: "", sessionKey: "main")
    }
}
