import Foundation
import SwiftUI

// MARK: - Native Agent Scheduler
//
// Replaces the external cron system with in-app Swift timers.
// Each agent has a heartbeat interval. When it fires, the scheduler
// sends the agent's heartbeat prompt to the Anthropic API via
// an isolated conversation and tracks the result.
//
// App Store compliant — no Process(), no cron, no external dependencies.

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
    private weak var anthropicClient: AnthropicClient?
    private weak var roster: AgentRosterStore?

    private static let configPath = ThrawnPaths.appSupportDir
        .appendingPathComponent("agent-scheduler.json")

    static let defaultAgents: [AgentHeartbeatConfig] = [
        AgentHeartbeatConfig(id: "thrawn",  name: "Thrawn",   minuteOffset: 0,  heartbeatFile: "thrawn.HEARTBEAT.md",           agentFile: "thrawn.md",  outputFile: "thrawn.json",  enabled: true),
        AgentHeartbeatConfig(id: "r2d2",    name: "R2-D2",    minuteOffset: 10, heartbeatFile: "r2d2.HEARTBEAT.md",             agentFile: "r2d2.md",    outputFile: "r2d2.json",    enabled: true),
        AgentHeartbeatConfig(id: "c3po",    name: "C-3PO",    minuteOffset: 20, heartbeatFile: "c3po.HEARTBEAT.md",             agentFile: "c3po.md",    outputFile: "c3po.json",    enabled: true),
        AgentHeartbeatConfig(id: "quigon",  name: "Qui-Gon",  minuteOffset: 30, heartbeatFile: "quigon.HEARTBEAT.md",           agentFile: "quigon.md",  outputFile: "quigon.json",  enabled: true),
        AgentHeartbeatConfig(id: "lando",   name: "Lando",    minuteOffset: 40, heartbeatFile: "lando.HEARTBEAT.md",            agentFile: "lando.md",   outputFile: "lando.json",   enabled: true),
        AgentHeartbeatConfig(id: "boba",    name: "Boba",     minuteOffset: 50, heartbeatFile: "boba.HEARTBEAT.md",             agentFile: "boba.md",    outputFile: "boba.json",    enabled: true),
    ]

    init() {
        self.agents = Self.loadConfig() ?? Self.defaultAgents
    }

    // MARK: - Binding

    func bind(client: AnthropicClient, roster: AgentRosterStore) {
        self.anthropicClient = client
        self.roster = roster
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

    // MARK: - Tick (runs every 30s)

    private func tick() async {
        let now = Date()
        let calendar = Calendar.current
        let currentMinute = calendar.component(.minute, from: now)

        for agent in agents where agent.enabled {
            // Should this agent fire now?
            guard currentMinute == agent.minuteOffset else { continue }

            // Don't fire if already running
            guard !runningAgents.contains(agent.id) else { continue }

            // Don't fire if we already ran this hour
            if let lastRun = lastRunTimes[agent.id] {
                let minutesSinceLastRun = now.timeIntervalSince(lastRun) / 60
                guard minutesSinceLastRun > 50 else { continue }  // At least 50 min gap
            }

            runHeartbeat(for: agent)
        }
    }

    // MARK: - Execute Heartbeat

    private func runHeartbeat(for agent: AgentHeartbeatConfig) {
        guard let client = anthropicClient else { return }
        guard !runningAgents.contains(agent.id) else { return }

        runningAgents.insert(agent.id)
        roster?.setState(id: agent.id, state: .working, detail: "Heartbeat running…")

        let task = Task { [weak self] in
            guard let self else { return }

            let startTime = Date()

            // Build the heartbeat prompt from files
            let prompt = self.buildHeartbeatPrompt(for: agent)

            guard !prompt.isEmpty else {
                await MainActor.run {
                    self.runningAgents.remove(agent.id)
                    self.lastRunResults[agent.id] = "No heartbeat file found"
                    self.roster?.setState(id: agent.id, state: .idle, detail: "No heartbeat config")
                }
                return
            }

            // Send to Anthropic API (isolated conversation — no history)
            var responseText = ""
            var completed = false
            var errorMsg: String?

            // Use a semaphore-like pattern with continuation
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                client.send(
                    text: prompt,
                    history: [],
                    systemPrompt: "You are \(agent.name), a specialist AI agent. Execute your heartbeat instructions precisely. Work autonomously.",
                    sessionKey: "agent:heartbeat:\(agent.id)",
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
                    let summary = String(responseText.prefix(200))
                    self.lastRunResults[agent.id] = summary

                    // Write output to agent's output file
                    self.writeAgentOutput(agent: agent, response: responseText, durationMs: Int(duration * 1000))

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
                    self.lastRunResults[agent.id] = "Error: \(errorMsg ?? "unknown")"
                    self.roster?.setState(id: agent.id, state: .blocked, detail: errorMsg ?? "Heartbeat failed")
                }

                self.activeRuns.removeValue(forKey: agent.id)
            }
        }

        activeRuns[agent.id] = task
    }

    // MARK: - Build Prompt from Heartbeat Files

    private func buildHeartbeatPrompt(for agent: AgentHeartbeatConfig) -> String {
        let fm = FileManager.default
        let opsDir = ThrawnPaths.opsDir
        let home = fm.homeDirectoryForCurrentUser

        var sections: [String] = []

        // 1. Read heartbeat instructions
        let heartbeatPath = opsDir.appendingPathComponent("heartbeats/\(agent.heartbeatFile)")
        if let content = try? String(contentsOf: heartbeatPath, encoding: .utf8) {
            sections.append("## Your Heartbeat Instructions\n\n\(content)")
        }

        // 2. Read agent operating contract
        let agentDir = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/agents")
        let agentPath = agentDir.appendingPathComponent(agent.agentFile)
        if let content = try? String(contentsOf: agentPath, encoding: .utf8) {
            sections.append("## Your Operating Contract\n\n\(content)")
        }

        // 3. Read task board
        let taskBoardPath = opsDir.appendingPathComponent("TASK_BOARD.md")
        if let content = try? String(contentsOf: taskBoardPath, encoding: .utf8) {
            sections.append("## Current Task Board\n\n\(content)")
        }

        if sections.isEmpty { return "" }

        let preamble = """
        You are \(agent.name), part of the NDAI multi-agent team.

        On this heartbeat:
        1. Read your instructions below carefully
        2. Check the task board for tasks assigned to you
        3. Work on any task with Status: In Progress and Owner: \(agent.name)
        4. Follow your heartbeat instructions precisely

        CRITICAL: Write your status updates as JSON to your output file.
        The dispatcher handles all board updates automatically.

        Work autonomously. All context is below.

        ---

        """

        return preamble + sections.joined(separator: "\n\n---\n\n")
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
