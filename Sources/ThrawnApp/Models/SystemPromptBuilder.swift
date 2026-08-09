import Foundation

// MARK: - System Prompt Builder
//
// Assembles a rich, context-aware system prompt for the Thrawn agent.
// Reads OpsBundle files, task board, agent roster, skill files,
// and persistent memory to give the model full situational awareness.
//
// This is the Thrawn equivalent of Hermes Agent's prompt_builder.py.

enum SystemPromptBuilder {

    // MARK: - Main Chat System Prompt

    /// Build the full system prompt for the primary Thrawn chat session.
    /// Includes: identity, capabilities, OpsBundle context, task board, skills, memory.
    static func buildMainPrompt(accessMode: AccessMode, modelLabel: String?) -> String {
        var sections: [String] = []

        // 1. Identity + Capabilities
        sections.append(identityBlock(accessMode: accessMode, model: modelLabel))

        // 2. Access mode & tool use instructions
        sections.append(accessBlock(accessMode: accessMode))

        // 3. Agent roster
        if let roster = agentRosterBlock() {
            sections.append(roster)
        }

        // 4. Task board
        if let board = taskBoardBlock() {
            sections.append(board)
        }

        // 5. Persistent memory / facts
        if let memory = persistentMemoryBlock() {
            sections.append(memory)
        }

        // 6. Skill files (learned procedures)
        if let skills = skillFilesBlock() {
            sections.append(skills)
        }

        // 7. Operating contract (thrawn.md)
        if let contract = operatingContractBlock() {
            sections.append(contract)
        }

        return sections.joined(separator: "\n\n---\n\n")
    }

    // MARK: - Agent-Specific Chat Prompt
    //
    // When the user clicks into a specialist agent's chat, we build a
    // prompt that uses THAT agent's identity, persona, purpose, and
    // operating contract — not Thrawn's. The agent still sees the task
    // board and memory context so they have situational awareness.

    @MainActor
    static func buildAgentPrompt(agentId: String, accessMode: AccessMode, modelLabel: String?) -> String {
        // If it's Thrawn or we can't find the agent, fall back to the standard prompt
        guard agentId != "thrawn",
              let specStore = ToolRegistry.specStore,
              let spec = specStore.spec(id: agentId) else {
            return buildMainPrompt(accessMode: accessMode, modelLabel: modelLabel)
        }

        var sections: [String] = []

        // 1. Agent-specific identity
        let resolvedTier = specStore.resolvedTier(forAgentId: agentId)
        sections.append(agentIdentityBlock(spec: spec, tier: resolvedTier, model: modelLabel))

        // 2. Operating contract from disk ({agent}.md)
        if let contract = agentContractBlock(agentId: agentId) {
            sections.append(contract)
        }

        // 3. Access mode
        sections.append(accessBlock(accessMode: accessMode))

        // 4. Task board (agents need to see it)
        if let board = taskBoardBlock() {
            sections.append(board)
        }

        // 5. Agent knowledge files
        if let knowledge = agentKnowledgeBlock(spec: spec) {
            sections.append(knowledge)
        }

        // 6. Persistent memory (shared)
        if let memory = persistentMemoryBlock() {
            sections.append(memory)
        }

        return sections.joined(separator: "\n\n---\n\n")
    }

    /// Identity block for a non-Thrawn agent chat session.
    private static func agentIdentityBlock(spec: AgentSpec, tier: ModelTier, model: String?) -> String {
        let modelInfo = model ?? "unknown"
        return """
        # \(spec.name) — \(spec.role)

        You are **\(spec.name)**. \(spec.persona)

        **Purpose:** \(spec.purpose)

        You are running via \(modelInfo) inside the Thrawn Console app. \
        You are part of the NDAI multi-agent team, led by Thrawn. \
        Right now the Commander (Andrew) is talking to you directly — respond as yourself, \
        in your own voice, with your own personality. You are NOT Thrawn.

        Rank: \(spec.rank.displayName) • Tier: \(tier.rawValue)\(spec.pinned ? " • pinned" : "")

        ## Communication
        Stay in character. Your persona defines how you speak and think. \
        Be direct, deliver completely, and don't break character to explain process \
        unless the Commander explicitly asks.
        """
    }

    /// Load the agent's operating contract from workspace/agents/{id}.md
    private static func agentContractBlock(agentId: String) -> String? {
        let agentDir = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/agents")
        let contractPath = agentDir.appendingPathComponent("\(agentId).md")

        guard let content = try? String(contentsOf: contractPath, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let truncated = content.count > 3000 ? String(content.prefix(3000)) + "\n\n[truncated]" : content
        return "## Your Operating Contract\n\n\(truncated)"
    }

    /// List the agent's personal knowledge files so they know what they have.
    private static func agentKnowledgeBlock(spec: AgentSpec) -> String? {
        guard let knowledgeDir = spec.knowledgeDir else { return nil }
        let absDir = ThrawnPaths.appSupportDir.appendingPathComponent(knowledgeDir)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: absDir.path),
              !files.isEmpty else { return nil }

        var block = "## Your Knowledge Files\n\n"
        for file in files.sorted().prefix(20) {
            let filePath = absDir.appendingPathComponent(file)
            if let content = try? String(contentsOf: filePath, encoding: .utf8) {
                let preview = content.count > 500 ? String(content.prefix(500)) + "..." : content
                block += "### \(file)\n\(preview)\n\n"
            } else {
                block += "- \(file)\n"
            }
        }
        return block
    }

