import Foundation
import Combine

// Gateway WebSocket message types aligned with OpenClaw dashboard protocol
struct GatewayWSMessage: Codable {
    let type: String
    var data: [String: AnyCodable]?
}

// Thin type-erased codable wrapper
struct AnyCodable: Codable {
    let value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = i }
        else if let b = try? c.decode(Bool.self) { value = b }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let a = try? c.decode([AnyCodable].self) { value = a }
        else if let m = try? c.decode([String: AnyCodable].self) { value = m }
        else { value = NSNull() }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let s as String: try c.encode(s)
        case let i as Int: try c.encode(i)
        case let b as Bool: try c.encode(b)
        case let d as Double: try c.encode(d)
        case let a as [AnyCodable]: try c.encode(a)
        case let m as [String: AnyCodable]: try c.encode(m)
        default: try c.encodeNil()
        }
    }
}

enum GatewayConnectionState {
    case disconnected, connecting, connected, error(String)
    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

@MainActor
final class GatewayWSClient: NSObject, ObservableObject {
    @Published var connectionState: GatewayConnectionState = .disconnected
    @Published var streamingText: String = ""
    @Published var isStreaming: Bool = false
    @Published var lastError: String?

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTimer: Timer?
    private var baseURL: String = "ws://127.0.0.1:18789"
    private var token: String?
    private var currentRunId: String?

    var onMessage: ((String, String) -> Void)? // (type, text)
    var onStreamChunk: ((String) -> Void)?
    var onStreamEnd: ((String) -> Void)?

    func configure(baseURL: String, token: String?) {
        let wsBase = baseURL
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.baseURL = wsBase
        self.token = token
    }

    func connect() {
        guard !connectionState.isConnected else { return }
        connectionState = .connecting

        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        guard let url = URL(string: "\(baseURL)/ws") else {
            connectionState = .error("Invalid Gateway URL")
            return
        }

        var request = URLRequest(url: url)
        if let token = token, !token.isEmpty {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        webSocket = session?.webSocketTask(with: request)
        webSocket?.resume()
        scheduleRead()
        schedulePing()
    }

    func disconnect() {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        pingTimer?.invalidate()
        pingTimer = nil
        connectionState = .disconnected
    }

    func sendChat(message: String, idempotencyKey: String? = nil) {
        let key = idempotencyKey ?? UUID().uuidString
        let payload: [String: Any] = [
            "type": "chat.send",
            "data": [
                "text": message,
                "idempotencyKey": key
            ]
        ]
        send(payload)
    }

    func loadHistory() {
        send(["type": "chat.history", "data": [:]])
    }

    func abort() {
        send(["type": "chat.abort", "data": [:]])
    }

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        webSocket?.send(.string(str)) { _ in }
    }

    private func scheduleRead() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text): self?.handleMessage(text)
                    case .data(let data): self?.handleMessage(String(data: data, encoding: .utf8) ?? "")
                    @unknown default: break
                    }
                    self?.scheduleRead()
                case .failure(let error):
                    self?.connectionState = .error(error.localizedDescription)
                    self?.lastError = error.localizedDescription
                }
            }
        }
    }

    private func handleMessage(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type_ = json["type"] as? String else { return }

        if type_ == "connect.ok" {
            connectionState = .connected
            loadHistory()
            return
        }

        if type_.hasPrefix("chat") {
            if let msgData = json["data"] as? [String: Any] {
                if let chunk = msgData["text"] as? String, type_ == "chat" {
                    streamingText += chunk
                    isStreaming = true
                    onStreamChunk?(chunk)
                }
                if type_ == "chat.done" || type_ == "chat.end" {
                    isStreaming = false
                    onStreamEnd?(streamingText)
                    streamingText = ""
                }
            }
        }

        onMessage?(type_, raw)
    }

    private func schedulePing() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            self?.webSocket?.sendPing { _ in }
        }
    }
}

extension GatewayWSClient: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol_: String?) {
        Task { @MainActor in
            // Send connect handshake with auth token
            var connectPayload: [String: Any] = ["type": "connect"]
            if let token = self.token, !token.isEmpty {
                connectPayload["params"] = ["auth": ["token": token]]
            } else {
                connectPayload["params"] = [String: Any]()
            }
            self.send(connectPayload)
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in self.connectionState = .disconnected }
    }
}
