import Foundation

// MARK: - Rank Evaluator
//
// Scores each non-pinned agent after a handoff and adjusts their rank.
// Also handles ephemeral lifecycle retirement — if an ephemeral agent has
// hit its task budget, the evaluator marks them retired so the scheduler
// stops firing heartbeats.
//
// Pinned agents (the dev-ops squad by default) get a score computed and
// stored for visibility, but their rank never auto-moves. This is what
// the user asked for: "dev ops squad stays pinned at rank B, visible
// scores but pinned."
//
// Scoring inputs (v1):
//   - heartbeatsCompleted (success rate across recent runs)
//   - tasksCompleted/Created ratio
//   - errorCount (negative signal)
//
// Each agent's score is 0..100. Thresholds:
//   S ≥ 90, A ≥ 75, B ≥ 55, C < 55

struct AgentScore: Codable, Equatable {
    let agentId: String
    let score: Int
    let heartbeatsCompleted: Int
    let heartbeatsErrored: Int
    let tasksCompleted: Int
    let errorCount: Int
    let evaluatedAt: Date

    static func rank(forScore score: Int) -> AgentRank {
        if score >= 90 { return .s }
        if score >= 75 { return .a }
        if score >= 55 { return .b }
        return .c
    }
}

@MainActor
final class RankEvaluator: ObservableObject {
    /// Most recent score per agent, keyed by agent id.
    @Published private(set) var scores: [String: AgentScore] = [:]

    private weak var specStore: AgentSpecStore?

    private static let savePath = ThrawnPaths.appSupportDir
        .appendingPathComponent("agent-scores.json")

    init() { load() }

    func bind(specs: AgentSpecStore) {
        self.specStore = specs
    }

    // MARK: - Evaluation

    /// Evaluate all agents using metrics from the last N days of flight logs.
    /// Called after every handoff. Updates rank on non-pinned agents and
    /// retires ephemeral agents that have hit their budget.
    func evaluateAll(windowDays: Int = 3) {
        guard let store = specStore else { return }
        let metrics = Self.loadMetricsPerAgent(windowDays: windowDays)

        for spec in store.specs {
            let m = metrics[spec.id] ?? AgentMetrics()
            let score = Self.computeScore(metrics: m)
            let agentScore = AgentScore(
                agentId: spec.id,
                score: score,
                heartbeatsCompleted: m.heartbeatsCompleted,
                heartbeatsErrored: m.heartbeatsErrored,
                tasksCompleted: m.tasksCompleted,
                errorCount: m.errorCount,
                evaluatedAt: Date()
            )
            scores[spec.id] = agentScore

            // Retire ephemeral agents whose task budget is exhausted.
            if case .ephemeral(let budget) = spec.lifecycle, spec.tasksCompleted >= budget {
                FlightRecorder.logEvent(
                    category: "rank", action: "retire",
                    detail: "\(spec.id) hit ephemeral task budget (\(spec.tasksCompleted)/\(budget))"
                )
                store.remove(id: spec.id)
                continue
            }

            // Move rank only if not pinned. Pinned agents keep their rank
            // but the score is still recorded for UI.
            if !spec.pinned {
                let newRank = AgentScore.rank(forScore: score)
                if newRank != spec.rank {
                    var updated = spec
                    updated.rank = newRank
                    store.upsert(updated)
                    FlightRecorder.logEvent(
                        category: "rank", action: "move",
                        detail: "\(spec.id) \(spec.rank.displayName)→\(newRank.displayName) (score \(score))"
                    )
                }
            }
        }
        save()
    }

    // MARK: - Metrics loading

    struct AgentMetrics {
        var heartbeatsCompleted: Int = 0
        var heartbeatsErrored: Int = 0
        var tasksCompleted: Int = 0
        var errorCount: Int = 0
    }

    /// Walk the last `windowDays` of flight-recorder JSONL and aggregate
    /// per-agent metrics. Missing files are silently skipped.
    private static func loadMetricsPerAgent(windowDays: Int) -> [String: AgentMetrics] {
        var out: [String: AgentMetrics] = [:]
        let cal = Calendar.current
        let now = Date()
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"

        for offset in 0..<windowDays {
            guard let day = cal.date(byAdding: .day, value: -offset, to: now) else { continue }
            let dayKey = df.string(from: day)
            let logsDir = ThrawnPaths.appSupportDir
                .appendingPathComponent("workspace/logs/\(dayKey)")

            for category in ["heartbeat", "events", "errors"] {
                let file = logsDir.appendingPathComponent("\(category).jsonl")
                guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }

                for line in content.split(separator: "\n") {
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                    let agentId = (json["agent"] as? String)
                        ?? (json["source"] as? String)?.replacingOccurrences(of: "heartbeat:", with: "")
                        ?? ""
                    guard !agentId.isEmpty else { continue }

                    var m = out[agentId] ?? AgentMetrics()

                    switch category {
                    case "heartbeat":
                        let event = json["event"] as? String ?? ""
                        if event == "complete" { m.heartbeatsCompleted += 1 }
                        else if event == "error" { m.heartbeatsErrored += 1 }
                    case "events":
                        let cat = json["category"] as? String ?? ""
                        let action = json["action"] as? String ?? ""
                        if cat == "task" && action == "complete" { m.tasksCompleted += 1 }
                    case "errors":
                        m.errorCount += 1
                    default: break
                    }

                    out[agentId] = m
                }
            }
        }
        return out
    }

    // MARK: - Scoring

    /// 0..100. Biased toward heartbeat success, with error penalties and a
    /// small task-completion bonus. Agents with no data at all get a neutral
    /// 60 (B-tier baseline) so they don't get demoted before they've run.
    static func computeScore(metrics m: AgentMetrics) -> Int {
        let totalHb = m.heartbeatsCompleted + m.heartbeatsErrored
        if totalHb == 0 && m.tasksCompleted == 0 && m.errorCount == 0 {
            return 60  // neutral baseline
        }

        var score = 60.0

        // Heartbeat success rate: -20..+25
        if totalHb > 0 {
            let rate = Double(m.heartbeatsCompleted) / Double(totalHb)
            score += (rate - 0.7) * 50  // 70% success = baseline
        }

        // Task throughput: +0..+15
        score += min(Double(m.tasksCompleted) * 2.0, 15.0)

        // Errors: -0..-25
        score -= min(Double(m.errorCount) * 2.0, 25.0)

        return max(0, min(100, Int(score.rounded())))
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Self.savePath),
              let decoded = try? JSONDecoder().decode([String: AgentScore].self, from: data)
        else { return }
        self.scores = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(scores) else { return }
        try? data.write(to: Self.savePath)
    }
}
