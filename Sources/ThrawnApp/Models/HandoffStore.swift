import Foundation
import SwiftUI

// MARK: - Dex Handoff System
//
// The "dex" layer: twice-daily handoff between Thrawn and Claude.
//
//  Morning handoff  (09:00): Thrawn debriefs on overnight work.
//                            Claude reviews, suggests course corrections.
//  Evening handoff  (17:00): Thrawn debriefs on today's work AND requests
//                            Claude to implement ONE business-improving change.
//
// The handoff report is generated from FlightRecorder logs + agent outputs
// + deliverables + objective progress. It is written to:
//   ~/Library/Application Support/Thrawn/workspace/handoffs/YYYY-MM-DD-{morning|evening}.md
//
// Claude's scheduled task picks these up, analyzes, and (on evening) commits
// one concrete improvement. Claude then drops a response report next to it.
//
// This closes the loop: the factory runs 24/7, and a human-level reviewer
// audits it twice a day AND makes one improvement per day.

enum HandoffKind: String, Codable, CaseIterable {
    case morning   // Debrief only — course correction from Claude
    case evening   // Debrief + implementation request

    var displayName: String { self == .morning ? "Morning Debrief" : "Evening Implementation" }
    var scheduledHour: Int { self == .morning ? 9 : 17 }
    var icon: String { self == .morning ? "sunrise.fill" : "moon.stars.fill" }
}

enum HandoffStatus: String, Codable {
    case pending       // Generated, waiting for Claude
    case reviewed      // Claude reviewed (morning flow)
    case implemented   // Claude implemented the change (evening flow)
    case stale         // Never picked up
}

struct Handoff: Identifiable, Codable {
    let id: String                 // HANDOFF-YYYY-MM-DD-kind
    let kind: HandoffKind
    let createdAt: Date
    var status: HandoffStatus
    var reportPath: String         // Markdown file on disk
    var responsePath: String?      // Claude's response after review
    var summary: String            // Short one-line summary
    var metrics: HandoffMetrics

    struct HandoffMetrics: Codable {
        var llmCalls: Int
        var llmSuccessRate: Int
        var heartbeatsCompleted: Int
        var heartbeatsErrored: Int
        var tasksCreated: Int
        var tasksCompleted: Int
        var errorCount: Int
        var overallHealthPercent: Int
    }
}

@MainActor
final class HandoffStore: ObservableObject {
    @Published var handoffs: [Handoff] = []

    private let fm = FileManager.default
    private weak var objectiveStore: ObjectiveStore?
    private weak var rankEvaluator: RankEvaluator?

    private var handoffsDir: URL {
        let dir = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/handoffs")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var indexFile: URL {
        ThrawnPaths.appSupportDir.appendingPathComponent("workspace/handoffs-index.json")
    }

    init() {
        load()
    }

    func bind(objectives: ObjectiveStore, rankEvaluator: RankEvaluator? = nil) {
        self.objectiveStore = objectives
        self.rankEvaluator = rankEvaluator
    }

    // MARK: - Scheduling

    /// True if we should generate a handoff of this kind right now.
    /// Called from AgentScheduler tick.
    func shouldGenerate(kind: HandoffKind, now: Date = Date()) -> Bool {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)

        // Fire in the first 5 minutes of the scheduled hour
        guard hour == kind.scheduledHour, minute < 5 else { return false }

