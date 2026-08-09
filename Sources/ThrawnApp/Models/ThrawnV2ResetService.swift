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
        // Conversation data survives every migration. Losing chat history to
        // a version bump is never acceptable.
        "threads.json",
        "drafts.json",
        "brain.json",
    ]

    static func performIfNeeded() -> Bool {
        if let data = try? Data(contentsOf: markerPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let existingVersion = json["version"] as? Int,
           existingVersion >= version {
            return false
        }

        do {
            // A version-bump migration never destroys state it did not copy
            // first. The full App Support tree is archived before anything
            // is cleared — recovery from a bad migration is a directory move.
            let archiveRoot = try archiveAppSupport(reason: "v2-reset-v\(version)")
            let preserved = preserveSettings()
            try clearAppSupport()
            try restoreSettings(preserved)
            try seedV2Workspace()
            FlightRecorder.logEvent(
                category: "v2-reset",
                action: "complete",
                detail: "Migrated to v\(version); prior state archived at \(archiveRoot.path)"
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
        // README.md documents the sentinel/archivist alias mapping — the file
        // whose absence caused the TASK-219 false alarm. It is load-bearing.
        let activeIds: Set<String> = ["thrawn", "archivist", "sentinel", "dwight", "steven", "readme"]

        let oldTaskBoard = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/ops/task-board.md")
        if fm.fileExists(atPath: oldTaskBoard.path) {
            try? fm.removeItem(at: oldTaskBoard)
        }

        removeUnknownAgentFiles(in: ThrawnPaths.appSupportDir.appendingPathComponent("workspace/agents"), activeIds: activeIds)
        removeUnknownHeartbeatFiles(in: ThrawnPaths.appSupportDir.appendingPathComponent("workspace/ops/heartbeats"), activeIds: activeIds)
        removeStatusFiles(in: ThrawnPaths.appSupportDir.appendingPathComponent("workspace/ops"))

        let historicalPackets = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/handoffs")
        if fm.fileExists(atPath: historicalPackets.path),
           let contents = try? fm.contentsOfDirectory(atPath: historicalPackets.path),
           !contents.isEmpty {
            quarantine(historicalPackets)
        }
        let historicalIndex = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/handoffs-index.json")
        if fm.fileExists(atPath: historicalIndex.path) {
            quarantine(historicalIndex)
        }

        // workspace/product-sentinel, workspace/citadel, and workspace/proofs are
        // LIVE roots used by the business-agent heartbeats and the LaunchAgent proof
        // crons. They must never be purged at launch — doing so was the root cause of
        // the recurring registry/proof disappearance (TASK-013/014, 2026-07-13/18).
    }

    /// Launch-time cleanup quarantines instead of deleting. A file this code
    /// judges "unknown" has been a live agent contract before (the Aug 2026
    /// davos.md/samwell.md incident) — deletion at launch leaves no recovery
    /// path and no provable author. Quarantined files land under
    /// Thrawn Archives/launch-quarantine-<date>/.
    private static func quarantine(_ item: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let dir = ThrawnPaths.appSupportDir
            .deletingLastPathComponent()
            .appendingPathComponent("Thrawn Archives/launch-quarantine-\(stamp)", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent(item.lastPathComponent)
        try? fm.removeItem(at: destination)
        do {
            try fm.moveItem(at: item, to: destination)
            FlightRecorder.logEvent(
                category: "v2-reset",
                action: "quarantine",
                detail: "Moved \(item.lastPathComponent) to \(destination.path)"
            )
        } catch {
            FlightRecorder.logError(
                source: "v2-reset",
                message: "Quarantine failed for \(item.path): \(error.localizedDescription)"
            )
        }
    }

    private static func archiveAppSupport(reason: String) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let destination = ThrawnPaths.appSupportDir
            .deletingLastPathComponent()
            .appendingPathComponent("Thrawn Archives/\(reason)-\(stamp)", isDirectory: true)
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fm.copyItem(at: ThrawnPaths.appSupportDir, to: destination)
        return destination
    }

    private static func removeUnknownAgentFiles(in dir: URL, activeIds: Set<String>) {
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for item in items {
            let name = item.deletingPathExtension().lastPathComponent.lowercased()
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if !activeIds.contains(item.lastPathComponent.lowercased()) {
                    quarantine(item)
                }
            } else if !activeIds.contains(name) {
                quarantine(item)
            }
        }
    }

    private static func removeUnknownHeartbeatFiles(in dir: URL, activeIds: Set<String>) {
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let expected = Set(activeIds.map { "\($0).HEARTBEAT.md" })
        for item in items where item.pathExtension == "md" && !expected.contains(item.lastPathComponent) {
            quarantine(item)
        }
    }

    private static func removeStatusFiles(in dir: URL) {
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for item in items where item.lastPathComponent.hasSuffix("-status.md") {
            quarantine(item)
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
