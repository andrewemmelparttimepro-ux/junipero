import Foundation

// MARK: - Standard Loadout
//
// The Standard Loadout is the single source of truth for the dev-ops
// squad's defaults. Any agent whose spec sets `tools: .inherit` or
// `tier: .inherit` reads from here at resolve-time — not at copy-time.
//
// If you change the Standard Loadout, every inheriting agent follows
// immediately. Dev-ops squad is the canonical inheritor.
//
// Persisted to ~/Library/Application Support/Thrawn/standard-loadout.json
// so edits from the UI (Step 6) survive restarts. If the file is missing
// we seed with the historical dev-ops defaults.

struct StandardLoadout: Codable, Equatable {
    /// Tool IDs available to any agent that inherits. Must match IDs in
    /// ToolRegistry (bash, file_read, task_write, memory_read, memory_write).
    var toolIds: [String]

    /// Model tier for inheriting agents.
    var tier: ModelTier

    /// Default rank for newly-spawned agents that inherit.
    var defaultRank: AgentRank

    /// The historical dev-ops default — exactly what pre-Step-2 code used.
    /// Bash is a wildcard, so behavior is identical until the loadout is
    /// intentionally narrowed.
    static let devopsDefault = StandardLoadout(
        toolIds: ["bash", "file_read", "task_write"],
        tier: .local,
        defaultRank: .b
    )
}

@MainActor
final class StandardLoadoutStore: ObservableObject {
    @Published var loadout: StandardLoadout {
        didSet { save() }
    }

    private static let savePath = ThrawnPaths.appSupportDir
        .appendingPathComponent("standard-loadout.json")

    init() {
        if let data = try? Data(contentsOf: Self.savePath),
           let decoded = try? JSONDecoder().decode(StandardLoadout.self, from: data) {
            self.loadout = decoded
        } else {
            self.loadout = .devopsDefault
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(loadout) else { return }
        try? data.write(to: Self.savePath)
    }
}
