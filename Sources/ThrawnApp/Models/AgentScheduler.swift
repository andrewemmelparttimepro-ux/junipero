import Foundation
import SwiftUI

// MARK: - Native Agent Scheduler
//
// Replaces the external cron system with in-app Swift timers.
// Each agent has a heartbeat interval. When it fires, the scheduler
// sends the agent's heartbeat prompt to the Anthropic API via
// an isolated conversation and tracks the result.
//
// When in UNLEASHED mode, agents can execute shell commands via
// ExecutionService — creating a real agentic loop.

struct AgentHeartbeatConfig: Identifiable, Codable {
    let id: String              // Agent ID: "r2d2", "quigon", etc.
    let name: String            // Display name: "R2-D2"
    let minuteOffset: Int       // Minute of the hour to fire (0-59)
    let heartbeatFile: String   // e.g. "r2d2.HEARTBEAT.md"
    let agentFile: String       // e.g. "r2d2.md"
    let outputFile: String      // e.g. "r2d2.json"
    var enabled: Bool
}

@MainActor
final class AgentScheduler: ObservableObject {
    @Published var agents: [AgentHeartbeatConfig]
    @Published var runningAgents: Set<String> = []
    @Published var lastRunTimes: [String: Date] = [:]
    @Published var lastRunResults: [String: String] = [:]

    private var timerTask: Task<Void, Never>?
    private var activeRuns: [String: Task<Void, Never>] = [:]
    private weak var ollamaClient: OllamaClient?
    private weak var anthropicClient: AnthropicClient?
    private weak var openaiClient: OpenAIClient?
    private weak var roster: AgentRosterStore?
    private weak var executionService: ExecutionService?
    private weak var objectiveStore: ObjectiveStore?
    private weak var handoffStore: HandoffStore?
    private weak var specStore: AgentSpecStore?
    private var providerRouter: ProviderRouter?

    /// Briefing service — wired after startup so the scheduler can fire
    /// SOD at 07:00 and EOD at 19:00 without needing a separate cron.
    private weak var briefingService: BriefingService?

    /// Voice service — wired after startup so each heartbeat can speak
    /// an opening and closing line through AVSpeechSynthesizer.
    private weak var voiceService: VoiceService?

    private static let configPath = ThrawnPaths.appSupportDir
        .appendingPathComponent("agent-scheduler.json")

    static let defaultAgents: [AgentHeartbeatConfig] = [
        AgentHeartbeatConfig(id: "thrawn",       name: "Thrawn",   minuteOffset: 0,  heartbeatFile: "thrawn.HEARTBEAT.md",           agentFile: "thrawn.md",  outputFile: "thrawn.json",       enabled: true),
        AgentHeartbeatConfig(id: "thrawn-dream",  name: "Thrawn",   minuteOffset: 5,  heartbeatFile: "thrawn-dream.HEARTBEAT.md",    agentFile: "thrawn.md",  outputFile: "thrawn-dream.json", enabled: true),
        AgentHeartbeatConfig(id: "thrawn-handoff", name: "Thrawn",  minuteOffset: 2,  heartbeatFile: "thrawn-handoff.HEARTBEAT.md",  agentFile: "thrawn.md",  outputFile: "thrawn-handoff.json", enabled: true),
        AgentHeartbeatConfig(id: "r2d2",         name: "R2-D2",    minuteOffset: 10, heartbeatFile: "r2d2.HEARTBEAT.md",             agentFile: "r2d2.md",    outputFile: "r2d2.json",         enabled: true),
        AgentHeartbeatConfig(id: "c3po",         name: "C-3PO",    minuteOffset: 20, heartbeatFile: "c3po.HEARTBEAT.md",             agentFile: "c3po.md",    outputFile: "c3po.json",         enabled: true),
        AgentHeartbeatConfig(id: "quigon",       name: "Qui-Gon",  minuteOffset: 30, heartbeatFile: "quigon.HEARTBEAT.md",           agentFile: "quigon.md",  outputFile: "quigon.json",       enabled: true),
        AgentHeartbeatConfig(id: "lando",        name: "Lando",    minuteOffset: 40, heartbeatFile: "lando.HEARTBEAT.md",            agentFile: "lando.md",   outputFile: "lando.json",        enabled: true),
        AgentHeartbeatConfig(id: "boba",         name: "Boba",     minuteOffset: 50, heartbeatFile: "boba.HEARTBEAT.md",             agentFile: "boba.md",    outputFile: "boba.json",         enabled: true),
        // V2 agents — personality-first, purpose-specific
        AgentHeartbeatConfig(id: "bart",         name: "Bart",     minuteOffset: 15, heartbeatFile: "bart.HEARTBEAT.md",             agentFile: "bart.md",    outputFile: "bart.json",         enabled: true),
        AgentHeartbeatConfig(id: "hunter",       name: "Hunter",   minuteOffset: 25, heartbeatFile: "hunter.HEARTBEAT.md",           agentFile: "hunter.md",  outputFile: "hunter.json",       enabled: true),
        AgentHeartbeatConfig(id: "alborland",   name: "Al Borland", minuteOffset: 35, heartbeatFile: "alborland.HEARTBEAT.md",     agentFile: "alborland.md", outputFile: "alborland.json", enabled: true),
    ]

