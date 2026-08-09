import Foundation

// MARK: - Autonomy Policy (plan §4.6)
// One policy object, consulted by the execution path — not prompt text.
// Tier defaults come from the roster design; agent-autonomy.json overrides
// per-agent domains. A domain ceiling is either "execute" or "prepare".
//
//   thrawn                lead-reviewer   — execute locally, external prepares
//   sentinel/archivist/   business-lead   — execute within product scope
//   steven
//   dwight                chief-of-staff  — prepare only, never executes
//
// Unknown agent ids get the most restrictive ceiling. The user session
// (agentId == nil) is Andrew and is never gated here.
enum AutonomyPolicy {
    private static let configPath = ThrawnPaths.appSupportDir
        .appendingPathComponent("agent-autonomy.json")

    private static let tierDefaults: [String: [String: String]] = [
        "thrawn":    ["local": "execute", "board": "execute", "files": "execute",
                      "records": "execute", "signals": "execute", "external": "prepare"],
        "sentinel":  ["local": "execute", "board": "execute", "files": "execute",
                      "records": "execute", "signals": "prepare", "external": "prepare"],
        "archivist": ["local": "execute", "board": "execute", "files": "execute",
                      "records": "execute", "signals": "prepare", "external": "prepare"],
        "steven":    ["local": "execute", "board": "execute", "files": "execute",
                      "records": "execute", "signals": "prepare", "external": "prepare"],
        "dwight":    ["local": "prepare", "board": "execute", "files": "prepare",
                      "records": "prepare", "signals": "prepare", "external": "prepare"],
    ]

    // Re-read when the file changes: a lazy static meant edits from the
    // autonomy gear sheet did not reach the execution path until relaunch.
    private static var cachedOverrides: [String: [String: String]] = [:]
    private static var cachedMTime: Date = .distantPast

    private static var overrides: [String: [String: String]] {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: configPath.path)[.modificationDate] as? Date) ?? .distantPast
        if mtime != cachedMTime {
            cachedMTime = mtime
            if let data = try? Data(contentsOf: configPath),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] {
                cachedOverrides = object
            } else {
                cachedOverrides = [:]
            }
        }
        return cachedOverrides
    }

    static func ceiling(agentID: String, domain: String) -> String {
        let slug = agentID.lowercased()
        if let value = overrides[slug]?[domain] { return value }
        if let value = tierDefaults[slug]?[domain] { return value }
        return "prepare"
    }

    /// May this agent execute shell commands at all?
    static func allowsShellExecution(agentID: String?) -> Bool {
        guard let agentID else { return true }  // user session
        return ceiling(agentID: agentID, domain: "local") == "execute"
    }

    /// Permission mode handed to provider CLIs for this agent's turns.
    /// Execute-tier agents keep their non-interactive flow; prepare-tier
    /// agents run in plan/ask mode so nothing lands without review.
    static func grokPermissionMode(agentID: String) -> String {
        allowsShellExecution(agentID: agentID) ? "dontAsk" : "plan"
    }

    static func blockMessage(agentID: String, command: String) -> String {
        "AutonomyPolicy: '\(agentID)' has a prepare-only local ceiling — shell execution is blocked. "
        + "The prepared command was recorded, not run: \(String(command.prefix(160)))"
    }
}
