import Foundation
import SwiftUI

enum AgentActivityState: String, Codable {
    case idle
    case working
    case handoff
    case review
    case blocked

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .handoff: return "Handoff"
        case .review: return "Review"
        case .blocked: return "Blocked"
        }
    }

    var color: Color {
        switch self {
        case .idle:
            return Color(red: 0.45, green: 0.53, blue: 0.64)
        case .working:
            return Color(red: 0.18, green: 0.58, blue: 0.98)
        case .handoff:
            return Color(red: 0.42, green: 0.75, blue: 1.0)
        case .review:
            return Color(red: 0.76, green: 0.82, blue: 1.0)
        case .blocked:
            return Color(red: 0.95, green: 0.36, blue: 0.34)
        }
    }
}

struct AgentStatus: Identifiable, Codable {
    let id: String
    let name: String
    let role: String
    var state: AgentActivityState
    var detail: String
    var lastTransition: Date

    init(id: String, name: String, role: String, state: AgentActivityState, detail: String, lastTransition: Date = Date()) {
        self.id = id
        self.name = name
        self.role = role
        self.state = state
        self.detail = detail
        self.lastTransition = lastTransition
    }
}

@MainActor
final class AgentRosterStore: ObservableObject {
    @Published var agents: [AgentStatus] = [] {
        didSet { save() }
    }

    private static let savePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".openclaw/thrawn-agent-roster.json")

    private static let defaults: [AgentStatus] = [
        AgentStatus(id: "thrawn",  name: "Thrawn",            role: "Lead",            state: .working, detail: "Command and review active"),
        AgentStatus(id: "r2d2",   name: "R2-D2",             role: "Dev",             state: .idle,    detail: "Awaiting build brief"),
        AgentStatus(id: "c3po",   name: "C-3PO",             role: "Data",            state: .idle,    detail: "Schema and API standby"),
        AgentStatus(id: "quigon", name: "Qui-Gon",           role: "Research",        state: .handoff, detail: "Feeding next brief"),
        AgentStatus(id: "lando",  name: "Lando Calrissian",  role: "Marketing & Copy",state: .review,  detail: "Positioning in review"),
        AgentStatus(id: "boba",   name: "Boba Fett",         role: "QA & Recon",      state: .idle,    detail: "Validation queue clear")
    ]

    init() {
        load()
    }

    func setState(id: String, state: AgentActivityState, detail: String) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        agents[index].state = state
        agents[index].detail = detail
        agents[index].lastTransition = Date()
    }

    private func load() {
        if let data = try? Data(contentsOf: Self.savePath),
           let decoded = try? JSONDecoder().decode([AgentStatus].self, from: data),
           !decoded.isEmpty {
            agents = decoded
        } else {
            agents = Self.defaults
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(agents) {
            try? data.write(to: Self.savePath)
        }
    }
}