    init() {
        self.agents = Self.loadConfig() ?? Self.defaultAgents
    }

    // MARK: - Binding

    func bind(
        ollamaClient: OllamaClient,
        roster: AgentRosterStore,
        execution: ExecutionService? = nil,
        objectives: ObjectiveStore? = nil,
        handoffs: HandoffStore? = nil,
        specs: AgentSpecStore? = nil,
        anthropic: AnthropicClient? = nil,
        openai: OpenAIClient? = nil
    ) {
        self.ollamaClient = ollamaClient
        self.anthropicClient = anthropic
        self.openaiClient = openai
        self.roster = roster
        self.executionService = execution
        self.objectiveStore = objectives
        self.handoffStore = handoffs
        self.specStore = specs
        self.providerRouter = ProviderRouter(ollama: ollamaClient, anthropic: anthropic, openai: openai)
    }

    /// Wire the briefing service so the scheduler can fire SOD at 07:00
    /// and EOD at 19:00 automatically. Called from ThrawnApp at startup.
    func bind(briefing: BriefingService) {
        self.briefingService = briefing
    }

    /// Wire the voice service so each heartbeat can fire open/close
    /// announcements. Called from ThrawnApp at startup.
    func bind(voice: VoiceService) {
        self.voiceService = voice
    }

    // MARK: - Start/Stop

    func start() {
        guard timerTask == nil else { return }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                // Check every 30 seconds
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
        for task in activeRuns.values { task.cancel() }
        activeRuns.removeAll()
        runningAgents.removeAll()
    }

    // MARK: - Manual Trigger

    func triggerAgent(_ agentId: String) {
        guard let config = agents.first(where: { $0.id == agentId }) else { return }
        runHeartbeat(for: config)
    }

    /// Manually trigger a handoff (morning or evening) right now.
    /// Used by the flow board drag-drop trigger and the Handoffs view button.
    func triggerHandoff(kind: HandoffKind) {
        guard let store = handoffStore else { return }
        store.generate(kind: kind)
        if let config = agents.first(where: { $0.id == "thrawn-handoff" }) {
            runHeartbeat(for: config)
        }
    }

    // MARK: - Tick (runs every 30s)

    private func tick() async {
        let now = Date()
        let calendar = Calendar.current
        let currentMinute = calendar.component(.minute, from: now)
        let currentHour = calendar.component(.hour, from: now)

        // Reset blocked agents back to idle so they can retry on next heartbeat
        if let roster {
            for agent in roster.agents where agent.state == .blocked {
                roster.setState(id: agent.id, state: .idle, detail: "Standing by")
            }
        }

        // MARK: - SOD / EOD briefing trigger
        //
        // SOD fires once per day at 07:00 local; EOD at 19:00 local.
        // `BriefingService.lastRunAt` tracks the last fire per kind,
        // so a restart mid-window doesn't re-fire the same briefing.
        // The tick loop runs every 30 seconds, so firing on minute 0
        // gives us a couple of chances to catch the hour transition.
        if let briefing = briefingService, !briefing.isGenerating {
            if currentHour == Self.sodHour && currentMinute == 0 {
                if Self.shouldFireBriefing(kind: .sod, lastRun: briefing.lastRunAt[.sod], now: now) {
                    FlightRecorder.logEvent(
                        category: "briefing", action: "auto-trigger",
                        detail: "SOD @\(currentHour):\(currentMinute)"
                    )
                    Task { await briefing.generate(kind: .sod) }
                }
            }
            if currentHour == Self.eodHour && currentMinute == 0 {
                if Self.shouldFireBriefing(kind: .eod, lastRun: briefing.lastRunAt[.eod], now: now) {
                    FlightRecorder.logEvent(
                        category: "briefing", action: "auto-trigger",
                        detail: "EOD @\(currentHour):\(currentMinute)"
                    )
                    Task { await briefing.generate(kind: .eod) }
                }
            }
        }

        for agent in agents where agent.enabled {
            // Don't fire if already running
            guard !runningAgents.contains(agent.id) else { continue }

            // Thrawn fires every 15 minutes (hub — needs to route frequently)
            // Dream cycle fires every 6 hours
            // Other agents fire once per hour at their minuteOffset
            let shouldFire: Bool
            let minGap: Double

            if agent.id == "thrawn" {
                shouldFire = currentMinute % 15 == 0
                minGap = 12
            } else if agent.id == "thrawn-dream" {
                // Dream cycle: fire at :05 past the hour, every 6 hours
                let hour = calendar.component(.hour, from: now)
                shouldFire = currentMinute == 5 && hour % 6 == 0
                minGap = 300  // At least 5 hours between dreams
            } else if agent.id == "thrawn-handoff" {
                // Twice-daily handoff to Claude: 09:02 and 17:02
                let hour = calendar.component(.hour, from: now)
                let isHandoffHour = (hour == 9 || hour == 17)
                shouldFire = isHandoffHour && currentMinute == 2
                minGap = 300  // At least 5 hours between handoffs

                // Generate the handoff report BEFORE the heartbeat fires,
                // so Thrawn's commentary has something to append to.
                if shouldFire, let store = handoffStore {
                    let kind: HandoffKind = hour == 9 ? .morning : .evening
                    if store.shouldGenerate(kind: kind, now: now) {
                        store.generate(kind: kind)
                    }
                }
            } else {
                shouldFire = currentMinute == agent.minuteOffset
                minGap = 50
            }

            guard shouldFire else { continue }

            if let lastRun = lastRunTimes[agent.id] {
                let minutesSinceLastRun = now.timeIntervalSince(lastRun) / 60
                guard minutesSinceLastRun > minGap else { continue }
            }

            runHeartbeat(for: agent)
        }
    }