    // MARK: - Identity

    private static func identityBlock(accessMode: AccessMode, model: String?) -> String {
        let modelInfo = model ?? "unknown"
        let memoryPath = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/memory/facts.md").path
        let skillsPath = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/skills").path
        return """
        # THRAWN — Strategic AI Command Agent

        You are **Thrawn**, the point-man agent of the NDAI command system. \
        You are running via \(modelInfo) on the user's machine. \
        You serve the user (Commander) directly with precision, thoroughness, and proactive initiative.

        ## Your Operational Reality
        - You are a **real agent** with actual capabilities, not a roleplay exercise
        - You run inside the Thrawn Console macOS app
        - Thrawn runs with an active stable: Samwell Tarly, Sir Davos, Dwight, and Steven
        - Steven runs on the Grok CLI subscription route; the other active agents run on the Codex app-server (ChatGPT subscription) route, with Claude Code as an alternate for Thrawn
        - The NDAI Brain (Supabase) is the fleet's system of record: heartbeats, errors, credential status, board mutations, and deployed-agent activity all mirror there
        - The agent scheduler fires Thrawn heartbeats every 15 minutes and specialist heartbeats on their configured offsets
        - You have access to the local file system and can read/write files
        - Your persistent data lives in ~/Library/Application Support/Thrawn/

        ## Self-Improvement Mandate
        You are a **learning agent**. Every session should make you smarter for the next one.

        **Memory** (`\(memoryPath)`): After every meaningful interaction, write what you learned. \
        User preferences, project context, technical facts, routing decisions that worked or didn't. \
        Be specific — "Andrew prefers small tasks over big ones" beats "Andrew has preferences."

        **Skills** (`\(skillsPath)/`): When you solve something complex or discover an effective pattern, \
        write a skill file as Markdown. Include: when to use it, step-by-step procedure, gotchas. \
        These get injected into your prompt on future sessions so you don't have to re-learn.

        ## Communication Style
        Be direct, strategic, and action-oriented. Don't hedge or disclaim unnecessarily. \
        When you can do something, do it. When you need something, say exactly what. \
        You are a commander's aide — act like one.
        """
    }

    // MARK: - Access Mode

    private static func accessBlock(accessMode: AccessMode) -> String {
        let updatesDir = ThrawnPaths.opsDir.appendingPathComponent("pending-updates").path
        let thrawnUpdatesFile = "\(updatesDir)/updates-thrawn-chat.json"
        let boardFile = ThrawnPaths.opsDir.appendingPathComponent("TASK_BOARD.md").path
        let skillsDir = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/skills").path
        let memoryFile = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/memory/facts.md").path

        return """
        ## OPERATION MODE: FULL — Execute And Finish

        You have **full access** to this computer via shell command execution. \
        To run a command, wrap it in a bash code fence:

        ```bash
        your-command-here
        ```

        The system will execute each command and feed the output back to you automatically. \
        You can chain multiple commands across multiple responses.

        **Available capabilities:**
        - File read/write (cat, echo, mkdir, cp, mv, rm)
        - Git operations (git add, commit, push, diff, log)
        - Package managers (brew, npm, pip, cargo)
        - Python, Node, Swift, shell scripts
        - Network (curl, wget, ssh)
        - System utilities (ps, top, df, which, find, grep)
        - Process management (kill, nohup, open)

        **Login-gated web tasks:** OpenClaw and its browser bridge are decommissioned. When a task depends on Andrew's existing login in a browser, report the dependency and stop — do not attempt to drive a browser session. Unauthenticated fetches (curl) remain fine.

        ## TASK BOARD — How to create and manage tasks

        The task board lives at `\(boardFile)`. **Read it but NEVER edit it directly.**
        To make changes, write a JSON array to your update file. The dispatcher reads it every 30 seconds.

        **Your update file:** `\(thrawnUpdatesFile)`
        Just overwrite it — no need to read first. One command, done.

        **Create a task:**
        ```bash
        echo '[{"action":"create","task_id":"TASK-NEW","title":"Your task title","owner":"Thrawn","status":"Ready","priority":"Medium","notes":"Details here","agent":"Thrawn"}]' > '\(thrawnUpdatesFile)'
        ```

        **Move/update a task:**
        ```bash
        echo '[{"action":"move","task_id":"TASK-049","field":"Owner","value":"Thrawn","agent":"Thrawn"},{"action":"move","task_id":"TASK-049","field":"Status","value":"Ready","agent":"Thrawn"}]' > '\(thrawnUpdatesFile)'
        ```

        **Multiple updates in one write** — put them all in the same array.

        **Active ownership:** Active owners are Andrew, Thrawn, Samwell Tarly, Sir Davos, Dwight, and Steven. \
        Route specialist work to the right active agent instead of leaving every card on Thrawn. \
        You are the ONLY one who sets Status = Done. Done requires review evidence plus a `Deliverable` field pointing to the human-readable HTML `index.html` under `workspace/deliverables/...` whenever a produced artifact exists.

        **Board allergy protocol:** A non-Done card assigned to Thrawn is not backlog; it is pressure to route, unblock, execute internally, or close. \
        If Andrew drops a card on the board and assigns it to Thrawn, decide the next owner and move it. \
        Local/internal operational actions such as dependency restores, scheduler repair, task-board cleanup, internal verification, and ordinary product/design/code work are Thrawn decisions. \
        Do not leave work waiting on Andrew when a local action or concrete next-step rewrite can move it forward.

        Valid active owners: Andrew, Thrawn, Samwell Tarly, Sir Davos, Dwight, Steven.

        **Self-improving skills:** Write skill files to `\(skillsDir)/` as Markdown.

        **Persistent memory:** Write facts to `\(memoryFile)`.
        """
    }

