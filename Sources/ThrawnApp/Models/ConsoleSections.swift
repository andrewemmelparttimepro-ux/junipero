import Foundation
import SwiftUI

enum ConsoleSection: String, CaseIterable, Identifiable {
    case command = "Command"
    case objectives = "Objectives"
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
    /// The project board occupying the primary console surface. Setting this
    /// to nil reveals the selected utility section from the collapsible rail.
    @Published var selectedProjectBoard: ProductBoardID? = .spas360
    /// When true, the currently-selected project board takes over the entire
    /// window as a full-screen freeform canvas. Toggled by the logo buttons
    /// in ProductBoardSwitcher and the oversized X exit in the overlay.
    @Published var showBoardFullScreen: Bool = false
    /// When non-nil, the right panel shows a specialist agent chat session
    @Published var selectedAgentId: String?
    /// When true, the right panel shows the 3D memory graph
    @Published var showMemoryGraph = false
    /// When true, the right panel shows The Citadel operating memory
    @Published var showCitadel = false
    /// Up to 2 agents pinned to the left panel quick-access slots
    @Published var pinnedLeftPanelAgents: [String] = [] {
        didSet { UserDefaults.standard.set(pinnedLeftPanelAgents, forKey: "thrawn.pinnedLeftPanelAgents") }
    }

    init() {
        pinnedLeftPanelAgents = UserDefaults.standard.stringArray(forKey: "thrawn.pinnedLeftPanelAgents")
            ?? ["thrawn"]
        pinnedLeftPanelAgents = pinnedLeftPanelAgents.filter { $0 == "thrawn" }
    }

    /// Dismiss the specialist chat and return to the previous section
    func dismissAgent() {
        selectedAgentId = nil
    }

    /// Dismiss the memory graph and return to the previous section
    func dismissMemoryGraph() {
        showMemoryGraph = false
    }

    /// Dismiss The Citadel and return to the previous section
    func dismissCitadel() {
        showCitadel = false
    }

    /// Dismiss full-panel overlays when navigating between primary sections
    func dismissOverlays() {
        showCitadel = false
        showMemoryGraph = false
    }

    /// Open one of the persistent product canvases.
    func selectProjectBoard(_ board: ProductBoardID) {
        selectedProjectBoard = board
        selectedAgentId = nil
        dismissOverlays()
    }

    /// Open a utility section from the right-side rail.
    func selectSection(_ section: ConsoleSection) {
        selectedProjectBoard = nil
        showBoardFullScreen = false
        selectedSection = section
        selectedAgentId = nil
        dismissOverlays()
    }

    /// Close the full-screen product board overlay and return to the
    /// normal split-panel view.
    func closeBoardFullScreen() {
        showBoardFullScreen = false
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
