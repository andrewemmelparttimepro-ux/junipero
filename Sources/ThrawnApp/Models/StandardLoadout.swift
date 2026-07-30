import Foundation

// MARK: - Standard Loadout
//
// The Standard Loadout is the console's metadata source for dev-ops squad
// defaults. Any agent whose spec sets `tools: .inherit` or `tier: .inherit`
// reads from here at resolve-time — not at copy-time.
//
// If you change the Standard Loadout, every inheriting agent follows
// immediately. Dev-ops squad is the canonical inheritor.
//
// Persisted to ~/Library/Application Support/Thrawn/standard-loadout.json
// so edits from the UI (Step 6) survive restarts. If the file is missing
// we seed with the historical dev-ops defaults.

struct StandardLoadout: Codable, Equatable {
    /// Tool IDs shown for any agent that inherits. Execution itself remains
    /// full-operation bash through ExecutionService.
    var toolIds: [String]

    /// Model tier for inheriting agents.
    var tier: ModelTier

    /// Default rank for newly-spawned agents that inherit.
    var defaultRank: AgentRank

    /// Full-operation default metadata for the dev-ops squad.
    static let devopsDefault = StandardLoadout(
        toolIds: ["bash", "file_read", "task_write"],
        tier: .premium,
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
        let data: Data
        do {
            data = try JSONEncoder().encode(loadout)
        } catch {
            FlightRecorder.logError(
                source: "loadout:save",
                message: "Encode failed: \(error.localizedDescription)"
            )
            return
        }
        do {
            try data.write(to: Self.savePath, options: .atomic)
        } catch {
            FlightRecorder.logError(
                source: "loadout:save",
                message: "Write \(Self.savePath.lastPathComponent) failed: \(error.localizedDescription)"
            )
        }
    }
}