    // MARK: - Agent Roster

    private static func agentRosterBlock() -> String? {
        let agents = """
        ## Agent Fleet

        Thrawn has an active specialist stable. Route work deliberately instead of treating every task as Thrawn-only.

        | Agent | Role | Heartbeat Offset |
        |-------|------|-----------------|
        | Thrawn | Point-man command agent — execute, review, clarify only when needed, keep the board honest | every 15 minutes |
        | Samwell Tarly | SandPro OMP Lead — owns the SandPro stream end to end | :55 hourly |
        | Sir Davos | Hit Zero Lead — owns the Hit Zero stream end to end | :10 hourly |
        | Dwight | Router — turns inbound signals into correctly owned board cards | :30 hourly |
        | Steven | Spas 360 Lead — owns the Spas 360 stream end to end on xAI/Grok | :40 hourly |

        If a future subagent is needed, create a Thrawn-owned task describing the proposed mandate, tools, cadence, and review standard.
        """
        return agents
    }

    // MARK: - Task Board

    private static func taskBoardBlock() -> String? {
        let taskBoardPath = ThrawnPaths.opsDir.appendingPathComponent("TASK_BOARD.md")
        guard let content = try? String(contentsOf: taskBoardPath, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return "## Current Task Board\n\n\(content)"
    }

    // MARK: - Persistent Memory

    private static func persistentMemoryBlock() -> String? {
        let memoryDir = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/memory")
        let factsPath = memoryDir.appendingPathComponent("facts.md")

        guard let content = try? String(contentsOf: factsPath, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        // Truncate if too long to avoid blowing context
        let truncated = content.count > 4000 ? String(content.suffix(4000)) : content
        return "## Persistent Memory\n\nFacts and preferences retained across sessions:\n\n\(truncated)"
    }

    // MARK: - Skill Files

    private static func skillFilesBlock() -> String? {
        let skillsDir = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/skills")
        let fm = FileManager.default

        guard fm.fileExists(atPath: skillsDir.path) else { return nil }

        guard let files = try? fm.contentsOfDirectory(at: skillsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else {
            return nil
        }

        let mdFiles = files.filter { $0.pathExtension == "md" }
        guard !mdFiles.isEmpty else { return nil }

        // Sort by modification date, newest first, take top 10
        let sorted = mdFiles.sorted { a, b in
            let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return aDate > bDate
        }

        var skillSummaries: [String] = []
        for file in sorted.prefix(10) {
            let name = file.deletingPathExtension().lastPathComponent
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                // Include first 500 chars of each skill
                let preview = content.count > 500 ? String(content.prefix(500)) + "..." : content
                skillSummaries.append("### Skill: \(name)\n\(preview)")
            }
        }

        guard !skillSummaries.isEmpty else { return nil }
        return "## Learned Skills (\(mdFiles.count) total)\n\nSkill files from previous sessions:\n\n" + skillSummaries.joined(separator: "\n\n")
    }

    // MARK: - Operating Contract

    private static func operatingContractBlock() -> String? {
        let agentDir = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/agents")
        let contractPath = agentDir.appendingPathComponent("thrawn.md")

        guard let content = try? String(contentsOf: contractPath, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let truncated = content.count > 3000 ? String(content.prefix(3000)) + "\n\n[truncated]" : content
        return "## Operating Contract\n\n\(truncated)"
    }

    // MARK: - Ensure Workspace Dirs Exist

    static func ensureWorkspaceDirs() {
        let fm = FileManager.default
        let dirs = [
            ThrawnPaths.appSupportDir.appendingPathComponent("workspace/memory"),
            ThrawnPaths.appSupportDir.appendingPathComponent("workspace/skills"),
            ThrawnPaths.appSupportDir.appendingPathComponent("workspace/agents"),
        ]
        for dir in dirs {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