    // MARK: - Execute Heartbeat

    private func runHeartbeat(for agent: AgentHeartbeatConfig) {
        guard !runningAgents.contains(agent.id) else { return }

        runningAgents.insert(agent.id)
        roster?.setState(id: agent.id, state: .working, detail: "Heartbeat running…")

        let task = Task { [weak self] in
            guard let self else { return }

            let startTime = Date()
            FlightRecorder.logHeartbeat(agent: agent.id, event: "start")

            // Build the heartbeat prompt from files
            let prompt = self.buildHeartbeatPrompt(for: agent)

            guard !prompt.isEmpty else {
                FlightRecorder.logHeartbeat(agent: agent.id, event: "skipped", detail: "No heartbeat file found")
                await MainActor.run {
                    self.runningAgents.remove(agent.id)
                    self.lastRunResults[agent.id] = "No heartbeat file found"
                    self.roster?.setState(id: agent.id, state: .idle, detail: "No heartbeat config")
                }
                return
            }

            // Send to the active provider (isolated conversation — no history)
            var responseText = ""
            var completed = false
            var errorMsg: String?

            let systemPrompt = "You are \(agent.name). You have \(Self.maxToolRounds) tool-use rounds. DO THE WORK on your assigned tasks — produce deliverables, write code, run commands. Then write your task board updates to your update file. Do not waste rounds on exploration or status reports."
            let sessionKey = "agent:heartbeat:\(agent.id)"

            // Use a semaphore-like pattern with continuation
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.sendToActiveProvider(
                    agentId: agent.id,
                    text: prompt,
                    systemPrompt: systemPrompt,
                    sessionKey: sessionKey,
                    onDelta: { delta in
                        responseText += delta
                    },
                    onComplete: { finalText, _ in
                        responseText = finalText
                        completed = true
                        continuation.resume()
                    },
                    onError: { error in
                        errorMsg = error
                        continuation.resume()
                    }
                )
            }

            let duration = Date().timeIntervalSince(startTime)

            await MainActor.run {
                self.runningAgents.remove(agent.id)
                self.lastRunTimes[agent.id] = startTime

                if completed {
                    // Peel the first + last lines as spoken open/close
                    // announcements. The preamble told the agent to put
                    // a short in-character sentence on each, with no
                    // markdown / fences / JSON. We strip them before
                    // tool extraction so they never reach bash parsing.
                    let (openLine, closeLine, stripped) = Self.peelVoiceLines(from: responseText)
                    if let open = openLine, !open.isEmpty {
                        self.voiceService?.announce(agentId: agent.id, kind: .open, text: open)
                    }
                    if let close = closeLine, !close.isEmpty, close != openLine {
                        self.voiceService?.announce(agentId: agent.id, kind: .close, text: close)
                    }
                    responseText = stripped

                    let durationMs = Int(duration * 1000)
                    let summary = String(responseText.prefix(200))
                    self.lastRunResults[agent.id] = summary

                    FlightRecorder.logHeartbeat(
                        agent: agent.id, event: "complete",
                        durationMs: durationMs,
                        detail: String(responseText.prefix(150))
                    )

                    // Write output to agent's output file
                    self.writeAgentOutput(agent: agent, response: responseText, durationMs: durationMs)

                    // Execute any shell commands from the response (unleashed mode only)
                    if let exec = self.executionService, exec.accessMode.isUnleashed {
                        Task {
                            await self.executeToolCalls(from: responseText, agent: agent)
                        }
                    }

                    // Transition: working → review → idle
                    self.roster?.setState(id: agent.id, state: .review, detail: "Heartbeat complete")
                    Task {
                        try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s in review
                        await MainActor.run {
                            if self.roster?.agents.first(where: { $0.id == agent.id })?.state == .review {
                                self.roster?.setState(id: agent.id, state: .idle, detail: "Standing by")
                            }
                        }
                    }
                } else {
                    let errDetail = errorMsg ?? "unknown"
                    self.lastRunResults[agent.id] = "Error: \(errDetail)"
                    FlightRecorder.logHeartbeat(
                        agent: agent.id, event: "error",
                        durationMs: Int(duration * 1000),
                        detail: errDetail
                    )
                    FlightRecorder.logError(source: "heartbeat:\(agent.id)", message: errDetail)
                    self.roster?.setState(id: agent.id, state: .blocked, detail: errorMsg ?? "Heartbeat failed")
                }

                self.activeRuns.removeValue(forKey: agent.id)
            }
        }

