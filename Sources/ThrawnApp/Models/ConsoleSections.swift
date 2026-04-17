import Foundation
import SwiftUI

enum ConsoleSection: String, CaseIterable, Identifiable {
    case command = "Command"
    case objectives = "Objectives"
    case handoffs = "Handoffs"
    case briefings = "Briefings"
    case agents = "Agents"
    case threads = "Threads"
    case approvals = "Approvals"
    case deliverables = "Deliverables"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .command: return "message.badge.fill"
        case .objectives: return "target"
        case .handoffs: return "arrow.left.arrow.right.circle.fill"
        case .briefings: return "waveform.circle.fill"
        case .agents: return "person.3.sequence.fill"
        case .threads: return "bubble.left.and.bubble.right.fill"
        case .approvals: return "checkmark.shield.fill"
        case .deliverables: return "shippingbox.fill"
        }
    }
}

@MainActor
final class ConsoleNavigationStore: ObservableObject {
    @Published var selectedSection: ConsoleSection = .command
    /// When non-nil, the right panel shows a specialist agent chat session
    @Published var selectedAgentId: String?
    /// When true, the right panel shows the 3D memory graph
    @Published var showMemoryGraph = false
    /// Up to 2 agents pinned to the left panel quick-access slots
    @Published var pinnedLeftPanelAgents: [String] = [] {
        didSet { UserDefaults.standard.set(pinnedLeftPanelAgents, forKey: "thrawn.pinnedLeftPanelAgents") }
    }

    init() {
        pinnedLeftPanelAgents = UserDefaults.standard.stringArray(forKey: "thrawn.pinnedLeftPanelAgents")
            ?? ["thrawn", "r2d2"]
    }

    /// Dismiss the specialist chat and return to the previous section
    func dismissAgent() {
        selectedAgentId = nil
    }

    /// Dismiss the memory graph and return to the previous section
    func dismissMemoryGraph() {
        showMemoryGraph = false
    }

    /// Pin an agent to the left panel (max 2, FIFO eviction)
    func pinAgent(_ agentId: String) {
        guard !pinnedLeftPanelAgents.contains(agentId) else { return }
        if pinnedLeftPanelAgents.count >= 2 {
            pinnedLeftPanelAgents.removeFirst()
        }
        pinnedLeftPanelAgents.append(agentId)
    }

    /// Remove an agent from the left panel pinned slots
    func unpinAgent(_ agentId: String) {
        pinnedLeftPanelAgents.removeAll { $0 == agentId }
    }
}
