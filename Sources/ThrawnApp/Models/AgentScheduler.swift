import Foundation
import SwiftUI

// MARK: - Native Agent Scheduler
//
// Replaces the external cron system with in-app Swift timers.
// Each agent has a heartbeat interval. When it fires, the scheduler
// sends the agent's heartbeat prompt through the active provider route and
// tracks the result.
//
// Agents execute shell commands via ExecutionService, creating a real agentic loop.

struct AgentHeartbeatConfig: Identifiable, Codable {
    let id: String              // Agent ID: "thrawn", future stable subagent ids.
    let name: String            // Display name
    let minuteOffset: Int       // Minute of the hour to fire (0-59)
    let heartbeatFile: String   // e.g. "thrawn.HEARTBEAT.md"
    let agentFile: String       // e.g. "thrawn.md"
    let outputFile: String      // e.g. "thrawn.json"
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
    private var activeRunStarts: [String: Date] = [:]
    /// Tool-loop tasks spawned AFTER the main heartbeat call returns. Tracked
    /// separately so they can be cancelled cleanly on stop() — otherwise they
    /// could outlive the main heartbeat task and leak commands during shutdown.
    private var toolLoopTasks: [String: Task<Void, Never>] = [:]
    private weak var openaiClient: OpenAIClient?
    private weak var openClawClient: GatewayWSClient?
    private weak var agentRuntime: AgentRuntimeCoordinator?
    private weak var roster: AgentRosterStore?
    private weak var executionService: ExecutionService?
    private weak var objectiveStore: ObjectiveStore?
    private weak var handoffStore: HandoffStore?
    private weak var specStore: AgentSpecStore?
    private weak var devOpsBrain: DevOpsBrainStore?
    private var providerRouter: ProviderRouter?

    /// Briefing service — wired after startup so the scheduler can fire
    /// SOD at 07:00 and EOD at 19:00 without needing a separate cron.
    private weak var briefingService: BriefingService?

    /// Voice service — wired after startup so each heartbeat can speak
    /// an opening and closing line through AVSpeechSynthesizer.
    private weak var voiceService: VoiceService?

    private static let configPath = ThrawnPaths.appSupportDir
        .appendingPathComponent("agent-scheduler.json")

    /// Where last-run timestamps persist. Survives app restarts so the
    /// minGap check still applies after a relaunch — without this, an agent
    /// that just ran could fire again seconds later if the app crashed and
    /// the user reopened it during the same minute window.
    private static let lastRunPath = ThrawnPaths.appSupportDir
        .appendingPathComponent("agent-last-runs.json")

    static let defaultAgents: [AgentHeartbeatConfig] = [
        AgentHeartbeatConfig(id: "thrawn",       name: "Thrawn",   minuteOffset: 0,  heartbeatFile: "thrawn.HEARTBEAT.md",           agentFile: "thrawn.md",  outputFile: "thrawn.json",       enabled: true),
        AgentHeartbeatConfig(id: "sentinel",     name: "Sir Davos", minuteOffset: 10, heartbeatFile: "sentinel.HEARTBEAT.md",         agentFile: "sentinel.md", outputFile: "sentinel.json",     enabled: true),
        AgentHeartbeatConfig(id: "dwight",       name: "Dwight",   minuteOffset: 30, heartbeatFile: "dwight.HEARTBEAT.md",           agentFile: "dwight.md",  outputFile: "dwight.json",       enabled: true),
        AgentHeartbeatConfig(id: "steven",       name: "Steven",   minuteOffset: 40, heartbeatFile: "steven.HEARTBEAT.md",           agentFile: "steven.md",  outputFile: "steven.json",       enabled: true),
        AgentHeartbeatConfig(id: "archivist",    name: "Samwell Tarly", minuteOffset: 55, heartbeatFile: "archivist.HEARTBEAT.md",  agentFile: "archivist.md", outputFile: "archivist.json",    enabled: true),
    ]

    init() {
        self.agents = Self.loadConfig() ?? Self.defaultAgents
        self.lastRunTimes = Self.loadLastRuns()
        saveConfig()
    }

    // MARK: - Binding

