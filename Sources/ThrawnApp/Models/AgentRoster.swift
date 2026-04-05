import Foundation
import SwiftUI
import Combine

enum AgentActivityState: String, Codable {
    case idle
    case working
    case handoff
    case review
    case blocked

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .handoff: return "Handoff"
        case .review: return "Review"
        case .blocked: return "Blocked"
        }
    }

    var color: Color {
        switch self {
        case .idle:
            return Color(red: 0.45, green: 0.53, blue: 0.64)
        case .working:
            return Color(red: 0.18, green: 0.58, blue: 0.98)
        case .handoff:
            return Color(red: 0.42, green: 0.75, blue: 1.0)
        case .review:
            return Color(red: 0.76, green: 0.82, blue: 1.0)
        case .blocked:
            return Color(red: 0.95, green: 0.36, blue: 0.34)
        }
    }
}

struct AgentStatus: Identifiable, Codable {
    let id: String
    let name: String
    let role: String
    var state: AgentActivityState
    var detail: String
    var lastTransition: Date
    var sessionKey: String

    init(id: String, name: String, role: String, state: AgentActivityState, detail: String, lastTransition: Date = Date(), sessionKey: String? = nil) {
        self.id = id
        self.name = name
        self.role = role
        self.state = state
        self.detail = detail
        self.lastTransition = lastTransition
        self.sessionKey = sessionKey ?? "agent:specialist:\(id)"
    }

    // Codable conformance with default for sessionKey (backward compat with existing JSON)
    enum CodingKeys: String, CodingKey {
        case id, name, role, state, detail, lastTransition, sessionKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        role = try c.decode(String.self, forKey: .role)
        state = try c.decode(AgentActivityState.self, forKey: .state)
        detail = try c.decode(String.self, forKey: .detail)
        lastTransition = try c.decode(Date.self, forKey: .lastTransition)
        sessionKey = try c.decodeIfPresent(String.self, forKey: .sessionKey) ?? "agent:specialist:\(id)"
    }
}

@MainActor
final class AgentRosterStore: ObservableObject {
    @Published var agents: [AgentStatus] = [] {
        didSet { save() }
    }

    private static let savePath = ThrawnPaths.appSupportDir
        .appendingPathComponent("thrawn-agent-roster.json")

    private static let defaults: [AgentStatus] = [
        AgentStatus(id: "thrawn",  name: "Thrawn",            role: "Lead",            state: .idle, detail: "Command ready",             sessionKey: "agent:main:main"),
        AgentStatus(id: "r2d2",   name: "R2-D2",             role: "Dev",             state: .idle, detail: "Awaiting build brief",       sessionKey: "agent:specialist:r2d2"),
        AgentStatus(id: "c3po",   name: "C-3PO",             role: "Data",            state: .idle, detail: "Schema and API standby",     sessionKey: "agent:specialist:c3po"),
        AgentStatus(id: "quigon", name: "Qui-Gon",           role: "Research",        state: .idle, detail: "Research standby",            sessionKey: "agent:specialist:quigon"),
        AgentStatus(id: "lando",  name: "Lando Calrissian",  role: "Marketing & Copy",state: .idle, detail: "Copy standby",               sessionKey: "agent:specialist:lando"),
        AgentStatus(id: "boba",   name: "Boba Fett",         role: "QA & Recon",      state: .idle, detail: "Validation queue clear",     sessionKey: "agent:specialist:boba")
    ]

    // Track which agents have active in-flight requests
    private var activeAgentSessions: Set<String> = []
    private var threadStoreObserver: Any?
    private weak var gatewayClient: GatewayWSClient?

    /// Maps cron job UUID → agent ID (e.g. "bd261208-..." → "r2d2")
    /// Built from ~/.openclaw/cron/jobs.json so we can match cron session keys.
    private var cronJobAgentMap: [String: String] = [:]

