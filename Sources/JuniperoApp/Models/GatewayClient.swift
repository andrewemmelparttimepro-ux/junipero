import Foundation

struct GatewaySessionSummary: Identifiable, Codable {
    let id: String
    let label: String
    let preview: String
    let updatedAt: Date
}

enum GatewayTransportMode: String, Codable {
    case placeholder
    case websocket
}

@MainActor
final class GatewayClient: ObservableObject {
    @Published var transportMode: GatewayTransportMode = .placeholder
    @Published var sessions: [GatewaySessionSummary] = [
        GatewaySessionSummary(id: "main", label: "Thrawn / Main", preview: "Gateway-native transport layer in progress", updatedAt: Date()),
        GatewaySessionSummary(id: "review", label: "Review Queue", preview: "Session-aware review flow to be wired", updatedAt: Date())
    ]
    @Published var connectionStatus: String = "Gateway WS migration in progress"

    func refreshPlaceholderState() {
        connectionStatus = "Gateway-native session client scaffolded; live WS migration next"
    }
}