    func bind(
        ollamaClient: OllamaClient,
        roster: AgentRosterStore,
        execution: ExecutionService? = nil,
        objectives: ObjectiveStore? = nil,
        handoffs: HandoffStore? = nil,
        specs: AgentSpecStore? = nil,
        devOpsBrain: DevOpsBrainStore? = nil,
        openclaw: GatewayWSClient? = nil,
        openai: OpenAIClient? = nil,
        agentRuntime: AgentRuntimeCoordinator? = nil
    ) {
        self.openaiClient = openai
        self.openClawClient = openclaw
        self.agentRuntime = agentRuntime
        self.roster = roster
        self.executionService = execution
        self.objectiveStore = objectives
        self.handoffStore = handoffs
        self.specStore = specs
        self.devOpsBrain = devOpsBrain
        self.providerRouter = ProviderRouter(ollama: ollamaClient, openai: openai)
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

        // Reliability rule: fail loudly at startup, not silently later.
        // Verify every directory the scheduler/dispatcher will touch is
        // present AND writable. Continues even on partial failure since
        // some agents may still be functional, but the failures are logged
        // loud and clear via FlightRecorder.
        let report = ThrawnPaths.verifyOpsDirectories()
        if !report.allGood {
            FlightRecorder.logError(
                source: "scheduler:start",
                message: "Starting scheduler with integrity issues: \(report.summary)"
            )
        }

        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                // Check every 30 seconds
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    func stop() {
        let sessionsToCancel = runningAgents.map { "agent:heartbeat:\($0)" }
        Task { [weak agentRuntime] in
            for sessionKey in sessionsToCancel {
                await agentRuntime?.cancel(sessionKey: sessionKey)
            }
        }
        timerTask?.cancel()
        timerTask = nil
        for task in activeRuns.values { task.cancel() }
        activeRuns.removeAll()
        activeRunStarts.removeAll()
        // Cancel any in-flight tool loops that might be running after the
        // main heartbeat returned. Without this, shell commands could keep
        // executing after the user stopped the scheduler.
        for task in toolLoopTasks.values { task.cancel() }
        toolLoopTasks.removeAll()
        runningAgents.removeAll()
    }

    func resetToV2Defaults() {
        stop()
        agents = Self.defaultAgents
        lastRunTimes = [:]
        lastRunResults = [:]
        saveConfig()
        saveLastRuns()
    }

    // MARK: - Manual Trigger

    func triggerAgent(_ agentId: String) {
        guard let config = agents.first(where: { $0.id == agentId }) else { return }
        runHeartbeat(for: config)
    }

    func upsertConfig(_ config: AgentHeartbeatConfig) {
        if let index = agents.firstIndex(where: { $0.id == config.id }) {
            agents[index] = config
        } else {
            agents.append(config)
        }
        saveConfig()
    }

    /// Manually trigger a handoff (morning or evening) right now.
    /// Used by the flow board drag-drop trigger and the Handoffs view button.
    func triggerHandoff(kind: HandoffKind) {
        guard let store = handoffStore else { return }
        store.generate(kind: kind)
    }

    // MARK: - Tick (runs every 30s)

    private func tick() async {
        let now = Date()
        let calendar = Calendar.current
        let currentMinute = calendar.component(.minute, from: now)
        let currentHour = calendar.component(.hour, from: now)

        reapStaleRuns(now: now)

        // .blocked stays visible until a run actually succeeds. The fire
        // decision below never consults roster state, so blocked agents
        // still retry on their next slot — erasing the state every tick
        // only hid five hours of total fleet failure behind "Standing by".

        autoDelegateNamedSpecialistTasks()

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

            // Thrawn fires every 15 minutes. Explicit subagents use their
            // configured hourly minute offset, but fresh Ready work assigned
            // after their last run wakes them promptly.
            let scheduledFire: Bool
            let scheduledMinGap: Double

            if agent.id == "thrawn" {
                scheduledFire = currentMinute % 15 == 0
                scheduledMinGap = 12
            } else {
                scheduledFire = currentMinute == agent.minuteOffset
                scheduledMinGap = 50
            }

            let readyWorkFire = hasFreshReadyWork(for: agent)
            guard scheduledFire || readyWorkFire else { continue }

            if let lastRun = lastRunTimes[agent.id] {
                let minutesSinceLastRun = now.timeIntervalSince(lastRun) / 60
                let minGap = readyWorkFire ? Self.readyWorkMinGapMinutes : scheduledMinGap
                guard minutesSinceLastRun > minGap else { continue }
            }

            runHeartbeat(for: agent)
        }
    }

    private static let readyWorkMinGapMinutes: Double = 2

