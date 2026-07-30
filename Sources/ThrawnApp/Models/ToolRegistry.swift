import Foundation

// MARK: - Tool Registry
//
// Every capability an agent can invoke is modeled as a Tool for UI metadata
// and prompt vocabulary. Runtime execution is full-operation: bash fences
// route directly through ExecutionService for every agent.
//
// For v1, all tool invocations flow through bash code fences — the agent
// outputs ```bash blocks and ExecutionService runs them.
//
// Built-in tools:
//   • bash        — wildcard shell access (dev-ops squad tier)
//   • file_read   — read-only file operations (cat/head/tail/ls/grep/find/...)
//   • task_write  — write to pending-updates/updates-{agent}.json
//   • memory_read — read from workspace/agents/{agent}/knowledge/
//   • memory_write— append to workspace/agents/{agent}/knowledge/
//
// Per-agent tool lists still render in the console as organizational metadata,
// but they are no longer a scheduler gate.

struct Tool {
    let id: String
    let description: String
    /// Return true if this bash command belongs to this tool.
    let matches: (String) -> Bool
}

enum ToolRegistry {

    // MARK: - Built-in Tools

    static let bash = Tool(
        id: "bash",
        description: "Full shell access. Any command wrapped in a ```bash fence executes directly.",
        matches: { _ in true }  // wildcard — if an agent has this, anything goes
    )

    static let fileRead = Tool(
        id: "file_read",
        description: "Read-only file operations: cat, head, tail, less, ls, find, grep, wc, stat, file. Cannot write, delete, or execute.",
        matches: { cmd in
            let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
            let first = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
            let readOnlyTools: Set<String> = [
                "cat", "head", "tail", "less", "more",
                "ls", "find", "grep", "rg", "fgrep", "egrep",
                "wc", "stat", "file", "du", "tree",
                "pwd", "echo", "which", "whoami", "date"
            ]
            guard readOnlyTools.contains(first) else { return false }
            // Deny redirects and command chaining that could produce writes
            let dangerous = [">", ">>", "|", "&&", "||", ";", "`", "$("]
            for token in dangerous {
                if cmd.contains(token) { return false }
            }
            return true
        }
    )

    static let taskWrite = Tool(
        id: "task_write",
        description: "Write your task-board update JSON to pending-updates/updates-{agent}.json. The dispatcher reads these every 30s and applies changes.",
        matches: { cmd in
            // Match writes that target the agent's pending-updates file
            cmd.contains("pending-updates/updates-") &&
            (cmd.contains(">") || cmd.contains("tee") || cmd.hasPrefix("echo "))
        }
    )

    static let memoryRead = Tool(
        id: "memory_read",
        description: "Read your personal knowledge files at workspace/agents/{agent}/knowledge/. Read-only.",
        matches: { cmd in
            guard cmd.contains("workspace/agents/") && cmd.contains("/knowledge/") else { return false }
            let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
            let first = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
            return ["cat", "head", "tail", "less", "ls", "grep", "find"].contains(first)
        }
    )

    static let memoryWrite = Tool(
        id: "memory_write",
        description: "Append to your personal knowledge files at workspace/agents/{agent}/knowledge/. Use >> or tee -a — never overwrite.",
        matches: { cmd in
            guard cmd.contains("workspace/agents/") && cmd.contains("/knowledge/") else { return false }
            // Must be append-only
            return cmd.contains(">>") || cmd.contains("tee -a")
        }
    )

    static let logRead = Tool(
        id: "log_read",
        description: "Read-only access to Thrawn runtime logs under workspace/logs/.",
        matches: { cmd in
            guard cmd.contains("workspace/logs/") else { return false }
            return readOnlyCommand(cmd)
        }
    )

    static let proofRead = Tool(
        id: "proof_read",
        description: "Read immutable proof bundles under workspace/proofs/.",
        matches: { cmd in
            guard cmd.contains("workspace/proofs/") else { return false }
            return readOnlyCommand(cmd)
        }
    )

    static let proofWrite = Tool(
        id: "proof_write",
        description: "Write new proof metadata under workspace/proofs/. Do not edit older proof runs.",
        matches: { cmd in
            guard cmd.contains("workspace/proofs/") else { return false }
            return appendOrCreateCommand(cmd)
        }
    )

    static let wikiRead = Tool(
        id: "wiki_read",
        description: "Read local knowledge pages under workspace/citadel/.",
        matches: { cmd in
            guard citadelCommand(cmd) else { return false }
            return readOnlyCommand(cmd)
        }
    )

    static let wikiWrite = Tool(
        id: "wiki_write",
        description: "Update local knowledge pages under workspace/citadel/.",
        matches: { cmd in
            guard citadelCommand(cmd) else { return false }
            return appendOrCreateCommand(cmd)
        }
    )

    static let summaryWrite = Tool(
        id: "summary_write",
        description: "Write synthesized summaries for product proofs and rolling 72-hour context.",
        matches: { cmd in
            guard citadelCommand(cmd) || cmd.contains("workspace/proofs/") else { return false }
            return appendOrCreateCommand(cmd)
        }
    )

    static let deliverableWrite = Tool(
        id: "deliverable_write",
        description: "Publish human-readable HTML deliverables under workspace/deliverables/ and register them in manifest.json.",
        matches: { cmd in
            guard cmd.contains("workspace/deliverables/") || cmd.contains("deliverable-publish.py") else { return false }
            return appendOrCreateCommand(cmd)
        }
    )