        // Don't re-fire the same kind on the same day
        let today = Self.dayKey(now)
        let alreadyFired = handoffs.contains { h in
            h.kind == kind && Self.dayKey(h.createdAt) == today
        }
        return !alreadyFired
    }

    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - Generation

    /// Generate a handoff report for the given kind.
    /// Pulls from FlightRecorder, agent outputs, task board, and objectives.
    @discardableResult
    func generate(kind: HandoffKind) -> Handoff {
        let now = Date()
        let dayKey = Self.dayKey(now)
        let id = "HANDOFF-\(dayKey)-\(kind.rawValue)"

        // Build the markdown report
        let (markdown, metrics) = buildReport(kind: kind, date: now)

        // Write to disk
        let filename = "\(dayKey)-\(kind.rawValue).md"
        let reportURL = handoffsDir.appendingPathComponent(filename)
        try? markdown.write(to: reportURL, atomically: true, encoding: .utf8)

        // Build summary line
        let summary = "\(kind.displayName) — Health \(metrics.overallHealthPercent)%, " +
                      "\(metrics.heartbeatsCompleted) HBs, \(metrics.tasksCompleted)/\(metrics.tasksCreated) tasks"

        let handoff = Handoff(
            id: id,
            kind: kind,
            createdAt: now,
            status: .pending,
            reportPath: reportURL.path,
            responsePath: nil,
            summary: summary,
            metrics: metrics
        )

        // Replace any existing handoff for today+kind (idempotent)
        handoffs.removeAll { $0.id == id }
        handoffs.append(handoff)
        handoffs.sort { $0.createdAt > $1.createdAt }
        save()

        FlightRecorder.logEvent(
            category: "handoff",
            action: "generated",
            detail: "\(id): \(summary)",
            metadata: ["kind": kind.rawValue, "path": reportURL.path]
        )

        // Drop a pointer file so Claude's cron can find the latest
        writeLatestPointer(handoff: handoff)

        // Re-score every agent and retire ephemerals at task budget.
        // Safe to call for dev-ops squad — they're pinned, only scores move.
        rankEvaluator?.evaluateAll()

        return handoff
    }

    /// Mark a handoff as reviewed/implemented by Claude.
    /// Called when a response file appears in handoffs dir.
    func markReviewed(_ id: String, responsePath: String, implemented: Bool) {
        guard let idx = handoffs.firstIndex(where: { $0.id == id }) else { return }
        handoffs[idx].status = implemented ? .implemented : .reviewed
        handoffs[idx].responsePath = responsePath
        save()
        FlightRecorder.logEvent(
            category: "handoff",
            action: implemented ? "implemented" : "reviewed",
            detail: id
        )
    }

    /// Scan handoffs dir for Claude response files and update statuses.
    func scanForResponses() {
        guard let files = try? fm.contentsOfDirectory(at: handoffsDir, includingPropertiesForKeys: nil) else { return }
        for h in handoffs where h.status == .pending {
            let dayKey = Self.dayKey(h.createdAt)
            let responseName = "\(dayKey)-\(h.kind.rawValue)-response.md"
            if let match = files.first(where: { $0.lastPathComponent == responseName }) {
                let content = (try? String(contentsOf: match, encoding: .utf8)) ?? ""
                let implemented = content.lowercased().contains("implemented:")
                markReviewed(h.id, responsePath: match.path, implemented: implemented)
            }
        }
    }

    // MARK: - Report Builder

    private func buildReport(kind: HandoffKind, date: Date) -> (String, Handoff.HandoffMetrics) {
        let dayKey = Self.dayKey(date)
        let iso = ISO8601DateFormatter().string(from: date)

        // Pull the FlightRecorder daily report as the foundation
        let flightReport = FlightRecorder.generateDailyReport(for: dayKey)

        // Extract rough metrics by re-reading log files
        let metrics = computeMetrics(dayKey: dayKey)

        // Objective snapshot
        var objectiveSection = "## Active Objectives\n\n"
        if let store = objectiveStore {
            let active = store.activeObjectives
            if active.isEmpty {
                objectiveSection += "_No user-defined objectives. Running NDAI fallback protocol._\n\n"
            } else {
                for obj in active {
                    let pct = Int(obj.progressPercent)
                    objectiveSection += "- **\(obj.id)** \(obj.playbookName) — \"\(obj.input)\"\n"
                    objectiveSection += "  - Progress: \(pct)% (phase \(obj.currentPhaseIndex + 1))\n"
                    objectiveSection += "  - Tasks: \(obj.tasksCompleted)/\(obj.tasksCreated) done\n"
                }
                objectiveSection += "\n"
            }
        }

        // Agent output summaries
        var agentOutputs = "## Agent Output Summaries\n\n"
        let outputDir = ThrawnPaths.opsDir.appendingPathComponent("agent-output")
        if let files = try? fm.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil) {
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard file.pathExtension == "json",
                      let data = try? Data(contentsOf: file),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let agent = obj["agent"] as? String ?? file.deletingPathExtension().lastPathComponent
                let ts = obj["timestamp"] as? String ?? "?"
                let summary = obj["summary"] as? String ?? ""
                agentOutputs += "### \(agent) — \(ts)\n\n\(summary.prefix(400))\n\n"
            }
        } else {
            agentOutputs += "_No agent output files found._\n\n"
        }

        // Deliverables scan
        var deliverables = "## Assets & Deliverables\n\n"
        let deliverablesDir = ThrawnPaths.opsDir.appendingPathComponent("deliverables")
        if let files = try? fm.contentsOfDirectory(at: deliverablesDir, includingPropertiesForKeys: [.creationDateKey]) {
            let recent = files.filter { file in
                guard let created = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate else { return false }
                return created > date.addingTimeInterval(-24 * 3600)
            }
            if recent.isEmpty {
                deliverables += "_No deliverables produced in the last 24 hours. Claude should infer impact from work logs._\n\n"
            } else {
                for f in recent.prefix(20) {
                    deliverables += "- `\(f.lastPathComponent)`\n"
                }
                deliverables += "\n"
            }
        } else {
            deliverables += "_Deliverables directory not yet created._\n\n"
        }

        // Kind-specific instruction block for Claude
        let claudeInstructions: String
        switch kind {
        case .morning:
            claudeInstructions = """
            ## Instructions for Claude

            This is the **morning debrief**. Your job:
            1. Read the metrics and agent output summaries above.
            2. Compare to what you would have done yesterday given the same objectives.
            3. Identify the single biggest gap, mistake, or missed opportunity.
            4. Write your review to `\(handoffsDir.path)/\(dayKey)-morning-response.md`.
            5. Structure:
               ```
               # Morning Review — \(dayKey)
               ## What went well
               ## What went wrong
               ## What I would have done differently
               ## Course correction for today
               ```
            6. Do NOT implement changes at this handoff. Save implementation for the evening handoff.
            """
        case .evening:
            claudeInstructions = """
            ## Instructions for Claude

            This is the **evening implementation handoff**. Your job:
            1. Read the metrics, outputs, and deliverables above.
            2. Analyze all assets produced today — if none, infer impact from the work logs.
            3. Identify ONE concrete change that would help the NDAI business:
               - A new report (compiled from today's research)
               - A website/copy update
               - A tool/script that automates a recurring problem you observed
               - A process improvement to a stuck heartbeat loop
               - A new playbook for a recurring objective pattern
            4. **IMPLEMENT that change.** One change. Don't over-scope.
            5. Write your report to `\(handoffsDir.path)/\(dayKey)-evening-response.md`.
            6. Start the response with `Implemented:` followed by a one-line title.
            7. Structure:
               ```
               Implemented: <one-line title>

               # Evening Implementation — \(dayKey)
               ## What the factory accomplished
               ## Asset analysis
               ## What I would have done differently
               ## The change I implemented
               <details, file paths, commit refs>
               ## Business impact
               ```
            """
        }

        let header = """
        # \(kind.displayName) — \(dayKey)

        **Handoff ID:** HANDOFF-\(dayKey)-\(kind.rawValue)
        **Generated:** \(iso)
        **Type:** \(kind.rawValue)

        ---

        ## Factory Metrics

        | Metric | Value |
        |--------|-------|
        | Overall health | **\(metrics.overallHealthPercent)%** |
        | LLM calls | \(metrics.llmCalls) (\(metrics.llmSuccessRate)% success) |
        | Heartbeats completed | \(metrics.heartbeatsCompleted) |
        | Heartbeats errored | \(metrics.heartbeatsErrored) |
        | Tasks created | \(metrics.tasksCreated) |
        | Tasks completed | \(metrics.tasksCompleted) |
        | Error events | \(metrics.errorCount) |

        ---

        \(objectiveSection)

        ---

        \(agentOutputs)

        ---

        \(deliverables)

        ---

        \(claudeInstructions)

        ---

        ## Full FlightRecorder Daily Report

        \(flightReport)
        """

        return (header, metrics)
    }

    private func computeMetrics(dayKey: String) -> Handoff.HandoffMetrics {
        let logsDir = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/logs")

        func readJsonl(_ name: String) -> [[String: Any]] {
            let path = logsDir.appendingPathComponent("\(name)-\(dayKey).jsonl")
            guard let content = try? String(contentsOf: path, encoding: .utf8) else { return [] }
            return content.split(separator: "\n").compactMap { line in
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                return obj
            }
        }

        let llm = readJsonl("llm")
        let hb = readJsonl("heartbeat")
        let errors = readJsonl("errors")
        let events = readJsonl("events")

        let llmSuccess = llm.filter { $0["success"] as? Bool == true }.count
        let llmRate = llm.isEmpty ? 100 : (llmSuccess * 100 / llm.count)
        let hbComplete = hb.filter { ($0["event"] as? String) == "complete" }.count
        let hbError = hb.filter { ($0["event"] as? String) == "error" }.count

        let taskEvents = events.filter { ($0["category"] as? String) == "dispatcher" || ($0["category"] as? String) == "task" }
        let tasksCreated = taskEvents.filter { ($0["action"] as? String)?.contains("create") == true }.count
        let tasksCompleted = taskEvents.filter { ($0["detail"] as? String)?.lowercased().contains("done") == true }.count

        let execSuccess = 100 // not critical here
        let overall = (llmRate + execSuccess + (hb.isEmpty ? 100 : hbComplete * 100 / max(hb.count, 1))) / 3

        return Handoff.HandoffMetrics(
            llmCalls: llm.count,
            llmSuccessRate: llmRate,
            heartbeatsCompleted: hbComplete,
            heartbeatsErrored: hbError,
            tasksCreated: tasksCreated,
            tasksCompleted: tasksCompleted,
            errorCount: errors.count,
            overallHealthPercent: overall
        )
    }

    private func writeLatestPointer(handoff: Handoff) {
        let pointer: [String: Any] = [
            "id": handoff.id,
            "kind": handoff.kind.rawValue,
            "report_path": handoff.reportPath,
            "created_at": ISO8601DateFormatter().string(from: handoff.createdAt),
            "expected_response_path": handoffsDir.appendingPathComponent(
                "\(Self.dayKey(handoff.createdAt))-\(handoff.kind.rawValue)-response.md"
            ).path,
        ]
        let pointerURL = handoffsDir.appendingPathComponent("LATEST.json")
        if let data = try? JSONSerialization.data(withJSONObject: pointer, options: [.prettyPrinted]) {
            try? data.write(to: pointerURL, options: .atomic)
        }
    }

    // MARK: - Persistence

    private func save() {
        let dir = indexFile.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(handoffs) {
            try? data.write(to: indexFile, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexFile) else { return }
        handoffs = (try? JSONDecoder().decode([Handoff].self, from: data)) ?? []
    }
}