    /// Legacy cron jobs path (for backward compat with OpenClaw cron system).
    /// Native scheduler doesn't need this, but it's read for detecting externally-running agents.
    private static let cronJobsPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".openclaw/cron/jobs.json")

    /// Reference to the native agent scheduler for detecting active agents.
    private weak var agentScheduler: AgentScheduler?

    func bindToGateway(_ client: GatewayWSClient) {
        gatewayClient = client
    }

    func bindToScheduler(_ scheduler: AgentScheduler) {
        self.agentScheduler = scheduler
    }

    init() {
        load()
        loadCronJobMap()
        startPolling()
    }

    func setState(id: String, state: AgentActivityState, detail: String) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        agents[index].state = state
        agents[index].detail = detail
        agents[index].lastTransition = Date()
    }

    func agentForSessionKey(_ key: String) -> AgentStatus? {
        agents.first { $0.sessionKey == key }
    }

    /// Bind to a ThreadStore to reactively update agent states based on in-flight requests.
    /// Thrawn's jewel lights up when ANY thread is in-flight (since all threads currently go through Thrawn).
    private var thrawnReviewTimer: Task<Void, Never>?

    func bindToThreadStore(_ threadStore: ThreadStore) {
        // Observe inFlightCount changes
        threadStoreObserver = threadStore.$inFlightCount.sink { [weak self] count in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if count > 0 {
                    // Cancel any pending review→idle transition
                    self.thrawnReviewTimer?.cancel()
                    self.thrawnReviewTimer = nil
                    self.setStateIfChanged(id: "thrawn", state: .working, detail: "Processing \(count) request\(count == 1 ? "" : "s")")
                } else {
                    // Transition through .review briefly before returning to .idle
                    self.setStateIfChanged(id: "thrawn", state: .review, detail: "Response received")
                    self.thrawnReviewTimer?.cancel()
                    self.thrawnReviewTimer = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds in review
                        guard !Task.isCancelled else { return }
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            if let idx = self.agents.firstIndex(where: { $0.id == "thrawn" }),
                               self.agents[idx].state == .review {
                                self.agents[idx].state = .idle
                                self.agents[idx].detail = "Command ready"
                                self.agents[idx].lastTransition = Date()
                            }
                        }
                    }
                }
            }
        }
    }

    /// Update agent state for a specialist session key (used when sending to specialist agents)
    func markSessionActive(_ sessionKey: String, detail: String = "Working…") {
        guard let agent = agentForSessionKey(sessionKey) else { return }
        activeAgentSessions.insert(sessionKey)
        setState(id: agent.id, state: .working, detail: detail)
    }

    func markSessionComplete(_ sessionKey: String, detail: String = "Task complete") {
        guard let agent = agentForSessionKey(sessionKey) else { return }
        activeAgentSessions.remove(sessionKey)
        setState(id: agent.id, state: .review, detail: detail)
        // Auto-transition to idle after 30s
        let agentId = agent.id
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let idx = self.agents.firstIndex(where: { $0.id == agentId }),
                   self.agents[idx].state == .review {
                    self.agents[idx].state = .idle
                    self.agents[idx].detail = "Standing by"
                    self.agents[idx].lastTransition = Date()
                }
            }
        }
    }

    func markSessionError(_ sessionKey: String, detail: String = "Error — check logs") {
        guard let agent = agentForSessionKey(sessionKey) else { return }
        activeAgentSessions.remove(sessionKey)
        setState(id: agent.id, state: .blocked, detail: detail)
    }

    private func setStateIfChanged(id: String, state: AgentActivityState, detail: String) {
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        guard agents[index].state != state else { return }
        agents[index].state = state
        agents[index].detail = detail
        agents[index].lastTransition = Date()
    }

    // MARK: - Cron job → agent mapping

    /// Reads ~/.openclaw/cron/jobs.json and builds jobId → agentId map.
    /// Job names follow the pattern "R2-D2 Heartbeat (:10)" — we extract the
    /// agent name before " Heartbeat" or " Initiative", normalize to match roster IDs.
    private func loadCronJobMap() {
        guard let data = try? Data(contentsOf: Self.cronJobsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobs = json["jobs"] as? [[String: Any]] else { return }

        var map: [String: String] = [:]
        for job in jobs {
            guard let jobId = job["id"] as? String,
                  let name = job["name"] as? String else { continue }
            // Extract agent name: everything before " Heartbeat" or " Initiative"
            let agentDisplayName: String
            if let range = name.range(of: " Heartbeat") {
                agentDisplayName = String(name[name.startIndex..<range.lowerBound])
            } else if let range = name.range(of: " Initiative") {
                agentDisplayName = String(name[name.startIndex..<range.lowerBound])
            } else {
                continue
            }
            // Normalize: lowercase, strip hyphens (e.g. "R2-D2" → "r2d2", "Qui-Gon" → "quigon")
            let agentId = agentDisplayName.lowercased().replacingOccurrences(of: "-", with: "")
            if agents.contains(where: { $0.id == agentId }) {
                map[jobId] = agentId
            }
        }
        cronJobAgentMap = map
    }

    /// Checks jobs.json state for agents with recently started runs (fallback when
    /// gateway sessions.list doesn't show the cron session).
    private func detectActiveFromCronState() -> Set<String> {
        guard let data = try? Data(contentsOf: Self.cronJobsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobs = json["jobs"] as? [[String: Any]] else { return [] }

        let nowMs = Date().timeIntervalSince1970 * 1000
        var active: Set<String> = []

        for job in jobs {
            guard let jobId = job["id"] as? String,
                  let agentId = cronJobAgentMap[jobId],
                  let state = job["state"] as? [String: Any],
                  let lastRunAtMs = state["lastRunAtMs"] as? Double else { continue }

            // Use previous run duration as estimate, with a 5-minute ceiling
            let lastDurationMs = (state["lastDurationMs"] as? Double) ?? 120_000
            let estimatedWindow = min(max(lastDurationMs * 1.5, 60_000), 300_000)

            // If the run started recently enough that it could still be going
            if nowMs - lastRunAtMs < estimatedWindow {
                active.insert(agentId)
            }
        }
        return active
    }

    // MARK: - Polling

    // Poll every 8s: live Gateway sessions + cron state + file-based override support
    private func startPolling() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000) // 8s — fast enough to feel live
                await refreshFromGateway()
                reloadIfChanged() // keep file-based override support
            }
        }
    }

    /// Refresh counter — reload cron job map every ~60s (every 8th poll)
    private var pollCount = 0

    private func refreshFromGateway() async {
        // Periodically reload the cron job map in case jobs change
        pollCount += 1
        if pollCount % 8 == 0 { loadCronJobMap() }

        guard let client = gatewayClient else { return }
        let sessions = await client.sessionsList()

        // Build set of currently active agent IDs from live sessions
        var activeNow: Set<String> = []
        for session in sessions {
            // Match by label (preferred: Thrawn sets label="r2d2" when spawning R2)
            if let label = session.label?.lowercased(), !label.isEmpty {
                let agentId = label.replacingOccurrences(of: "-", with: "")
                if agents.contains(where: { $0.id == agentId }) {
                    activeNow.insert(agentId)
                }
            }

            let key = session.key

            // Match cron sessions: key pattern "agent:main:cron:<jobId>:run:<runId>"
            if key.hasPrefix("agent:main:cron:") {
                let afterPrefix = String(key.dropFirst("agent:main:cron:".count))
                if let runRange = afterPrefix.range(of: ":run:") {
                    let jobId = String(afterPrefix[afterPrefix.startIndex..<runRange.lowerBound])
                    if let agentId = cronJobAgentMap[jobId] {
                        activeNow.insert(agentId)
                    }
                }
            }

            // Also match by session key pattern (e.g. "agent:specialist:r2d2")
            for agent in agents where agent.id != "thrawn" {
                if key.lowercased().contains(agent.id) {
                    activeNow.insert(agent.id)
                }
            }
        }

        // Native scheduler: detect agents currently running heartbeats
        if let scheduler = agentScheduler {
            activeNow.formUnion(scheduler.runningAgents)
        }

        // Fallback: detect agents with recently started cron runs from jobs.json state
        // This catches cases where the gateway session ended but the run was very recent
        let cronActive = detectActiveFromCronState()
        activeNow.formUnion(cronActive)

        // Update agents that are now active
        for agentId in activeNow {
            setStateIfChanged(id: agentId, state: .working, detail: "Working…")
        }

        // Transition agents that were working but are no longer in active sessions → review
        for agent in agents where agent.id != "thrawn" && agent.state == .working {
            if !activeNow.contains(agent.id) {
                setStateIfChanged(id: agent.id, state: .review, detail: "Task complete")
                let id = agent.id
                Task {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        if let idx = self.agents.firstIndex(where: { $0.id == id }),
                           self.agents[idx].state == .review {
                            self.agents[idx].state = .idle
                            self.agents[idx].detail = "Standing by"
                            self.agents[idx].lastTransition = Date()
                        }
                    }
                }
            }
        }
    }

    private var lastLoadedModTime: Date?

    private func reloadIfChanged() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: Self.savePath.path)
        let modTime = attrs?[.modificationDate] as? Date
        guard let modTime, modTime != lastLoadedModTime else { return }
        load()
    }

    private func load() {
        if let data = try? Data(contentsOf: Self.savePath),
           let decoded = try? JSONDecoder().decode([AgentStatus].self, from: data),
           !decoded.isEmpty {
            // Merge: preserve agents that exist in defaults but not in file
            var merged = decoded
            for def in Self.defaults {
                if !merged.contains(where: { $0.id == def.id }) {
                    merged.append(def)
                }
            }
            agents = merged
        } else {
            agents = Self.defaults
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: Self.savePath.path)
        lastLoadedModTime = attrs?[.modificationDate] as? Date
    }

    private func save() {
        if let data = try? JSONEncoder().encode(agents) {
            try? data.write(to: Self.savePath)
        }
    }
}
