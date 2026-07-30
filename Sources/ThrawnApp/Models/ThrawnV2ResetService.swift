import Foundation

enum ThrawnV2ResetService {
    private static let version = 20
    private static let fm = FileManager.default

    private static var markerPath: URL {
        ThrawnPaths.appSupportDir.appendingPathComponent("v2-reset.json")
    }

    private static let preservedNames: Set<String> = [
        "setup.json",
        "preferences.json",
        "provider-state.json",
        "openai-config.json",
        ProviderRouter.glmConfigFileName,
    ]

    static func performIfNeeded() -> Bool {
        if let data = try? Data(contentsOf: markerPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let existingVersion = json["version"] as? Int,
           existingVersion >= version {
            return false
        }

        do {
            let preserved = preserveSettings()
            try clearAppSupport()
            try restoreSettings(preserved)
            try seedV2Workspace()
            FlightRecorder.logEvent(
                category: "v2-reset",
                action: "complete",
                detail: "Purged active runtime and seeded Thrawn 2.0 clean slate."
            )
            return true
        } catch {
            FlightRecorder.logError(
                source: "v2-reset",
                message: "Reset failed: \(error.localizedDescription)"
            )
            return false
        }
    }

    static func removeLegacyV1Residue() {
        let activeIds: Set<String> = ["thrawn", "archivist", "sentinel", "dwight", "steven"]

        let oldTaskBoard = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/ops/task-board.md")
        if fm.fileExists(atPath: oldTaskBoard.path) {
            try? fm.removeItem(at: oldTaskBoard)
        }

        removeUnknownAgentFiles(in: ThrawnPaths.appSupportDir.appendingPathComponent("workspace/agents"), activeIds: activeIds)
        removeUnknownHeartbeatFiles(in: ThrawnPaths.appSupportDir.appendingPathComponent("workspace/ops/heartbeats"), activeIds: activeIds)
        removeStatusFiles(in: ThrawnPaths.appSupportDir.appendingPathComponent("workspace/ops"))

        let historicalPackets = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/handoffs")
        if fm.fileExists(atPath: historicalPackets.path) {
            try? fm.removeItem(at: historicalPackets)
        }
        let historicalIndex = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/handoffs-index.json")
        if fm.fileExists(atPath: historicalIndex.path) {
            try? fm.removeItem(at: historicalIndex)
        }

        // workspace/product-sentinel, workspace/citadel, and workspace/proofs are
        // LIVE roots used by the business-agent heartbeats and the LaunchAgent proof
        // crons. They must never be purged at launch — doing so was the root cause of
        // the recurring registry/proof disappearance (TASK-013/014, 2026-07-13/18).
    }

    private static func removeUnknownAgentFiles(in dir: URL, activeIds: Set<String>) {
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for item in items {
            let name = item.deletingPathExtension().lastPathComponent.lowercased()
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if !activeIds.contains(item.lastPathComponent.lowercased()) {
                    try? fm.removeItem(at: item)
                }
            } else if !activeIds.contains(name) {
                try? fm.removeItem(at: item)
            }
        }
    }

    private static func removeUnknownHeartbeatFiles(in dir: URL, activeIds: Set<String>) {
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let expected = Set(activeIds.map { "\($0).HEARTBEAT.md" })
        for item in items where item.pathExtension == "md" && !expected.contains(item.lastPathComponent) {
            try? fm.removeItem(at: item)
        }
    }

    private static func removeStatusFiles(in dir: URL) {
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for item in items where item.lastPathComponent.hasSuffix("-status.md") {
            try? fm.removeItem(at: item)
        }
    }

    private static func preserveSettings() -> [(name: String, data: Data)] {
        preservedNames.compactMap { name in
            let url = ThrawnPaths.appSupportDir.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return (name, data)
        }
    }

    private static func clearAppSupport() throws {
        let root = ThrawnPaths.appSupportDir
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let contents = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for item in contents {
            try fm.removeItem(at: item)
        }
    }

