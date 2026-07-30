import Foundation

/// Centralised path resolution for Thrawn Console.
///
/// The operational "guts" (heartbeats, agent definitions, dispatcher scripts,
/// control docs) are version-controlled inside the app's `OpsBundle/` directory.
/// On every launch, `deployOpsBundle()` syncs config files to the app's data
/// directory where agents read/write at runtime.
///
/// **App Store path**: `~/Library/Application Support/Thrawn/`
/// In sandbox mode, this resolves inside the container automatically.
///
/// Runtime state (logs, agent-output, dispatch-log) is never overwritten —
/// only structural/config files are deployed.
enum ThrawnPaths {
    private static let fm = FileManager.default
    private static let home = fm.homeDirectoryForCurrentUser

    /// Primary data directory — App Store compatible.
    /// Uses ~/Library/Application Support/Thrawn/ (auto-sandboxed when needed).
    /// Falls back to ~/.openclaw/ for backward compatibility during migration.
    static let appSupportDir: URL = {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Thrawn", isDirectory: true)
        try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }()

    /// The root data directory (NDAI for development, app support for production).
    static let dataRoot: URL = {
        let candidates = [
            home.appendingPathComponent("Desktop/NDAI"),
            URL(fileURLWithPath: "/Volumes/brain/NDAI"),
        ]
        for candidate in candidates where fm.fileExists(atPath: candidate.path) {
            return candidate
        }
        let fallback = appSupportDir.appendingPathComponent("workspace")
        try? fm.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }()

    /// The ops directory — where agents write and the dispatcher updates TASK_BOARD.md.
    /// Uses app support path, with migration from legacy .openclaw path.
    static let opsDir: URL = {
        let primary = appSupportDir.appendingPathComponent("workspace/ops")
        let legacy = home.appendingPathComponent(".openclaw/workspace/ops")

        // If legacy path has data and primary is empty, migrate
        if fm.fileExists(atPath: legacy.path) && !fm.fileExists(atPath: primary.path) {
            try? fm.createDirectory(at: primary.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: legacy, to: primary)
        }

        try? fm.createDirectory(at: primary, withIntermediateDirectories: true)
        return primary
    }()

    /// Convenience: path to a named file inside opsDir.
    static func opsFile(_ name: String) -> String {
        opsDir.appendingPathComponent(name).path
    }

    // MARK: - OpsBundle Deployment

    /// The OpsBundle directory inside the source tree / app bundle.
    /// At dev time this resolves to the source tree; in a release build it
    /// would be inside the .app bundle's Resources.
    private static let opsBundleDir: URL? = {
        // First check the app bundle (release builds)
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("OpsBundle"),
           fm.fileExists(atPath: bundled.path) {
            return bundled
        }
        // Dev time: walk up from the executable to find the source tree
        let execURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()

        // Walk up to 8 parent directories looking for an OpsBundle sibling
        var cursor = execURL
        for _ in 0..<8 {
            let candidate = cursor.appendingPathComponent("OpsBundle").standardized
            if fm.fileExists(atPath: candidate.path) { return candidate }
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path { break }
            cursor = parent
        }

        // Known source-tree locations
        let candidates = [
            home.appendingPathComponent("Documents/thrawn-console/OpsBundle"),
            home.appendingPathComponent("Desktop/thrawn-console/OpsBundle"),
            home.appendingPathComponent("Desktop/NDAI/09-Projects/Active/Thrawn-Console/thrawn-console-src/OpsBundle"),
        ]
        for c in candidates {
            let resolved = c.standardized
            if fm.fileExists(atPath: resolved.path) { return resolved }
        }
        return nil
    }()

    /// Deploy config/code files from OpsBundle → app support at launch.
    /// Only copies files that are newer than the destination (or missing).
    /// Never overwrites runtime state files (logs, agent-output, etc.).
    static func deployOpsBundle() {
        guard let bundle = opsBundleDir else { return }

        // Mapping: OpsBundle subdir → destination under app support
        let deployments: [(src: String, dst: String, replaceIfDifferent: Bool)] = [
            ("ops/heartbeats",   "workspace/ops/heartbeats", false),
            ("ops",              "workspace/ops", false),       // control docs (TASK_BOARD, OPERATING_AUTHORITY, etc.)
            ("agents",           "workspace/agents", false),
            ("bin",              "bin", true),
            ("workspace-meta",   "workspace", false),           // USER.md, SOUL.md, etc. → workspace root
        ]

        for mapping in deployments {
            let srcDir = bundle.appendingPathComponent(mapping.src)
            let dstDir = appSupportDir.appendingPathComponent(mapping.dst)
            try? fm.createDirectory(at: dstDir, withIntermediateDirectories: true)

            guard let files = try? fm.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for file in files where !file.hasDirectoryPath {
                let name = file.lastPathComponent
                let dest = dstDir.appendingPathComponent(name)
                if name == "TASK_BOARD.md", fm.fileExists(atPath: dest.path) {
                    continue
                }
                if isRuntimeState(name) { continue }
                deployIfNewer(from: file, to: dest, replaceIfDifferent: mapping.replaceIfDifferent)
            }
        }

        let obsoleteFiles = [
            "workspace/ops/APPROVAL_BOUNDARIES.md",
        ]
        for path in obsoleteFiles {
            let url = appSupportDir.appendingPathComponent(path)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }

        // Roster JSON → app support root
        let rosterSrc = bundle.appendingPathComponent("thrawn-agent-roster.json")
        let rosterDst = appSupportDir.appendingPathComponent("thrawn-agent-roster.json")
        if !fm.fileExists(atPath: rosterDst.path) {
            try? fm.copyItem(at: rosterSrc, to: rosterDst)
        }
    }

