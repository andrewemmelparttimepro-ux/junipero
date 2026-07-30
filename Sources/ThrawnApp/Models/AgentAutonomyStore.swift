import Foundation
import SwiftUI

// MARK: - Agent Autonomy (Earned Delegation)
//
// Per-agent permission ladder modeled on the Cyclops Autonomy panel:
// every capability has one of four levels — Observe, Suggest, Prepare,
// Execute — set by Andrew from the gear on an agent card. The chosen
// ceiling is persisted to agent-autonomy.json and injected into every
// heartbeat prompt, so it constrains behavior rather than just the UI.
// Some capabilities carry a hard lock (e.g. external sends cap at
// Prepare) that no slider can raise.

enum AutonomyLevel: String, Codable, CaseIterable, Comparable, Identifiable {
    case observe, suggest, prepare, execute

    var id: String { rawValue }

    var label: String { rawValue.uppercased() }

    var blurb: String {
        switch self {
        case .observe: return "Read and surface"
        case .suggest: return "Recommend a move"
        case .prepare: return "Draft for approval"
        case .execute: return "Act within guardrail"
        }
    }

    private var rank: Int {
        switch self {
        case .observe: return 0
        case .suggest: return 1
        case .prepare: return 2
        case .execute: return 3
        }
    }

    static func < (lhs: AutonomyLevel, rhs: AutonomyLevel) -> Bool { lhs.rank < rhs.rank }
}

struct AutonomyCapability: Identifiable {
    let id: String
    let title: String
    let blurb: String
    let guardrail: String
    /// Hard ceiling — the UI locks levels above this and the prompt
    /// renderer never emits more than this regardless of stored value.
    let maxLevel: AutonomyLevel
}

enum AutonomyCatalog {
    static let capabilities: [AutonomyCapability] = [
        AutonomyCapability(
            id: "signals",
            title: "Triage inbound signals",
            blurb: "Rank, label, de-duplicate, and route messages and notes into board cards.",
            guardrail: "May organize and prioritize. Never deletes, archives, replies, or changes source material.",
            maxLevel: .execute
        ),
        AutonomyCapability(
            id: "board",
            title: "Work the task board",
            blurb: "Create, move, annotate, and close cards through the update-file pipeline.",
            guardrail: "Nothing reaches Done without review. Sourceless cards get bounced.",
            maxLevel: .execute
        ),
        AutonomyCapability(
            id: "local",
            title: "Run diagnostics & proofs",
            blurb: "Product Sentinel patrols, builds, tests, and local commands with receipts.",
            guardrail: "Proof runs are immutable. No product code mutation without a card and review.",
            maxLevel: .execute
        ),
        AutonomyCapability(
            id: "files",
            title: "Write workspace files & deliverables",
            blurb: "Reports, citadel pages, HTML deliverables, and knowledge notes.",
            guardrail: "Workspace only. Never publishes or deploys outside the machine.",
            maxLevel: .execute
        ),
        AutonomyCapability(
            id: "external",
            title: "Draft external communications",
            blurb: "Client replies, posts, and outreach prepared from approved business context.",
            guardrail: "Sending anything external always requires Andrew. Execute is hard-locked.",
            maxLevel: .prepare
        ),
        AutonomyCapability(
            id: "records",
            title: "Update business records",
            blurb: "Objectives, durable memory, contacts, and operating records.",
            guardrail: "No deletion, ownership transfer, or bulk rewrite without explicit human approval.",
            maxLevel: .execute
        ),
    ]

    static func capability(_ id: String) -> AutonomyCapability? {
        capabilities.first { $0.id == id }
    }

