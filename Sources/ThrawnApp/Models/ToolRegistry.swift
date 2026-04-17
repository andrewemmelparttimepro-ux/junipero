import Foundation

// MARK: - Tool Registry
//
// Every capability an agent can invoke is modeled as a Tool. Agents declare
// which tools they're allowed to use; unauthorized commands are denied at
// the scheduler level before they ever reach ExecutionService.
//
// For v1, all tool invocations flow through bash code fences — the agent
// outputs ```bash blocks and we match each command against their allowed
// tools. This keeps LLMs fluent in a syntax they already know while giving
// us per-agent capability gating.
//
// Built-in tools:
//   • bash        — wildcard shell access (dev-ops squad tier)
//   • file_read   — read-only file operations (cat/head/tail/ls/grep/find/...)
//   • task_write  — write to pending-updates/updates-{agent}.json
//   • memory_read — read from workspace/agents/{agent}/knowledge/
//   • memory_write— append to workspace/agents/{agent}/knowledge/
//
// Step 2 will replace the hardcoded default toolset with a per-agent list
// read from AgentSpec. For Step 1, every existing dev-ops agent inherits
// the default `[bash, file_read, task_write]` loadout so nothing changes.

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

    static let all: [Tool] = [bash, fileRead, taskWrite, memoryRead, memoryWrite, webSearch, webScrape]

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
        if let store = specStore {
            return store.resolvedTools(forAgentId: id)
        }
        return devopsDefault
    }

    // MARK: - Authorization

    /// Check whether an agent is allowed to execute the given command.
    /// Returns the ID of the matching tool, or nil if the command is denied.
    ///
    /// Bash is a wildcard — if an agent has `bash` in their toolset, every
    /// command is authorized regardless of what other tools they have.
    static func authorize(command: String, allowedToolIds: [String]) -> String? {
        // Wildcard short-circuit
        if allowedToolIds.contains("bash") { return "bash" }

        // Check each non-bash tool in order
        for toolId in allowedToolIds where toolId != "bash" {
            guard let tool = tool(id: toolId) else { continue }
            if tool.matches(command) { return toolId }
        }
        return nil
    }

    // MARK: - Prompt Rendering

    /// Render the tool list as markdown for injection into a heartbeat prompt.
    /// The agent sees only the tools they're allowed to use.
    @MainActor
    static func renderAvailableToolsBlock(forAgentId agentId: String) -> String {
        let allowed = allowedTools(forAgentId: agentId)
        guard !allowed.isEmpty else {
            return "You have no execution tools available on this heartbeat. Respond with text only."
        }

        var block = "You have the following tools available:\n\n"
        for toolId in allowed {
            guard let t = tool(id: toolId) else { continue }
            block += "- **\(t.id)** — \(t.description)\n"
        }
        block += "\nInvoke tools by wrapping commands in ```bash code fences. "
        block += "Every command you output is matched against your allowed tools before execution. "
        block += "Unauthorized commands are denied and logged, but do not stop the heartbeat.\n"
        return block
    }
}