    private func hasFreshReadyWork(for agent: AgentHeartbeatConfig) -> Bool {
        let boardURL = ThrawnPaths.opsDir.appendingPathComponent("TASK_BOARD.md")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: boardURL.path),
              let boardModifiedAt = attrs[.modificationDate] as? Date else {
            return false
        }
        if let lastRun = lastRunTimes[agent.id],
           boardModifiedAt <= lastRun.addingTimeInterval(1) {
            return false
        }
        guard let content = try? String(contentsOf: boardURL, encoding: .utf8) else {
            return false
        }
        return parseTaskBoard(from: content).contains { task in
            isReadyStatus(task.status) && ownerMatches(task.owner, agent: agent)
        }
    }

    private func hasAssignedReadyTask(for agent: AgentHeartbeatConfig) -> Bool {
        let boardURL = ThrawnPaths.opsDir.appendingPathComponent("TASK_BOARD.md")
        guard let content = try? String(contentsOf: boardURL, encoding: .utf8) else {
            return false
        }
        return parseTaskBoard(from: content).contains { task in
            isReadyStatus(task.status) && ownerMatches(task.owner, agent: agent)
        }
    }

    private func autoDelegateNamedSpecialistTasks() {
        let boardURL = ThrawnPaths.opsDir.appendingPathComponent("TASK_BOARD.md")
        let lockURL = ThrawnPaths.opsDir.appendingPathComponent("TASK_BOARD.md.lock")
        FileLock.withLock(at: lockURL, source: "scheduler:autoDelegate") {
            guard let content = try? String(contentsOf: boardURL, encoding: .utf8) else { return }
            var tasks = parseTaskBoard(from: content)
            guard !tasks.isEmpty else { return }

            var changedTasks: [String] = []
            for index in tasks.indices {
                let task = tasks[index]
                guard isReadyStatus(task.status),
                      ownerMatchesThrawn(task.owner),
                      let target = namedSpecialistTarget(in: task) else {
                    continue
                }

                tasks[index].owner = target.owner
                tasks[index].status = "Ready"
                if tasks[index].nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    tasks[index].nextStep = "\(target.owner): pull this task, produce the requested deliverable, and route findings back to Thrawn for review."
                }
                if tasks[index].notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    tasks[index].notes = "Auto-routed because the Thrawn-owned request explicitly named \(target.owner)."
                }
                changedTasks.append("\(task.id)->\(target.owner)")
            }

            guard !changedTasks.isEmpty else { return }
            let markdown = serializeTaskBoard(tasks, preservingHeaderFrom: content)
            do {
                try markdown.write(to: boardURL, atomically: true, encoding: .utf8)
                FlightRecorder.logEvent(
                    category: "scheduler",
                    action: "auto-delegate",
                    detail: changedTasks.joined(separator: ", ")
                )
            } catch {
                FlightRecorder.logError(
                    source: "scheduler:autoDelegate",
                    message: "Could not write TASK_BOARD.md: \(error.localizedDescription)"
                )
            }
        }
    }

    private func isReadyStatus(_ status: String) -> Bool {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "ready"
    }

    private func ownerMatchesThrawn(_ owner: String) -> Bool {
        let normalized = owner.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "thrawn"
    }

    private func ownerMatches(_ owner: String, agent: AgentHeartbeatConfig) -> Bool {
        let normalized = owner.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let aliases = ownerAliases(for: agent)
        return aliases.contains(normalized)
    }

    private func ownerAliases(for agent: AgentHeartbeatConfig) -> Set<String> {
        switch agent.id {
        case "thrawn":
            return ["thrawn"]
        case "archivist":
            return ["archivist", "samwell", "samwell tarly"]
        case "sentinel":
            return ["sentinel", "sir davos", "davos"]
        case "dwight":
            return ["dwight"]
        case "steven":
            return ["steven"]
        default:
            return [agent.id.lowercased(), agent.name.lowercased()]
        }
    }

    private func namedSpecialistTarget(in task: ParsedTask) -> (id: String, owner: String)? {
        let text = [
            task.title,
            task.nextStep,
            task.notes,
            task.blockers,
            task.deliverable,
        ].joined(separator: " ").lowercased()

        let targets: [(id: String, owner: String, needles: [String])] = [
            ("steven", "Steven", ["steven"]),
            ("archivist", "Samwell Tarly", ["samwell", "samwell tarly", "archivist"]),
            ("sentinel", "Sir Davos", ["sir davos", "davos", "sentinel"]),
            ("dwight", "Dwight", ["dwight"]),
        ]
        return targets.first { target in
            target.needles.contains { text.contains($0) }
        }.map { ($0.id, $0.owner) }
    }

    // MARK: - Execute Heartbeat

    private func runHeartbeat(for agent: AgentHeartbeatConfig) {
        guard !runningAgents.contains(agent.id) else { return }

        runningAgents.insert(agent.id)
        activeRunStarts[agent.id] = Date()
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

            // Continuation with watchdog timeout. Reliability rule: a heartbeat
            // must NEVER hang forever — if the provider stops responding without
            // calling onComplete or onError (network stall, broken stream, etc.),
            // the watchdog forces an error after the cap. Both the success/error
            // callbacks and the watchdog go through a single-resume guard so the
            // continuation can only resume exactly once.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                var resumed = false
                let resumeOnce: () -> Void = {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume()
                }

                // Watchdog task — fires after the heartbeat cap.
                let watchdog = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: Self.heartbeatWatchdogNs)
                    guard !Task.isCancelled, !resumed else { return }
                    let msg = "Heartbeat exceeded \(Self.heartbeatWatchdogSeconds)s watchdog"
                    FlightRecorder.logError(source: "scheduler:\(agent.id)", message: msg)
                    errorMsg = msg
                    Task { [weak agentRuntime = self.agentRuntime] in
                        await agentRuntime?.cancel(sessionKey: sessionKey)
                    }
                    resumeOnce()
                }

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
                        watchdog.cancel()
                        resumeOnce()
                    },
                    onError: { error in
                        errorMsg = error
                        watchdog.cancel()
                        resumeOnce()
                    }
                )
            }

            let duration = Date().timeIntervalSince(startTime)

            await MainActor.run {
                self.runningAgents.remove(agent.id)
                self.lastRunTimes[agent.id] = startTime
                self.saveLastRuns()

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
                    if responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       self.hasAssignedReadyTask(for: agent) {
                        let errDetail = "Heartbeat returned only a voice line while Ready tasks were assigned."
                        self.lastRunResults[agent.id] = "Error: \(errDetail)"
                        FlightRecorder.logHeartbeat(
                            agent: agent.id, event: "error",
                            durationMs: durationMs,
                            detail: errDetail
                        )
                        FlightRecorder.logError(source: "heartbeat:\(agent.id)", message: errDetail)
                        self.writeAgentOutput(agent: agent, response: "⚠️ \(errDetail)", durationMs: durationMs)
                        self.roster?.setState(id: agent.id, state: .blocked, detail: errDetail)
                        self.activeRuns.removeValue(forKey: agent.id)
                        self.activeRunStarts.removeValue(forKey: agent.id)
                        return
                    }

                    let summary = String(responseText.prefix(200))
                    self.lastRunResults[agent.id] = summary

                    FlightRecorder.logHeartbeat(
                        agent: agent.id, event: "complete",
                        durationMs: durationMs,
                        detail: String(responseText.prefix(150))
                    )

                    // Write output to agent's output file
                    self.writeAgentOutput(agent: agent, response: responseText, durationMs: durationMs)

                    // Subscription agent runtimes execute tools natively and
                    // surface provider events/approvals. The legacy fenced-bash
                    // harness remains only for explicit non-agent API routes.
                    let nativeGateway = self.specStore?
                        .spec(id: agent.id)?
                        .modelOverride?
                        .provider
                        .isSubscriptionGateway == true
                    if self.executionService != nil, !nativeGateway {
                        let agentId = agent.id
                        let prior = self.toolLoopTasks[agentId]
                        prior?.cancel()
                        let toolTask = Task { [weak self] in
                            guard let self else { return }
                            await self.executeToolCalls(from: responseText, agent: agent)
                            await MainActor.run { [weak self] in
                                _ = self?.toolLoopTasks.removeValue(forKey: agentId)
                            }
                        }
                        self.toolLoopTasks[agentId] = toolTask
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
                self.activeRunStarts.removeValue(forKey: agent.id)
            }
        }

        activeRuns[agent.id] = task
    }

    private func reapStaleRuns(now: Date) {
        let staleSeconds = Self.heartbeatWatchdogSeconds + Self.toolRoundWatchdogSeconds + 120
        let staleAgentIds = activeRunStarts.compactMap { agentId, startedAt in
            now.timeIntervalSince(startedAt) > Double(staleSeconds) ? agentId : nil
        }
        for agentId in staleAgentIds {
            activeRuns[agentId]?.cancel()
            activeRuns.removeValue(forKey: agentId)
            toolLoopTasks[agentId]?.cancel()
            toolLoopTasks.removeValue(forKey: agentId)
            runningAgents.remove(agentId)
            activeRunStarts.removeValue(forKey: agentId)
            FlightRecorder.logHeartbeat(
                agent: agentId,
                event: "stale-run-cleared",
                detail: "Cleared scheduler state after \(staleSeconds)s without completion."
            )
            FlightRecorder.logError(
                source: "scheduler:\(agentId)",
                message: "Cleared stale active run after \(staleSeconds)s watchdog."
            )
            roster?.setState(id: agentId, state: .blocked, detail: "Stale run cleared; will retry next window")
        }
    }

    // MARK: - Build Prompt from Heartbeat Files

    private func buildHeartbeatPrompt(for agent: AgentHeartbeatConfig) -> String {
        let opsDir = ThrawnPaths.opsDir
        let boardFile = ThrawnPaths.opsDir.appendingPathComponent("TASK_BOARD.md").path
        let updatesDir = ThrawnPaths.opsDir.appendingPathComponent("pending-updates").path
        let myUpdatesFile = "\(updatesDir)/updates-\(agent.id).json"

        var sections: [String] = []

        // 1. Read task board FIRST — this is what agents need most.
        let taskBoardPath = opsDir.appendingPathComponent("TASK_BOARD.md")
        if let content = try? String(contentsOf: taskBoardPath, encoding: .utf8) {
            sections.append("## TASK BOARD\n\n\(content)")
        }

        // 2. Read heartbeat instructions
        let heartbeatPath = opsDir.appendingPathComponent("heartbeats/\(agent.heartbeatFile)")
        if let content = try? String(contentsOf: heartbeatPath, encoding: .utf8) {
            sections.append("## Your Heartbeat Instructions\n\n\(content)")
        }

        // 3. Read agent operating contract.
        let agentDir = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/agents")
        let agentPath = agentDir.appendingPathComponent(agent.agentFile)
        if let content = try? String(contentsOf: agentPath, encoding: .utf8) {
            sections.append("## Your Operating Contract\n\n\(content)")
        }

        // 4. Autonomy ceiling — Andrew's per-agent permission ladder (gear on
        // the agent card). Hard limits for this wake; always injected.
        sections.append(AgentAutonomyStore.promptBlock(forAgentId: agent.id))

        // Auth-gated browser work should use the provider agent's supported
        // browser/Chrome integration and Andrew's existing signed-in session.
        sections.append("""
        ## Authenticated Browser Route

        When a task depends on Andrew's existing login, use the available Browser or Chrome integration tied to his real session. Never work around a login wall with a separate anonymous profile. If the signed-in browser cannot attach, record the exact blocker and leave the gated action untouched.
        """)

        // 5. Objectives context (Thrawn agents only)
        if agent.id.hasPrefix("thrawn"), let objContext = objectiveStore?.heartbeatContext() {
            sections.append(objContext)
        }

        // 6. Spec-driven identity (brief — just name, role, persona)
        if let spec = specStore?.spec(id: agent.id) {
            var identity = "## Identity\n\n"
            identity += "**\(spec.name)** — \(spec.role). \(spec.persona)\n"
            if let override = spec.modelOverride {
                identity += "Rank: \(spec.rank.displayName) • Effective route: \(override.provider.rawValue) \(override.model)"
                if let effort = override.reasoningEffort {
                    identity += ", \(effort) reasoning"
                }
            } else {
                identity += "Rank: \(spec.rank.displayName) • Effective route: Codex subscription, live model discovery"
            }
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

        // Tool preamble — tight, directive, no fluff.
        let toolsBlock = ToolRegistry.renderAvailableToolsBlock(forAgentId: agent.id)
        let toolsLine = "MODE: FULL OPERATION. \(toolsBlock)"

        let procedure: String
        if agent.id == "thrawn" {
            procedure = """
            PROCEDURE — follow this EXACTLY:
            1. OPEN LINE (spoken) — short, in character, states what board pressure you're about to remove.
            2. Treat every non-Done TASK BOARD card as live pressure. First triage cards where Owner = Thrawn in any lane, then Inbox, Blocked, Review, and stale Ready cards.
            3. For every Thrawn-owned non-Done card, do one of these before the wake ends:
               - Execute or unblock internal operational work yourself, especially local dependency installs, scheduler repair, docs, task-board cleanup, and internal verification.
               - Close reviewed work: publish or confirm a human-readable HTML deliverable under workspace/deliverables/.../index.html, set Deliverable to that index.html path, and set Status = Done only when the review note is present.
               - If reviewing exposes a blocker, change Status from Review to Blocked immediately. Record the exact blocker and smallest next action so the card turns red on the Review lane.
               - Keep Blocked only when the next action is impossible with local tools. Write the exact missing input and the smallest next action.
            4. If a card says "Authorize" but the action is local/internal and reversible, treat that as already within Thrawn's operating authority. Rename/reframe through Notes/Next step if useful; do not leave it waiting on Andrew.
            5. Write all board changes to `\(myUpdatesFile)` as one JSON array before your close line.
            6. Do NOT reply HEARTBEAT_OK while any Owner = Thrawn non-Done card remains without a fresh delegation, execution update, Done review, or concrete missing-input Blocked reason.
            7. CLOSE LINE (spoken) — short, in character, states what you delegated, unblocked, or closed.

            Thrawn success means the board got smaller, clearer, or moving. A passive board wake is failed.
            """
        } else {
            procedure = """
            PROCEDURE — follow this EXACTLY:
            1. OPEN LINE (spoken) — short, in character, states what you're about to do.
            2. Look at the TASK BOARD below. Find tasks where Owner = \(agent.name) AND Status = Ready.
            3. If any Ready task is assigned to you, do not stop after the open line, do not reply HEARTBEAT_OK, and do not return a voice-only response.
            4. DO THE ACTUAL WORK for each assigned task (write code, produce deliverables, run commands). For research tasks, use available local/network tools through bash or Python and create a polished source-backed artifact.
            5. When you produce a handoff artifact, publish a human-readable HTML page at workspace/deliverables/<ticket>/<date>/<slug>/index.html and register it in workspace/deliverables/manifest.json. If PDF is requested, also create a PDF beside the HTML when local tooling supports it.
            6. When done, write your updates:
               ```bash
               echo '[{"action":"move","task_id":"TASK-XXX","field":"Owner","value":"Thrawn","agent":"\(agent.name)"},{"action":"move","task_id":"TASK-XXX","field":"Status","value":"Ready","agent":"\(agent.name)"},{"action":"update","task_id":"TASK-XXX","field":"Notes","value":"What you did","agent":"\(agent.name)"}]' > '\(myUpdatesFile)'
               ```
            7. If a task cannot be completed in this wake, still write an update marking Status = Blocked or In Progress with the exact blocker/next step. If a Review task becomes blocked, change its Status from Review to Blocked immediately so the board shows the red blocker state. A voice-only "starting now" reply is invalid.
            8. If no tasks are assigned to you, reply HEARTBEAT_OK on its own line and still emit the open+close spoken lines.
            9. CLOSE LINE (spoken) — short, in character, states what you accomplished.
            """
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
        • If you have an assigned Ready task, the response must contain actionable body content between the open and close lines.

        \(procedure)

        DO NOT spend rounds reading directories or exploring. The task board and context are RIGHT BELOW. Go straight to work.

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

        if let firstIdx, firstIdx == lastIdx {
            return (open, nil, text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

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
    // await the final text. Routing is handled upstream by the provider
    // router exactly like heartbeats.

    /// Fire a single prompt at an agent and return the full response text.
    /// Returns nil on failure so the caller can skip without blowing up.
    /// Watchdog-protected with a briefing-sized cap. A single stalled provider
    /// must not hold the entire five-agent SOD/EOD run for fifteen minutes.
    func sendOneShot(
        agentId: String,
        prompt: String,
        systemPrompt: String?,
        sessionKey: String? = nil
    ) async -> String? {
        let key = sessionKey ?? "oneshot-\(agentId)-\(Int(Date().timeIntervalSince1970))"
        let responses = AsyncStream<String> { continuation in
            // Watchdog — if the provider stalls, return nil so callers move on.
            let watchdog = DispatchWorkItem {
                FlightRecorder.logError(
                    source: "oneshot:\(agentId)",
                    message: "sendOneShot exceeded \(Self.oneShotWatchdogSeconds)s watchdog"
                )
                continuation.yield("")
                continuation.finish()
            }
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + .seconds(Self.oneShotWatchdogSeconds),
                execute: watchdog
            )

            sendToActiveProvider(
                agentId: agentId,
                text: prompt,
                systemPrompt: systemPrompt,
                sessionKey: key,
                onDelta: { _ in },
                onComplete: { full, _ in
                    watchdog.cancel()
                    continuation.yield(full)
                    continuation.finish()
                },
                onError: { err in
                    FlightRecorder.logEvent(
                        category: "briefing", action: "oneshot-error",
                        detail: "\(agentId): \(err)"
                    )
                    watchdog.cancel()
                    continuation.yield("")
                    continuation.finish()
                }
            )
        }
        let response = await responses.first(where: { _ in true }) ?? ""
        return response.isEmpty ? nil : response
    }

    // MARK: - Provider-Aware Send

    /// Route a send request through the resolved agent model.
    /// Standard model for all agent heartbeats
    nonisolated static let agentModel = ProviderRouter.dynamicCodexModel

    private func sendToActiveProvider(
        agentId: String,
        text: String,
        systemPrompt: String?,
        sessionKey: String,
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String, String?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        let route: RoutedProvider
        if let override = specStore?.spec(id: agentId)?.modelOverride {
            route = RoutedProvider(
                backend: override.provider,
                model: override.model,
                isFallback: false,
                reasoningEffort: override.reasoningEffort,
                allowFallback: override.allowFallback
            )
        } else {
            route = providerRouter?.resolve(tier: .premium)
                ?? ProviderRouter.thrawnCoreRoute(openAIConfigured: openaiClient?.apiKeyConfigured ?? false)
        }

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

        FlightRecorder.logEvent(
            category: "router",
            action: "route",
            detail: "\(agentId) -> \(route.backend.rawValue) \(route.model)",
            metadata: [
                "agent": agentId,
                "model": route.model,
                "reasoning": route.reasoningEffort ?? "",
                "allowFallback": route.allowFallback ? "true" : "false",
                "isFallback": route.isFallback ? "true" : "false"
            ]
        )

        switch route.backend {
        case .codex, .grok, .claude:
            guard let agentRuntime else {
                logFailure(
                    "\(route.backend.gatewayDisplayName) route requested for \(agentId), but the agent runtime is unavailable."
                )
                return
            }
            Task { @MainActor [weak agentRuntime] in
                guard let agentRuntime else {
                    logFailure("Codex agent runtime was released before the turn started.")
                    return
                }
                do {
                    let result = try await agentRuntime.run(
                        prompt: text,
                        options: AgentSessionOptions(
                            sessionKey: sessionKey,
                            agentID: agentId,
                            provider: route.backend,
                            developerInstructions: systemPrompt,
                            model: route.model,
                            reasoningEffort: route.reasoningEffort,
                            approvalPolicy: .onRequest,
                            sandbox: .fullOperation
                        )
                    ) { event in
                        switch event {
                        case .textDelta(let delta):
                            onDelta(delta)
                        case .toolCall(let call):
                            FlightRecorder.logEvent(
                                category: "codex-tool",
                                action: call.status,
                                detail: "\(agentId): \(call.title)"
                            )
                        case .fileChange(let change):
                            FlightRecorder.logEvent(
                                category: "codex-file",
                                action: change.status,
                                detail: "\(agentId): \(change.paths.joined(separator: ", "))"
                            )
                        case .approvalRequired(let approval):
                            self.roster?.setState(
                                id: agentId,
                                state: .blocked,
                                detail: "Approval required: \(approval.title)"
                            )
                        case .error(let detail):
                            FlightRecorder.logError(
                                source: "codex:\(agentId)",
                                message: detail
                            )
                        case .reasoningDelta, .usage, .completed:
                            break
                        }
                    }
                    logSuccess(result.text, result.model)
                } catch {
                    logFailure(error.localizedDescription)
                }
            }

        case .xai:
            if let openai = openaiClient {
                openai.send(
                    text: text,
                    systemPrompt: systemPrompt,
                    sessionKey: sessionKey,
                    modelOverride: route.model,
                    reasoningEffortOverride: route.reasoningEffort,
                    baseURLOverride: ProviderRouter.xaiBaseURL,
                    apiKeyServiceOverride: ProviderRouter.xaiKeychainService,
                    providerLabel: "xAI",
                    includeReasoningControls: false,
                    onDelta: onDelta,
                    onComplete: logSuccess,
                    onError: { error in
                        logFailure(error)
                    }
                )
                return
            }
            logFailure("xAI route requested for \(agentId), but the OpenAI-compatible client is unavailable.")

        case .openclaw:
            if let openClaw = openClawClient {
                // Heartbeats are intentionally isolated conversations. Use the
                // scheduler's per-call session key plus a timestamp so legacy
                // OpenClaw treats each heartbeat/tool round as fresh work.
                let gatewaySessionKey = Self.openClawSessionKey(
                    agentId: agentId,
                    sessionKey: sessionKey
                )
                openClaw.send(
                    text: text,
                    sessionKey: gatewaySessionKey,
                    model: route.model,
                    thinking: route.reasoningEffort ?? ProviderRouter.premiumOpenClawThinkingLevel,
                    onDelta: onDelta,
                    onComplete: logSuccess,
                    onError: { error in
                        logFailure(error)
                    }
                )
                return
            }
            logFailure("Legacy OpenClaw route requested for \(agentId), but the OpenClaw client is unavailable.")

        case .openai:
            if let openai = openaiClient, openai.apiKeyConfigured {
                openai.send(
                    text: text,
                    systemPrompt: systemPrompt,
                    sessionKey: sessionKey,
                    modelOverride: route.model,
                    reasoningEffortOverride: route.reasoningEffort,
                    onDelta: onDelta,
                    onComplete: logSuccess,
                    onError: { error in
                        logFailure(error)
                    }
                )
                return
            }
            logFailure("OpenAI-compatible route required for \(agentId), but no API key is configured.")

        case .ollama:
            logFailure("Legacy Ollama route requested for \(agentId), but normal agent operation requires the configured cloud route.")
        }
    }

    private static func openClawSessionKey(agentId: String, sessionKey: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitizedScalars = sessionKey.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(sanitizedScalars)
        let millis = Int(Date().timeIntervalSince1970 * 1000)
        return "thrawn-agent-\(agentId)-\(sanitized)-\(millis)"
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

    // MARK: - Watchdog timeouts (reliability rule: never hang forever)
    //
    // Every continuation that awaits a provider callback is wrapped with a
    // hard timeout. If the provider stops responding without firing
    // onComplete or onError, the watchdog forces a clean exit so the agent
    // never sits forever in `working` state.

    /// Hard cap on a single heartbeat call (initial prompt + streaming).
    /// 15 minutes lets a slow Ollama generation finish but cuts off true hangs.
    static let heartbeatWatchdogSeconds: Int = 900
    static let heartbeatWatchdogNs: UInt64 = UInt64(heartbeatWatchdogSeconds) * 1_000_000_000

    /// Briefings are short, single-response requests. Keep a failed route from
    /// blocking the remaining agents; BriefingService writes a grounded
    /// fallback when this cap expires.
    static let oneShotWatchdogSeconds: Int = 120

    /// Hard cap on a single tool-loop round (commands + follow-up LLM call).
    /// 5 minutes — most rounds finish in seconds; this catches stuck rounds.
    static let toolRoundWatchdogSeconds: Int = 300
    static let toolRoundWatchdogNs: UInt64 = UInt64(toolRoundWatchdogSeconds) * 1_000_000_000

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

            // Execute command fences in full-operation mode.
            var results: [(command: String, result: ShellCommandResult)] = []
            let allowedTools = ToolRegistry.allowedTools(forAgentId: agent.id)

            for command in commands {
                let toolId = ToolRegistry.authorize(command: command, allowedToolIds: allowedTools) ?? "bash"

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
                - If you're blocked, write a board update with Status = Blocked plus the exact blocker and smallest next action. Do NOT leave a blocked task in Review or loop on the same failing command.

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

            // Watchdog-protected continuation — one round of the tool loop
            // must NEVER hang forever. If the provider stalls, the watchdog
            // forces a clean exit so the agent moves on or terminates.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                var resumed = false
                let resumeOnce: () -> Void = {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume()
                }

                let watchdog = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: Self.toolRoundWatchdogNs)
                    guard !Task.isCancelled, !resumed else { return }
                    FlightRecorder.logError(
                        source: "toolloop:\(agent.id)",
                        message: "Round \(round) exceeded \(Self.toolRoundWatchdogSeconds)s watchdog"
                    )
                    resumeOnce()
                }

                self.sendToActiveProvider(
                    agentId: agent.id,
                    text: feedback,
                    systemPrompt: continuePrompt,
                    sessionKey: sessionKey,
                    onDelta: { delta in nextResponse += delta },
                    onComplete: { response, _ in
                        nextResponse = response
                        gotResponse = true
                        watchdog.cancel()
                        resumeOnce()
                    },
                    onError: { error in
                        FlightRecorder.logError(
                            source: "toolloop:\(agent.id)",
                            message: "Round \(round) feedback error: \(error)"
                        )
                        watchdog.cancel()
                        resumeOnce()
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

        FlightRecorder.logHeartbeat(
            agent: agent.id,
            event: "tool-loop-complete",
            commandsExecuted: totalCommandsRun,
            detail: "\(totalCommandsRun) command(s) executed across tool loop"
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
        let outputPath = outputDir.appendingPathComponent(agent.outputFile)

        // Reliability rule: never silently fail. Every filesystem error is
        // logged through FlightRecorder so disk-full / permission / sandbox
        // problems show up in the operator's diagnostics instead of vanishing.
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } catch {
            FlightRecorder.logError(
                source: "scheduler:writeAgentOutput",
                message: "createDirectory \(outputDir.path) failed: \(error.localizedDescription)"
            )
            return
        }

        // The full response is the record; the summary is the glance. Every
        // run's complete transcript lands under workspace/transcripts/ so the
        // reasoning behind a board move is never unrecoverable again.
        let stamp = ISO8601DateFormatter().string(from: Date())
        var transcriptPath = ""
        let transcriptsDir = ThrawnPaths.appSupportDir
            .appendingPathComponent("workspace/transcripts", isDirectory: true)
            .appendingPathComponent(agent.id, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: transcriptsDir, withIntermediateDirectories: true)
            let fileName = stamp.replacingOccurrences(of: ":", with: "-") + ".md"
            let file = transcriptsDir.appendingPathComponent(fileName)
            let header = "# \(agent.name) heartbeat — \(stamp)\n- duration_ms: \(durationMs)\n\n"
            try (header + response).write(to: file, atomically: true, encoding: .utf8)
            transcriptPath = file.path
        } catch {
            FlightRecorder.logError(
                source: "scheduler:writeTranscript",
                message: "transcript write failed for \(agent.id): \(error.localizedDescription)"
            )
        }

        let output: [String: Any] = [
            "agent": agent.id,
            "timestamp": stamp,
            "durationMs": durationMs,
            "status": "ok",
            "summary": String(response.prefix(500)),
            "transcript": transcriptPath
        ]

        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted])
        } catch {
            FlightRecorder.logError(
                source: "scheduler:writeAgentOutput",
                message: "JSON encode failed for \(agent.id): \(error.localizedDescription)"
            )
            return
        }

        do {
            try data.write(to: outputPath, options: .atomic)
        } catch {
            FlightRecorder.logError(
                source: "scheduler:writeAgentOutput",
                message: "write \(outputPath.path) failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Persistence

    private static func loadConfig() -> [AgentHeartbeatConfig]? {
        guard let data = try? Data(contentsOf: configPath) else { return nil }
        guard let decoded = try? JSONDecoder().decode([AgentHeartbeatConfig].self, from: data) else { return nil }
        let retiredIds: Set<String> = []
        var merged = decoded
            .filter { !retiredIds.contains($0.id) }
            .map(Self.normalizeConfig)
        for def in defaultAgents where !merged.contains(where: { $0.id == def.id }) {
            merged.append(def)
        }
        return merged
    }

    private static func normalizeConfig(_ config: AgentHeartbeatConfig) -> AgentHeartbeatConfig {
        if config.id == "thrawn", config.name != "Thrawn" {
            return AgentHeartbeatConfig(
                id: "thrawn",
                name: "Thrawn",
                minuteOffset: config.minuteOffset,
                heartbeatFile: "thrawn.HEARTBEAT.md",
                agentFile: "thrawn.md",
                outputFile: "thrawn.json",
                enabled: config.enabled
            )
        }
        return config
    }

    /// Load persisted last-run timestamps. Missing or unreadable file is fine —
    /// returns empty dict so a fresh install just acts as if nothing has run yet.
    private static func loadLastRuns() -> [String: Date] {
        guard let data = try? Data(contentsOf: lastRunPath) else { return [:] }
        // Stored as { agentId: epoch_seconds_double }
        guard let dict = try? JSONDecoder().decode([String: Double].self, from: data) else {
            FlightRecorder.logError(
                source: "scheduler:loadLastRuns",
                message: "Could not decode \(lastRunPath.lastPathComponent) — starting with empty last-run history"
            )
            return [:]
        }
        return dict.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private func saveLastRuns() {
        let serializable = lastRunTimes.mapValues { $0.timeIntervalSince1970 }
        let dir = Self.lastRunPath.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            FlightRecorder.logError(
                source: "scheduler:saveLastRuns",
                message: "createDirectory failed: \(error.localizedDescription)"
            )
            return
        }
        do {
            let data = try JSONEncoder().encode(serializable)
            try data.write(to: Self.lastRunPath, options: .atomic)
        } catch {
            FlightRecorder.logError(
                source: "scheduler:saveLastRuns",
                message: "write failed: \(error.localizedDescription)"
            )
        }
    }

    func saveConfig() {
        let dir = Self.configPath.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            FlightRecorder.logError(
                source: "scheduler:saveConfig",
                message: "createDirectory \(dir.path) failed: \(error.localizedDescription)"
            )
            return
        }

        let data: Data
        do {
            data = try JSONEncoder().encode(agents)
        } catch {
            FlightRecorder.logError(
                source: "scheduler:saveConfig",
                message: "JSON encode failed: \(error.localizedDescription)"
            )
            return
        }

        do {
            try data.write(to: Self.configPath, options: .atomic)
        } catch {
            FlightRecorder.logError(
                source: "scheduler:saveConfig",
                message: "write \(Self.configPath.path) failed: \(error.localizedDescription)"
            )
        }
    }
}