        activeRuns[agent.id] = task
    }

    // MARK: - Build Prompt from Heartbeat Files

    private func buildHeartbeatPrompt(for agent: AgentHeartbeatConfig) -> String {
        let opsDir = ThrawnPaths.opsDir
        let boardFile = ThrawnPaths.opsDir.appendingPathComponent("TASK_BOARD.md").path
        let updatesDir = ThrawnPaths.opsDir.appendingPathComponent("pending-updates").path
        let myUpdatesFile = "\(updatesDir)/updates-\(agent.id).json"

        var sections: [String] = []

        // 1. Read task board FIRST — this is what the agent needs most
        let taskBoardPath = opsDir.appendingPathComponent("TASK_BOARD.md")
        if let content = try? String(contentsOf: taskBoardPath, encoding: .utf8) {
            sections.append("## TASK BOARD\n\n\(content)")
        }

        // 2. Read heartbeat instructions
        let heartbeatPath = opsDir.appendingPathComponent("heartbeats/\(agent.heartbeatFile)")
        if let content = try? String(contentsOf: heartbeatPath, encoding: .utf8) {
            sections.append("## Your Heartbeat Instructions\n\n\(content)")
        }

        // 3. Read agent operating contract
        let agentDir = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/agents")
        let agentPath = agentDir.appendingPathComponent(agent.agentFile)
        if let content = try? String(contentsOf: agentPath, encoding: .utf8) {
            sections.append("## Your Operating Contract\n\n\(content)")
        }

        // 4. Objectives context (Thrawn agents only)
        if agent.id.hasPrefix("thrawn"), let objContext = objectiveStore?.heartbeatContext() {
            sections.append(objContext)
        }

        // 5. Spec-driven identity (brief — just name, role, persona)
        if let spec = specStore?.spec(id: agent.id) {
            let tier = specStore?.resolvedTier(forAgentId: agent.id) ?? .local
            var identity = "## Identity\n\n"
            identity += "**\(spec.name)** — \(spec.role). \(spec.persona)\n"
            identity += "Rank: \(spec.rank.displayName) • Tier: \(tier.rawValue)"
            if spec.pinned { identity += " • pinned" }

            if let knowledgeDir = spec.knowledgeDir {
                let absDir = ThrawnPaths.appSupportDir.appendingPathComponent(knowledgeDir)
                if let files = try? FileManager.default.contentsOfDirectory(atPath: absDir.path),
                   !files.isEmpty {
                    let listing = files.sorted().prefix(10).map { "- \(knowledgeDir)/\($0)" }.joined(separator: "\n")
                    identity += "\n\nKnowledge files:\n\(listing)"
                }
            }

            sections.append(identity)
        }

        if sections.isEmpty { return "" }

        // Access-mode aware preamble — TIGHT, directive, no fluff
        let toolsLine: String
        if let exec = executionService, exec.accessMode.isUnleashed {
            let toolsBlock = ToolRegistry.renderAvailableToolsBlock(forAgentId: agent.id)
            toolsLine = "MODE: UNLEASHED. \(toolsBlock)"
        } else {
            toolsLine = "MODE: RESTRICTED — text only, no commands."
        }

        let preamble = """
        YOU ARE \(agent.name.uppercased()). DO THE WORK. NOT JUST RECONNAISSANCE.

        \(toolsLine)

        UPDATE FILE: `\(myUpdatesFile)`
        TASK BOARD: `\(boardFile)`

        VOICE PROTOCOL — MANDATORY:
        • Your FIRST line of the response is a SPOKEN open announcement. In character, under 12 words. Example: "R2 here. Building TASK-049."
        • Your LAST line of the response is a SPOKEN close announcement. In character, under 12 words. Example: "R2 out. Tests green."
        • Both lines are standalone — no markdown, no code fences, no prefix like "SPEAK:". Just the plain sentence.
        • Do NOT put bash commands or JSON on the first or last line. The harness strips those two lines and speaks them through the voice layer.

        PROCEDURE — follow this EXACTLY:
        1. OPEN LINE (spoken) — short, in character, states what you're about to do.
        2. Look at the TASK BOARD below. Find tasks where Owner = \(agent.name) AND Status = Ready.
        3. DO THE ACTUAL WORK for each task (write code, produce deliverables, run commands).
        4. When done, write your updates:
           ```bash
           echo '[{"action":"move","task_id":"TASK-XXX","field":"Owner","value":"Thrawn","agent":"\(agent.name)"},{"action":"move","task_id":"TASK-XXX","field":"Status","value":"Ready","agent":"\(agent.name)"},{"action":"update","task_id":"TASK-XXX","field":"Notes","value":"What you did","agent":"\(agent.name)"}]' > '\(myUpdatesFile)'
           ```
        5. If no tasks are assigned to you, reply HEARTBEAT_OK on its own line and still emit the open+close spoken lines.
        6. CLOSE LINE (spoken) — short, in character, states what you accomplished.

        DO NOT spend rounds reading directories or exploring. The task board is RIGHT BELOW. Go straight to work.

        ---

        """

        return preamble + sections.joined(separator: "\n\n---\n\n")
    }

    // MARK: - Voice line peeler
    //
    // Pulls the first non-empty line and the last non-empty line out of a
    // heartbeat response so the voice layer can speak them. The peeler
    // refuses any line that looks like markdown, a code fence, JSON, a
    // bash command, or anything over ~140 chars — those are NOT spoken
    // lines and we leave them alone in the response.
    //
    // Returns: (open, close, stripped) where stripped is the response
    // with the spoken lines removed so the tool extractor doesn't see
    // them. If the model didn't comply, both open and close are nil and
    // stripped == input.
    static func peelVoiceLines(from text: String) -> (open: String?, close: String?, stripped: String) {
        let lines = text.components(separatedBy: "\n")
        guard !lines.isEmpty else { return (nil, nil, text) }

        // Find first speakable line index
        var firstIdx: Int? = nil
        for (i, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if isSpeakable(line) {
                firstIdx = i
                break
            } else {
                // First non-empty line wasn't speakable → bail, model didn't comply
                break
            }
        }

        // Find last speakable line index (scanning from the bottom)
        var lastIdx: Int? = nil
        for i in stride(from: lines.count - 1, through: 0, by: -1) {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if isSpeakable(line) {
                lastIdx = i
                break
            } else {
                break
            }
        }

        let open = firstIdx.map { lines[$0].trimmingCharacters(in: .whitespaces) }
        let close = lastIdx.map { lines[$0].trimmingCharacters(in: .whitespaces) }

        // Build stripped output
        var kept: [String] = []
        for (i, raw) in lines.enumerated() {
            if i == firstIdx { continue }
            if i == lastIdx { continue }
            kept.append(raw)
        }
        let stripped = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        return (open, close, stripped)
    }

    /// True if a line looks like a plain in-character spoken sentence,
    /// not markdown / code / json / a command. Conservative — when in
    /// doubt, leave the line in the response.
    private static func isSpeakable(_ line: String) -> Bool {
        if line.count > 140 { return false }
        if line.count < 3 { return false }
        let lower = line.lowercased()
        // Reject anything that smells like markup or code
        let banned: [Character] = ["{", "}", "[", "]", "`", "<", ">", "|", "$"]
        if line.contains(where: { banned.contains($0) }) { return false }
        if line.hasPrefix("#") { return false }
        if line.hasPrefix("- ") || line.hasPrefix("* ") { return false }
        if line.hasPrefix("```") { return false }
        if lower.hasPrefix("echo ") || lower.hasPrefix("cat ") || lower.hasPrefix("ls ") ||
           lower.hasPrefix("cd ") || lower.hasPrefix("bash ") || lower.hasPrefix("sh ") ||
           lower.hasPrefix("git ") || lower.hasPrefix("npm ") || lower.hasPrefix("python") {
            return false
        }
        if lower.hasPrefix("speak:") { return false }
        // Must contain at least one letter
        if !line.contains(where: { $0.isLetter }) { return false }
        return true
    }

    // MARK: - One-shot send (async wrapper for BriefingService, etc.)
    //
    // BriefingService needs to fire a single prompt at a specific agent
    // and get the full response back. It doesn't care about streaming
    // or tool rounds — just "ask this agent one question, get one answer."
    //
    // This wraps sendToActiveProvider in a continuation so callers can
    // await the final text. Routing (Bart → OpenAI, others → Ollama)
    // is handled upstream by the provider router exactly like heartbeats.

    /// Fire a single prompt at an agent and return the full response text.
    /// Returns nil on failure so the caller can skip without blowing up.
    func sendOneShot(
        agentId: String,
        prompt: String,
        systemPrompt: String?,
        sessionKey: String? = nil
    ) async -> String? {
        let key = sessionKey ?? "oneshot-\(agentId)-\(Int(Date().timeIntervalSince1970))"
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            var resumed = false
            let resume: (String?) -> Void = { value in
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: value)
            }
            sendToActiveProvider(
                agentId: agentId,
                text: prompt,
                systemPrompt: systemPrompt,
                sessionKey: key,
                onDelta: { _ in },
                onComplete: { full, _ in resume(full) },
                onError: { err in
                    FlightRecorder.logEvent(
                        category: "briefing", action: "oneshot-error",
                        detail: "\(agentId): \(err)"
                    )
                    resume(nil)
                }
            )
        }
    }

    // MARK: - Provider-Aware Send

    /// Route a send request to the active provider from ProviderStateStore.
    /// Falls back through available providers if the active one isn't connected.
    /// Standard model for all agent heartbeats
    static let agentModel = "kimi-k2.5:cloud"

    private func sendToActiveProvider(
        agentId: String,
        text: String,
        systemPrompt: String?,
        sessionKey: String,
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String, String?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        // Resolve tier from spec store, then route to a concrete backend.
        // Falls back to Ollama if anything upstream is missing or unkeyed —
        // reliability is #1: never silently fail.
        let tier = specStore?.resolvedTier(forAgentId: agentId) ?? .local
        let route = providerRouter?.resolve(tier: tier)
            ?? RoutedProvider(backend: .ollama, model: Self.agentModel, isFallback: true)

        let llmStart = Date()
        let promptLen = text.count
        let sysLen = systemPrompt?.count ?? 0

        let logSuccess: (String, String?) -> Void = { response, model in
            let ms = Int(Date().timeIntervalSince(llmStart) * 1000)
            FlightRecorder.logLLM(
                agent: sessionKey, model: model ?? route.model,
                promptLength: promptLen, responseLength: response.count,
                durationMs: ms, sessionKey: sessionKey,
                systemPromptLength: sysLen, success: true,
                responseSummary: response
            )
            onComplete(response, model)
        }

        let logFailure: (String) -> Void = { error in
            let ms = Int(Date().timeIntervalSince(llmStart) * 1000)
            FlightRecorder.logLLM(
                agent: sessionKey, model: route.model,
                promptLength: promptLen, responseLength: 0,
                durationMs: ms, sessionKey: sessionKey,
                systemPromptLength: sysLen, success: false,
                error: error
            )
            onError(error)
        }

        switch route.backend {
        case .openai:
            if let openai = openaiClient, openai.apiKeyConfigured {
                openai.send(
                    text: text,
                    systemPrompt: systemPrompt,
                    sessionKey: sessionKey,
                    onDelta: onDelta,
                    onComplete: logSuccess,
                    onError: { [weak self] error in
                        FlightRecorder.logEvent(
                            category: "router", action: "fallback",
                            detail: "openai→ollama for \(agentId): \(error)"
                        )
                        self?.dispatchOllama(
                            text: text, systemPrompt: systemPrompt, sessionKey: sessionKey,
                            onDelta: onDelta, onComplete: logSuccess, onError: logFailure
                        )
                    }
                )
                return
            }
            // No key — fall through to Ollama
            dispatchOllama(
                text: text, systemPrompt: systemPrompt, sessionKey: sessionKey,
                onDelta: onDelta, onComplete: logSuccess, onError: logFailure
            )

        case .anthropic:
            if let anthropic = anthropicClient, anthropic.apiKeyConfigured {
                anthropic.send(
                    text: text,
                    systemPrompt: systemPrompt,
                    sessionKey: sessionKey,
                    onDelta: onDelta,
                    onComplete: logSuccess,
                    onError: { [weak self] error in
                        // Cloud failed — fall back to local rather than bubble.
                        FlightRecorder.logEvent(
                            category: "router", action: "fallback",
                            detail: "anthropic→ollama for \(agentId): \(error)"
                        )
                        self?.dispatchOllama(
                            text: text, systemPrompt: systemPrompt, sessionKey: sessionKey,
                            onDelta: onDelta, onComplete: logSuccess, onError: logFailure
                        )
                    }
                )
                return
            }
            // No key — fall through to Ollama
            dispatchOllama(
                text: text, systemPrompt: systemPrompt, sessionKey: sessionKey,
                onDelta: onDelta, onComplete: logSuccess, onError: logFailure
            )

        case .ollama:
            dispatchOllama(
                text: text, systemPrompt: systemPrompt, sessionKey: sessionKey,
                onDelta: onDelta, onComplete: logSuccess, onError: logFailure
            )
        }
    }

    private func dispatchOllama(
        text: String,
        systemPrompt: String?,
        sessionKey: String,
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String, String?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard let client = ollamaClient, client.connected else {
            if let client = ollamaClient {
                Task { await client.refreshConnectionStatus() }
            }
            onError("Ollama not connected. Make sure Ollama is running on localhost:11434.")
            return
        }
        client.send(
            text: text, systemPrompt: systemPrompt, sessionKey: sessionKey,
            model: Self.agentModel,
            onDelta: onDelta,
            onComplete: onComplete,
            onError: onError
        )
    }

    // MARK: - Tool Call Extraction & Execution (Iterative Loop)
    //
    // The agent loop works like this:
    //   1. LLM responds with text + bash commands
    //   2. Commands execute
    //   3. Results feed back to the LLM with "continue working" prompt
    //   4. If the LLM emits more commands → goto 2
    //   5. If no commands → loop ends, final summary written
    //
    // Max rounds prevents runaway loops. Each round is a full LLM call.

    /// Maximum number of tool-use rounds per heartbeat. Agents that need
    /// more work than this should break the task into subtasks.
    private static let maxToolRounds = 8

    // MARK: - SOD/EOD briefing trigger config

    /// Local hour SOD briefings fire at (07:00).
    static let sodHour = 7
    /// Local hour EOD briefings fire at (19:00).
    static let eodHour = 19

    /// True if a briefing of the given kind should fire now. Used by
    /// the tick loop to ensure we only fire once per day. A briefing
    /// whose last-run date is the same local day as `now` is skipped.
    static func shouldFireBriefing(
        kind: BriefingKind,
        lastRun: Date?,
        now: Date
    ) -> Bool {
        guard let last = lastRun else { return true }
        let cal = Calendar.current
        // Same local day? Skip. Different day? Fire.
        return !cal.isDate(last, inSameDayAs: now)
    }

    /// Parse agent response for bash code fences and execute them.
    /// If the follow-up LLM response contains more commands, execute
    /// those too — up to `maxToolRounds` iterations.
    private func executeToolCalls(from response: String, agent: AgentHeartbeatConfig) async {
        guard let exec = executionService else { return }

        var currentResponse = response
        var totalCommandsRun = 0

        for round in 1...Self.maxToolRounds {
            let commands = Self.extractBashCommands(from: currentResponse)
            guard !commands.isEmpty else { break }  // No more commands — done

            await MainActor.run {
                self.roster?.setState(
                    id: agent.id, state: .working,
                    detail: "Round \(round): executing \(commands.count) command(s)…"
                )
            }

            // Execute commands with authorization
            var results: [(command: String, result: ShellCommandResult)] = []
            let allowedTools = ToolRegistry.allowedTools(forAgentId: agent.id)

            for command in commands {
                guard let toolId = ToolRegistry.authorize(command: command, allowedToolIds: allowedTools) else {
                    FlightRecorder.logEvent(
                        category: "tool",
                        action: "denied",
                        detail: "\(agent.id): \(String(command.prefix(120)))",
                        metadata: ["allowed": allowedTools.joined(separator: ",")]
                    )
                    let denied = ShellCommandResult(
                        exitCode: 126,
                        stdout: "",
                        stderr: "Tool denied: command does not match any tool in your allowed set [\(allowedTools.joined(separator: ", "))]. " +
                                "Rewrite the command to use an authorized tool, or ask Thrawn to grant you a broader capability."
                    )
                    results.append((command, denied))
                    continue
                }

                FlightRecorder.logEvent(
                    category: "tool",
                    action: "invoke",
                    detail: "\(agent.id) [\(toolId)] r\(round): \(String(command.prefix(120)))"
                )

                let result = await exec.run(command, agentId: agent.id)
                results.append((command, result))
                totalCommandsRun += 1
            }

            // Build feedback message
            var feedback = "## Command Execution Results (Round \(round))\n\n"
            for (i, entry) in results.enumerated() {
                feedback += "### Command \(i + 1): `\(entry.command.prefix(80))`\n"
                feedback += "Exit code: \(entry.result.exitCode)\n"
                if !entry.result.stdout.isEmpty {
                    feedback += "```\n\(String(entry.result.stdout.prefix(2000)))\n```\n"
                }
                if !entry.result.stderr.isEmpty {
                    feedback += "Stderr: \(String(entry.result.stderr.prefix(500)))\n"
                }
                feedback += "\n"
            }

            let remainingRounds = Self.maxToolRounds - round
            let continuePrompt: String
            if remainingRounds > 0 {
                continuePrompt = """
                You are \(agent.name). You are working autonomously on your assigned tasks.

                Above are the results of commands you just ran (round \(round) of max \(Self.maxToolRounds)).

                CONTINUE WORKING. You have \(remainingRounds) round(s) remaining.
                - If you still have work to do, output more ```bash commands to continue.
                - If your work is complete, write your task-board updates and provide a final summary with NO bash fences.
                - If you're blocked, explain why — do NOT loop on the same failing command.

                Remember: write your updates to YOUR dedicated file (the path was in your heartbeat preamble).
                """
            } else {
                continuePrompt = """
                You are \(agent.name). This was your final round (\(round)/\(Self.maxToolRounds)).
                Summarize what you accomplished and any remaining work. Do NOT output any more bash commands.
                """
            }

            let sessionKey = "agent:toolresult:\(agent.id)"

            // Send results back and get next response
            var nextResponse = ""
            var gotResponse = false

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.sendToActiveProvider(
                    agentId: agent.id,
                    text: feedback,
                    systemPrompt: continuePrompt,
                    sessionKey: sessionKey,
                    onDelta: { delta in nextResponse += delta },
                    onComplete: { response, _ in
                        nextResponse = response
                        gotResponse = true
                        continuation.resume()
                    },
                    onError: { error in
                        FlightRecorder.logError(
                            source: "toolloop:\(agent.id)",
                            message: "Round \(round) feedback error: \(error)"
                        )
                        continuation.resume()
                    }
                )
            }

            guard gotResponse else { break }  // LLM error — stop loop

            currentResponse = nextResponse

            // Log the agent's intermediate response
            FlightRecorder.logHeartbeat(
                agent: agent.id, event: "tool-round-\(round)",
                detail: String(nextResponse.prefix(150))
            )
        }

        // Write the final response (last LLM output) as the agent's output
        if currentResponse != response {
            self.writeAgentOutput(agent: agent, response: currentResponse, durationMs: 0)
        }

        FlightRecorder.logEvent(
            category: "tool",
            action: "loop-complete",
            detail: "\(agent.id): \(totalCommandsRun) commands across loop"
        )
    }

    /// Extract bash commands from ```bash code fences in agent response.
    static func extractBashCommands(from text: String) -> [String] {
        var commands: [String] = []
        let pattern = "```(?:bash|shell|sh|exec)\\s*\\n([\\s\\S]*?)\\n```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return commands
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        for match in matches {
            if match.numberOfRanges > 1,
               let cmdRange = Range(match.range(at: 1), in: text) {
                let command = String(text[cmdRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !command.isEmpty {
                    commands.append(command)
                }
            }
        }

        return commands
    }

    // MARK: - Write Agent Output

    private func writeAgentOutput(agent: AgentHeartbeatConfig, response: String, durationMs: Int) {
        let outputDir = ThrawnPaths.opsDir.appendingPathComponent("agent-output")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let outputPath = outputDir.appendingPathComponent(agent.outputFile)

        let output: [String: Any] = [
            "agent": agent.id,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "durationMs": durationMs,
            "status": "ok",
            "summary": String(response.prefix(500))
        ]

        if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted]) {
            try? data.write(to: outputPath, options: .atomic)
        }
    }

    // MARK: - Persistence

    private static func loadConfig() -> [AgentHeartbeatConfig]? {
        guard let data = try? Data(contentsOf: configPath) else { return nil }
        return try? JSONDecoder().decode([AgentHeartbeatConfig].self, from: data)
    }

    func saveConfig() {
        let dir = Self.configPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(agents) {
            try? data.write(to: Self.configPath, options: .atomic)
        }
    }
}