    /// Role-appropriate defaults, used until Andrew adjusts a ladder.
    static func defaults(forAgentId id: String) -> [String: AutonomyLevel] {
        switch id {
        case "thrawn":
            return ["signals": .execute, "board": .execute, "local": .execute,
                    "files": .execute, "external": .prepare, "records": .execute]
        case "dwight":
            // Router: signals + board are the whole job; everything else observes.
            return ["signals": .execute, "board": .execute, "local": .observe,
                    "files": .suggest, "external": .observe, "records": .observe]
        default:
            // Business leads.
            return ["signals": .suggest, "board": .execute, "local": .execute,
                    "files": .execute, "external": .prepare, "records": .execute]
        }
    }
}

// MARK: - Store

@MainActor
final class AgentAutonomyStore: ObservableObject {
    /// agentId → capabilityId → level
    @Published private(set) var ladders: [String: [String: AutonomyLevel]] = [:]

    nonisolated private static var fileURL: URL {
        ThrawnPaths.appSupportDir.appendingPathComponent("agent-autonomy.json")
    }

    init() {
        ladders = Self.loadFromDisk()
    }

    func level(agentId: String, capability: String) -> AutonomyLevel {
        let stored = ladders[agentId]?[capability]
            ?? AutonomyCatalog.defaults(forAgentId: agentId)[capability]
            ?? .observe
        let ceiling = AutonomyCatalog.capability(capability)?.maxLevel ?? .execute
        return min(stored, ceiling)
    }

    func setLevel(agentId: String, capability: String, level: AutonomyLevel) {
        let ceiling = AutonomyCatalog.capability(capability)?.maxLevel ?? .execute
        var agentLadder = ladders[agentId] ?? AutonomyCatalog.defaults(forAgentId: agentId)
        agentLadder[capability] = min(level, ceiling)
        ladders[agentId] = agentLadder
        save()
        FlightRecorder.logEvent(
            category: "autonomy",
            action: "set-level",
            detail: "\(agentId).\(capability) → \(min(level, ceiling).rawValue)"
        )
    }

    private func save() {
        let raw = ladders.mapValues { $0.mapValues(\.rawValue) }
        guard let data = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    nonisolated private static func loadFromDisk() -> [String: [String: AutonomyLevel]] {
        guard let data = try? Data(contentsOf: fileURL),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else { return [:] }
        return raw.mapValues { $0.compactMapValues(AutonomyLevel.init(rawValue:)) }
    }

    /// Disk-backed ceiling lookup for callers that can't hold the store —
    /// the voice tool layer gates every action through this.
    nonisolated static func effectiveLevel(agentId: String, capability: String) -> AutonomyLevel {
        let stored = loadFromDisk()[agentId]?[capability]
            ?? AutonomyCatalog.defaults(forAgentId: agentId)[capability]
            ?? .observe
        let ceiling = AutonomyCatalog.capability(capability)?.maxLevel ?? .execute
        return min(stored, ceiling)
    }

    // MARK: - Prompt injection (read-side, safe off the main actor)

    /// Renders the autonomy ceiling block for an agent's heartbeat prompt.
    /// Reads straight from disk so the scheduler needs no store binding.
    nonisolated static func promptBlock(forAgentId id: String) -> String {
        let stored = loadFromDisk()[id] ?? [:]
        let defaults = AutonomyCatalog.defaults(forAgentId: id)
        var lines: [String] = []
        lines.append("## Autonomy Ceiling — set by Andrew, hard limits for this wake")
        lines.append("")
        lines.append("Levels: OBSERVE = read & report only. SUGGEST = recommend in notes/cards only. PREPARE = draft or stage for approval, never act. EXECUTE = act within the guardrail.")
        lines.append("")
        for cap in AutonomyCatalog.capabilities {
            let level = min(stored[cap.id] ?? defaults[cap.id] ?? .observe, cap.maxLevel)
            lines.append("- \(cap.title): **\(level.label)** — guardrail: \(cap.guardrail)")
        }
        lines.append("")
        lines.append("An action above your ceiling for its capability is forbidden this wake: instead stage what you can at your level and hand the card to Thrawn (or flag Andrew via a Blocked card) per the ladder. Every action is audited.")
        return lines.joined(separator: "\n")
    }
}
