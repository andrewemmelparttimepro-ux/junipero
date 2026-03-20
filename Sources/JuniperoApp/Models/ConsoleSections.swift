import Foundation
import SwiftUI

enum ConsoleSection: String, CaseIterable, Identifiable {
    case command = "Command"
    case threads = "Threads"
    case tasks = "Tasks"
    case review = "Review"
    case approvals = "Approvals"
    case deliverables = "Deliverables"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .command: return "message.badge.fill"
        case .threads: return "bubble.left.and.bubble.right.fill"
        case .tasks: return "list.bullet.rectangle.portrait.fill"
        case .review: return "checklist.checked"
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

    /// Dismiss the specialist chat and return to the previous section
    func dismissAgent() {
        selectedAgentId = nil
    }
}