    static let browserUser = Tool(
        id: "browser_user",
        description: "Use Andrew's existing signed-in Chrome for authenticated sites via `openclaw browser --browser-profile user ...`. Never substitute the isolated OpenClaw profile when login state matters.",
        matches: { cmd in
            cmd.contains("openclaw browser") && cmd.contains("--browser-profile user")
        }
    )

    static let webSearch = Tool(
        id: "web_search",
        description: "Search the web via curl + search APIs / site-specific queries. Google dorking, LinkedIn public search, Reddit search, GitHub user/org search. Build search URLs and fetch results.",
        matches: { cmd in
            let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
            let first = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
            return first == "curl" && (
                cmd.contains("google.com/search") ||
                cmd.contains("duckduckgo.com") ||
                cmd.contains("api.github.com") ||
                cmd.contains("reddit.com/search") ||
                cmd.contains("old.reddit.com") ||
                cmd.contains("linkedin.com") ||
                cmd.contains("search?") ||
                cmd.contains("site:") ||
                cmd.contains("hn.algolia.com")
            )
        }
    )

    static let webScrape = Tool(
        id: "web_scrape",
        description: "Fetch and extract data from public web pages. About pages, team pages, profiles, job listings, conference speaker lists. Uses curl + text processing (grep, sed, awk, python). No login-walled content.",
        matches: { cmd in
            let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
            let first = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
            // Allow curl for general web fetching
            if first == "curl" { return true }
            // Allow python/python3 for scraping scripts
            if first == "python3" || first == "python" { return true }
            // Allow wget for page downloads
            if first == "wget" { return true }
            return false
        }
    )

    // MARK: - Catalog

    static let all: [Tool] = [
        bash,
        fileRead,
        taskWrite,
        memoryRead,
        memoryWrite,
        logRead,
        proofRead,
        proofWrite,
        wikiRead,
        wikiWrite,
        summaryWrite,
        deliverableWrite,
        browserUser,
        webSearch,
        webScrape
    ]

    static func tool(id: String) -> Tool? {
        all.first(where: { $0.id == id })
    }

    // MARK: - Default Loadouts & Resolver
    //
    // Step 2: tool lists are resolved from AgentSpecStore with inheritance
    // from the StandardLoadout. If no spec store is wired (early startup,
    // unit tests), we fall back to the historical dev-ops default so
    // behavior is unchanged.

    /// Historical dev-ops default. Matches `StandardLoadout.devopsDefault`.
    /// Used only as a fallback when no spec store has been injected.
    static let devopsDefault: [String] = ["bash", "file_read", "task_write"]

    /// Injected at app startup by ThrawnApp so the scheduler's static
    /// authorize path can resolve tools through the spec store.
    /// MainActor-isolated because the store is @MainActor.
    @MainActor static var specStore: AgentSpecStore?

    /// Return the allowed tool IDs for a given agent.
    /// Resolves through the spec store if available; otherwise falls back
    /// to the dev-ops default to preserve pre-Step-2 behavior.
    @MainActor
    static func allowedTools(forAgentId id: String) -> [String] {
        var resolved: [String]
        if let store = specStore {
            resolved = store.resolvedTools(forAgentId: id)
        } else {
            resolved = devopsDefault
        }
        if !resolved.contains("bash") {
            resolved.insert("bash", at: 0)
        }
        return resolved
    }

    // MARK: - Execution Classification

    /// Classify a command for logging. Execution is full-operation, so an
    /// unknown command still runs as `bash`.
    static func authorize(command: String, allowedToolIds: [String]) -> String? {
        for toolId in allowedToolIds where toolId != "bash" {
            guard let tool = tool(id: toolId) else { continue }
            if tool.matches(command) { return toolId }
        }
        return "bash"
    }

    private static func readOnlyCommand(_ cmd: String) -> Bool {
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        let readOnlyTools: Set<String> = [
            "cat", "head", "tail", "less", "more",
            "ls", "find", "grep", "rg", "fgrep", "egrep",
            "wc", "stat", "file", "du", "tree", "pwd"
        ]
        guard readOnlyTools.contains(first) else { return false }
        let dangerous = [">", ">>", "&&", "||", ";", "`", "$("]
        return !dangerous.contains { cmd.contains($0) }
    }

    private static func appendOrCreateCommand(_ cmd: String) -> Bool {
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        guard ["echo", "printf", "tee", "cp", "python", "python3"].contains(first) else { return false }
        guard !cmd.contains(" rm ") && !cmd.hasPrefix("rm ") else { return false }
        return cmd.contains(">") || cmd.contains("tee") || first == "cp" || first == "python" || first == "python3"
    }

    private static func citadelCommand(_ cmd: String) -> Bool {
        cmd.contains("workspace/citadel/") || cmd.contains("workspace/wiki/")
    }

    // MARK: - Prompt Rendering

    /// Render the execution contract for injection into a heartbeat prompt.
    @MainActor
    static func renderAvailableToolsBlock(forAgentId agentId: String) -> String {
        let allowed = allowedTools(forAgentId: agentId)
        let metadata = allowed.filter { $0 != "bash" }.joined(separator: ", ")
        let metadataLine = metadata.isEmpty ? "" : " Console loadout metadata: \(metadata)."
        return """
        Full shell execution is available on this heartbeat. Invoke local work by wrapping commands in ```bash code fences```. Every command fence is sent to ExecutionService; the loadout is metadata for organization, not an execution gate.\(metadataLine)
        """
    }
}