    /// Files that are runtime state — never overwrite from the bundle.
    private static func isRuntimeState(_ filename: String) -> Bool {
        let runtimeFiles: Set<String> = [
            "dispatcher.log", "dispatch-log.jsonl", "dispatch-cron.log",
            "REVIEW_QUEUE.md", "task_activity.json", "agent-updates.json",
            "review-log.json",
        ]
        // agent-output JSON and data-notes are also runtime
        if filename.hasSuffix(".json") && !filename.contains("HEARTBEAT") && !filename.contains("APPROVAL") {
            // Be conservative — only deploy .md config files from ops/
            // JSON in ops/ is typically runtime state
            return runtimeFiles.contains(filename)
        }
        return runtimeFiles.contains(filename)
    }

    /// Copy src → dst only if src is newer or dst doesn't exist.
    private static func deployIfNewer(from src: URL, to dst: URL, replaceIfDifferent: Bool = false) {
        if fm.fileExists(atPath: dst.path) {
            if replaceIfDifferent,
               let srcData = try? Data(contentsOf: src),
               let dstData = try? Data(contentsOf: dst),
               srcData != dstData {
                try? fm.removeItem(at: dst)
                try? fm.copyItem(at: src, to: dst)
                return
            }
            let srcAttrs = try? fm.attributesOfItem(atPath: src.path)
            let dstAttrs = try? fm.attributesOfItem(atPath: dst.path)
            let srcMod = srcAttrs?[.modificationDate] as? Date ?? .distantPast
            let dstMod = dstAttrs?[.modificationDate] as? Date ?? .distantPast
            guard srcMod > dstMod else { return }
            try? fm.removeItem(at: dst)
        }
        try? fm.copyItem(at: src, to: dst)
    }

    // MARK: - Startup Integrity Check
    //
    // Reliability rule: fail loudly at startup, not silently three hours later
    // when an agent tries to write a file. Verifies every directory the
    // scheduler / dispatcher / FlightRecorder needs to function. Each one is
    // tested by attempting to create it AND write a tiny probe file — that
    // catches sandbox permission issues that bare createDirectory misses.

    struct OpsIntegrityReport {
        let allGood: Bool
        let missingDirs: [URL]
        let unwritableDirs: [URL]
        let totalChecked: Int

        /// Plain-English summary suitable for logs / UI banner.
        var summary: String {
            if allGood { return "All \(totalChecked) ops directories OK." }
            var parts: [String] = []
            if !missingDirs.isEmpty {
                parts.append("\(missingDirs.count) missing")
            }
            if !unwritableDirs.isEmpty {
                parts.append("\(unwritableDirs.count) unwritable")
            }
            return "Ops integrity: \(parts.joined(separator: ", ")) of \(totalChecked) dirs."
        }

        var problematicPaths: [String] {
            (missingDirs + unwritableDirs).map { $0.path }
        }
    }

    /// Every directory the runtime relies on. Tested at startup.
    private static var requiredOpsDirectories: [URL] {
        [
            appSupportDir,
            appSupportDir.appendingPathComponent("workspace"),
            appSupportDir.appendingPathComponent("workspace/ops"),
            appSupportDir.appendingPathComponent("workspace/ops/heartbeats"),
            appSupportDir.appendingPathComponent("workspace/ops/agent-output"),
            appSupportDir.appendingPathComponent("workspace/ops/pending-updates"),
            appSupportDir.appendingPathComponent("workspace/ops/board-backups"),
            appSupportDir.appendingPathComponent("workspace/ops/quarantine"),
            appSupportDir.appendingPathComponent("workspace/agents"),
            appSupportDir.appendingPathComponent("workspace/handoffs"),
            appSupportDir.appendingPathComponent("workspace/logs"),
            appSupportDir.appendingPathComponent("workspace/reports"),
            appSupportDir.appendingPathComponent("workspace/deliverables"),
        ]
    }

    /// Verify all ops directories exist AND are writable. Call this once at
    /// app launch before starting the scheduler / dispatcher. Logs every
    /// failure via FlightRecorder so the operator sees them in diagnostics.
    @discardableResult
    static func verifyOpsDirectories() -> OpsIntegrityReport {
        var missing: [URL] = []
        var unwritable: [URL] = []

        for dir in requiredOpsDirectories {
            // Step 1: ensure it exists
            if !fm.fileExists(atPath: dir.path) {
                do {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                } catch {
                    FlightRecorder.logError(
                        source: "integrity:create",
                        message: "Could not create \(dir.path): \(error.localizedDescription)"
                    )
                    missing.append(dir)
                    continue
                }
            }

            // Step 2: writability probe — a tiny file that gets cleaned up.
            // This catches sandbox permission denials that createDirectory
                // can succeed past (the dir exists but writes fail).
            let probe = dir.appendingPathComponent(".thrawn-write-probe")
            do {
                try Data("ok".utf8).write(to: probe, options: .atomic)
                try fm.removeItem(at: probe)
            } catch {
                FlightRecorder.logError(
                    source: "integrity:writable",
                    message: "Probe write failed in \(dir.path): \(error.localizedDescription)"
                )
                unwritable.append(dir)
            }
        }

        let allGood = missing.isEmpty && unwritable.isEmpty
        let report = OpsIntegrityReport(
            allGood: allGood,
            missingDirs: missing,
            unwritableDirs: unwritable,
            totalChecked: requiredOpsDirectories.count
        )

        if allGood {
            FlightRecorder.logEvent(
                category: "integrity", action: "startup-ok",
                detail: report.summary
            )
        } else {
            FlightRecorder.logError(
                source: "integrity:startup",
                message: "STARTUP INTEGRITY FAILED — \(report.summary). Bad paths: \(report.problematicPaths.joined(separator: ", "))"
            )
        }

        return report
    }
}
