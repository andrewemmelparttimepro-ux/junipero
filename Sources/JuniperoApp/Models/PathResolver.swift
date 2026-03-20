import Foundation

/// Centralised path resolution for Thrawn Console.
/// The ops directory (TASK_BOARD.md, agent-updates.json, etc.) always lives at
/// `~/.openclaw/workspace/ops/` — the single source of truth that both the console
/// and OpenClaw agents read/write. The NDAI tree is used for non-ops data only.
enum ThrawnPaths {
    private static let fm = FileManager.default
    private static let home = fm.homeDirectoryForCurrentUser

    /// The root data directory (NDAI or workspace fallback).
    static let dataRoot: URL = {
        let candidates = [
            home.appendingPathComponent("Desktop/NDAI"),
            URL(fileURLWithPath: "/Volumes/brain/NDAI"),
        ]
        for candidate in candidates where fm.fileExists(atPath: candidate.path) {
            return candidate
        }
        let fallback = home.appendingPathComponent(".openclaw/workspace")
        try? fm.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }()

    /// The ops directory — ALWAYS ~/.openclaw/workspace/ops/.
    /// This is where agents write and the dispatcher updates TASK_BOARD.md.
    /// Never use the NDAI ops path — that creates a split-brain.
    static let opsDir: URL = {
        let workspaceOps = home.appendingPathComponent(".openclaw/workspace/ops")
        try? fm.createDirectory(at: workspaceOps, withIntermediateDirectories: true)
        return workspaceOps
    }()

    /// Convenience: path to a named file inside opsDir.
    static func opsFile(_ name: String) -> String {
        opsDir.appendingPathComponent(name).path
    }
}
