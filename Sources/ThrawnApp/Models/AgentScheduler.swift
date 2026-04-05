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
    private weak var anthropicClient: AnthropicClient?
    private weak var geminiClient: GeminiAPIClient?
    private weak var geminiOAuth: GeminiOAuthClient?
    private weak var openAIClient: OpenAIClient?
    private weak var roster: AgentRosterStore?
    private weak var executionService: ExecutionService?

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

    func bind(client: AnthropicClient, roster: AgentRosterStore, execution: ExecutionService? = nil,
              geminiClient: GeminiAPIClient? = nil, geminiOAuth: GeminiOAuthClient? = nil,
              openAIClient: OpenAIClient? = nil) {
        self.anthropicClient = client
        self.roster = roster
        self.executionService = execution
        self.geminiClient = geminiClient
        self.geminiOAuth = geminiOAuth
        self.openAIClient = openAIClient
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

            // Send to the active provider (isolated conversation — no history)
            var responseText = ""
            var completed = false
            var errorMsg: String?

            let systemPrompt = "You are \(agent.name), a specialist AI agent. Execute your heartbeat instructions precisely. Work autonomously."
            let sessionKey = "agent:heartbeat:\(agent.id)"

            // Use a semaphore-like pattern with continuation
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.sendToActiveProvider(
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
                    let summary = String(responseText.prefix(200))
                    self.lastRunResults[agent.id] = summary

                    // Write output to agent's output file
                    self.writeAgentOutput(agent: agent, response: responseText, durationMs: Int(duration * 1000))

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

        // Access-mode aware preamble
        let accessBlock: String
        if let exec = executionService, exec.accessMode.isUnleashed {
            accessBlock = """
            
            ACCESS MODE: UNLEASHED — You have FULL ACCESS to this computer.
            You can execute shell commands by wrapping them in ```bash code fences.
            Results will be fed back to you. Execute commands autonomously.
            Available: file read/write, git, npm, python, brew, system utilities, network.
            
            When you need to run a command, output it like this:
            ```bash
            your-command-here
            ```
            
            """
        } else {
            accessBlock = """
            
            ACCESS MODE: RESTRICTED — You can analyze, plan, and respond with text only.
            You cannot execute commands or modify files directly.
            Provide clear instructions for the user to execute manually.
            
            """
        }

        let preamble = """
        You are \(agent.name), part of the NDAI multi-agent team.
        \(accessBlock)
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

    // MARK: - Provider-Aware Send

    /// Route a send request to the active provider from ProviderStateStore.
    /// Falls back through available providers if the active one isn't connected.
    private func sendToActiveProvider(
        text: String,
        systemPrompt: String?,
        sessionKey: String,
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String, String?) -> Void,
        onError: @escaping (String) -> Void
    ) {
        let activeProvider = ProviderStateStore.load().activeProvider

        // Try active provider first
        switch activeProvider {
        case .gemini:
            if let oauth = geminiOAuth, oauth.authenticated, let client = geminiClient {
                client.send(text: text, systemPrompt: systemPrompt, sessionKey: sessionKey,
                            onDelta: onDelta, onComplete: onComplete, onError: onError)
                return
            }
        case .claude:
            if let client = anthropicClient, client.apiKeyConfigured {
                client.send(text: text, history: [], systemPrompt: systemPrompt, sessionKey: sessionKey,
                            onDelta: onDelta, onComplete: onComplete, onError: onError)
                return
            }
        case .chatgpt:
            if let client = openAIClient, client.apiKeyConfigured {
                client.send(text: text, systemPrompt: systemPrompt, sessionKey: sessionKey,
                            onDelta: onDelta, onComplete: onComplete, onError: onError)
                return
            }
        }

        // Fallback: try any connected provider
        if let oauth = geminiOAuth, oauth.authenticated, let client = geminiClient {
            client.send(text: text, systemPrompt: systemPrompt, sessionKey: sessionKey,
                        onDelta: onDelta, onComplete: onComplete, onError: onError)
            return
        }
        if let client = anthropicClient, client.apiKeyConfigured {
            client.send(text: text, history: [], systemPrompt: systemPrompt, sessionKey: sessionKey,
                        onDelta: onDelta, onComplete: onComplete, onError: onError)
            return
        }
        if let client = openAIClient, client.apiKeyConfigured {
            client.send(text: text, systemPrompt: systemPrompt, sessionKey: sessionKey,
                        onDelta: onDelta, onComplete: onComplete, onError: onError)
            return
        }

        onError("No AI provider connected. Open Settings to configure a provider.")
    }

    // MARK: - Tool Call Extraction & Execution

    /// Parse agent response for bash code fences and execute them.
    private func executeToolCalls(from response: String, agent: AgentHeartbeatConfig) async {
        guard let exec = executionService else { return }

        let commands = Self.extractBashCommands(from: response)
        guard !commands.isEmpty else { return }

        await MainActor.run {
            self.roster?.setState(id: agent.id, state: .working, detail: "Executing \(commands.count) command(s)…")
        }

        var results: [(command: String, result: ShellCommandResult)] = []

        for command in commands {
            let result = await exec.run(command, agentId: agent.id)
            results.append((command, result))
        }

        // Build a follow-up message with execution results
        var feedback = "## Command Execution Results\n\n"
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

        // Send results back to the agent for a follow-up response
        let systemPrompt = "You are \(agent.name). You just executed commands on the computer. Review the results and report status. If there were errors, explain what happened."
        let sessionKey = "agent:toolresult:\(agent.id)"

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.sendToActiveProvider(
                text: feedback,
                systemPrompt: systemPrompt,
                sessionKey: sessionKey,
                onDelta: { _ in },
                onComplete: { [weak self] response, _ in
                    self?.writeAgentOutput(agent: agent, response: response, durationMs: 0)
                    continuation.resume()
                },
                onError: { _ in
                    continuation.resume()
                }
            )
        }
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