    private static func restoreSettings(_ preserved: [(name: String, data: Data)]) throws {
        try fm.createDirectory(at: ThrawnPaths.appSupportDir, withIntermediateDirectories: true)
        for item in preserved {
            let url = ThrawnPaths.appSupportDir.appendingPathComponent(item.name)
            try item.data.write(to: url, options: .atomic)
        }
    }

    private static func seedV2Workspace() throws {
        let workspace = ThrawnPaths.appSupportDir.appendingPathComponent("workspace", isDirectory: true)
        let ops = ThrawnPaths.opsDir
        let dirs = [
            workspace,
            ops,
            ops.appendingPathComponent("heartbeats", isDirectory: true),
            ops.appendingPathComponent("agent-output", isDirectory: true),
            ops.appendingPathComponent("pending-updates", isDirectory: true),
            ops.appendingPathComponent("board-backups", isDirectory: true),
            ops.appendingPathComponent("quarantine", isDirectory: true),
            workspace.appendingPathComponent("agents", isDirectory: true),
            workspace.appendingPathComponent("agents/thrawn/knowledge", isDirectory: true),
            workspace.appendingPathComponent("logs", isDirectory: true),
            workspace.appendingPathComponent("reports", isDirectory: true),
            workspace.appendingPathComponent("deliverables", isDirectory: true),
            workspace.appendingPathComponent("memory", isDirectory: true),
            workspace.appendingPathComponent("skills", isDirectory: true),
        ]
        for dir in dirs {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        try "[]".write(
            to: ops.appendingPathComponent("agent-updates.json"),
            atomically: true,
            encoding: .utf8
        )
        try "[]".write(
            to: ThrawnPaths.appSupportDir.appendingPathComponent("workspace/objectives.json"),
            atomically: true,
            encoding: .utf8
        )
        try "{\n  \"schemaVersion\": 2,\n  \"primaryFormat\": \"html\",\n  \"deliverableRoot\": \"workspace/deliverables\",\n  \"deliverables\": []\n}\n".write(
            to: workspace.appendingPathComponent("deliverables/manifest.json"),
            atomically: true,
            encoding: .utf8
        )
        try Data().write(to: ops.appendingPathComponent("TASK_BOARD.md.lock"), options: .atomic)

        try minimalMemory.write(
            to: workspace.appendingPathComponent("memory/facts.md"),
            atomically: true,
            encoding: .utf8
        )

        let marker: [String: Any] = [
            "version": version,
            "reset_at": ISO8601DateFormatter().string(from: Date()),
            "mode": "active-stable",
        ]
        let markerData = try JSONSerialization.data(withJSONObject: marker, options: [.prettyPrinted, .sortedKeys])
        try markerData.write(to: markerPath, options: .atomic)
    }

    private static let minimalMemory = """
    # Thrawn Memory - Persistent Facts

    ## Andrew
    - Name: Andrew.
    - Timezone: America/Chicago.
    - Runs NDAI, an AI software company.
    - Wants Thrawn to be calm, strategic, direct, autonomous, and allergic to passive waiting.
    - Wants Andrew interrupted only when his taste, credential, preference, business judgment, or outside-world authority is truly required.

    ## Thrawn 2.1
    - Thrawn runs with an active stable: Dwight (Router), Samwell Tarly (SandPro OMP Lead), Sir Davos (Hit Zero Lead), and Steven (Spas 360 Lead).
    - Dwight routes inbound signals into business-owned board cards; the three business leads own one revenue stream each.
    - Steven uses the xAI Grok API route; the other active agents use the OpenClaw subscription GPT route.
    - The agent scheduler fires Thrawn heartbeats every 15 minutes and specialist heartbeats on their configured offsets.
    - Active task owners are Andrew, Thrawn, Samwell Tarly, Sir Davos, Dwight, and Steven.
    """
}
