import Foundation

// MARK: - Flight Recorder
//
// Central observability system for Thrawn Console.
// Captures EVERY significant event as append-only JSONL:
//   • LLM calls (prompt, response, model, timing, agent)
//   • Command executions (command, exit code, output, agent)
//   • Dispatcher actions (what was applied, what was skipped, errors)
//   • Heartbeat lifecycle (start, end, duration, success/failure)
//   • Task board mutations (field changes with before/after)
//   • Errors (any failure anywhere)
//
// All logs go to ~/Library/Application Support/Thrawn/workspace/logs/
// Daily reports are generated from these logs for external review.

enum FlightRecorder {
    private static let fm = FileManager.default
    private static let logsDir: URL = {
        let dir = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/logs")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Today's date string for file naming
    private static var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Current ISO timestamp
    private static var now: String {
        ISO8601DateFormatter().string(from: Date())
    }

    // MARK: - Log Files (one per day, auto-rotated)

    private static var llmLogPath: URL { logsDir.appendingPathComponent("llm-\(today).jsonl") }
    private static var execLogPath: URL { logsDir.appendingPathComponent("exec-\(today).jsonl") }
    private static var heartbeatLogPath: URL { logsDir.appendingPathComponent("heartbeat-\(today).jsonl") }
    private static var errorLogPath: URL { logsDir.appendingPathComponent("errors-\(today).jsonl") }
    private static var eventLogPath: URL { logsDir.appendingPathComponent("events-\(today).jsonl") }

    // MARK: - LLM Calls

    /// Log an LLM request/response pair.
    static func logLLM(
        agent: String,
        model: String,
        promptLength: Int,
        responseLength: Int,
        durationMs: Int,
        sessionKey: String,
        systemPromptLength: Int = 0,
        success: Bool,
        error: String? = nil,
        responseSummary: String? = nil
    ) {
        var entry: [String: Any] = [
            "ts": now,
            "agent": agent,
            "model": model,
            "prompt_chars": promptLength,
            "response_chars": responseLength,
            "system_prompt_chars": systemPromptLength,
            "duration_ms": durationMs,
            "session": sessionKey,
            "success": success,
        ]
        if let e = error { entry["error"] = e }
        if let s = responseSummary { entry["response_summary"] = String(s.prefix(300)) }
        append(entry, to: llmLogPath)
    }

    // MARK: - Command Execution

    /// Log a shell command execution.
    static func logExec(
        agent: String?,
        command: String,
        exitCode: Int32,
        durationMs: Int,
        stdoutLength: Int,
        stderrLength: Int,
        stderrPreview: String? = nil
    ) {
        var entry: [String: Any] = [
            "ts": now,
            "agent": agent ?? "user",
            "command": String(command.prefix(500)),
            "exit_code": exitCode,
            "duration_ms": durationMs,
            "stdout_chars": stdoutLength,
            "stderr_chars": stderrLength,
        ]
        if let preview = stderrPreview, !preview.isEmpty {
            entry["stderr_preview"] = String(preview.prefix(200))
        }
        append(entry, to: execLogPath)
    }

    // MARK: - Heartbeat Lifecycle

    /// Log a heartbeat start/end.
    static func logHeartbeat(
        agent: String,
        event: String,  // "start", "complete", "error", "skipped"
        durationMs: Int = 0,
        commandsExecuted: Int = 0,
        detail: String? = nil
    ) {
        var entry: [String: Any] = [
            "ts": now,
            "agent": agent,
            "event": event,
            "duration_ms": durationMs,
            "commands_executed": commandsExecuted,
        ]
        if let d = detail { entry["detail"] = String(d.prefix(300)) }
        append(entry, to: heartbeatLogPath)
    }

    // MARK: - Errors

    /// Log any error from any subsystem.
    static func logError(
        source: String,
        message: String,
        context: [String: String] = [:]
    ) {
        var entry: [String: Any] = [
            "ts": now,
            "source": source,
            "message": String(message.prefix(500)),
        ]
        for (k, v) in context { entry[k] = v }
        append(entry, to: errorLogPath)
    }

    // MARK: - General Events

    /// Log any notable event (task mutations, state changes, etc.)
    static func logEvent(
        category: String,
        action: String,
        detail: String,
        metadata: [String: String] = [:]
    ) {
        var entry: [String: Any] = [
            "ts": now,
            "category": category,
            "action": action,
            "detail": String(detail.prefix(300)),
        ]
        for (k, v) in metadata { entry[k] = v }
        append(entry, to: eventLogPath)
    }

    // MARK: - Daily Report Generation

    /// Generate a comprehensive daily report as Markdown.
    /// Call this on demand or on schedule.
    static func generateDailyReport(for date: String? = nil) -> String {
        let targetDate = date ?? today
        var report = "# Thrawn Daily Report — \(targetDate)\n\n"
        report += "Generated: \(now)\n\n"

        // LLM stats
        let llmEntries = readLog(logsDir.appendingPathComponent("llm-\(targetDate).jsonl"))
        report += "## LLM Calls (\(llmEntries.count) total)\n\n"
        if !llmEntries.isEmpty {
            let successful = llmEntries.filter { $0["success"] as? Bool == true }
            let failed = llmEntries.filter { $0["success"] as? Bool != true }
            let totalDuration = llmEntries.compactMap { $0["duration_ms"] as? Int }.reduce(0, +)
            let avgDuration = llmEntries.isEmpty ? 0 : totalDuration / llmEntries.count
            let totalPromptChars = llmEntries.compactMap { $0["prompt_chars"] as? Int }.reduce(0, +)
            let totalResponseChars = llmEntries.compactMap { $0["response_chars"] as? Int }.reduce(0, +)

            report += "| Metric | Value |\n|--------|-------|\n"
            report += "| Successful | \(successful.count) |\n"
            report += "| Failed | \(failed.count) |\n"
            report += "| Total duration | \(totalDuration / 1000)s |\n"
            report += "| Avg duration | \(avgDuration)ms |\n"
            report += "| Total prompt chars | \(totalPromptChars) |\n"
            report += "| Total response chars | \(totalResponseChars) |\n\n"

            // Per-agent breakdown
            let byAgent = Dictionary(grouping: llmEntries, by: { $0["agent"] as? String ?? "unknown" })
            report += "### Per-Agent Breakdown\n\n"
            report += "| Agent | Calls | Successes | Failures | Avg Duration |\n"
            report += "|-------|-------|-----------|----------|-------------|\n"
            for (agent, entries) in byAgent.sorted(by: { $0.key < $1.key }) {
                let ok = entries.filter { $0["success"] as? Bool == true }.count
                let fail = entries.count - ok
                let avgMs = entries.compactMap { $0["duration_ms"] as? Int }.reduce(0, +) / max(entries.count, 1)
                report += "| \(agent) | \(entries.count) | \(ok) | \(fail) | \(avgMs)ms |\n"
            }
            report += "\n"

            // Failed calls detail
            if !failed.isEmpty {
                report += "### Failed LLM Calls\n\n"
                for entry in failed {
                    let agent = entry["agent"] as? String ?? "?"
                    let err = entry["error"] as? String ?? "unknown"
                    let ts = entry["ts"] as? String ?? ""
                    report += "- **\(ts)** \(agent): \(err)\n"
                }
                report += "\n"
            }
        }

        // Command execution stats
        let execEntries = readLog(logsDir.appendingPathComponent("exec-\(targetDate).jsonl"))
        report += "## Command Executions (\(execEntries.count) total)\n\n"
        if !execEntries.isEmpty {
            let succeeded = execEntries.filter { ($0["exit_code"] as? Int) == 0 }
            let failed = execEntries.filter { ($0["exit_code"] as? Int) != 0 }

            report += "| Metric | Value |\n|--------|-------|\n"
            report += "| Succeeded (exit 0) | \(succeeded.count) |\n"
            report += "| Failed (exit != 0) | \(failed.count) |\n\n"

            if !failed.isEmpty {
                report += "### Failed Commands\n\n"
                for entry in failed.prefix(20) {
                    let agent = entry["agent"] as? String ?? "?"
                    let cmd = entry["command"] as? String ?? "?"
                    let code = entry["exit_code"] as? Int ?? -1
                    let stderr = entry["stderr_preview"] as? String ?? ""
                    report += "- **\(agent)** `\(String(cmd.prefix(80)))` → exit \(code)"
                    if !stderr.isEmpty { report += " — \(String(stderr.prefix(100)))" }
                    report += "\n"
                }
                report += "\n"
            }
        }

        // Heartbeat stats
        let hbEntries = readLog(logsDir.appendingPathComponent("heartbeat-\(targetDate).jsonl"))
        report += "## Heartbeats (\(hbEntries.count) events)\n\n"
        if !hbEntries.isEmpty {
            let starts = hbEntries.filter { ($0["event"] as? String) == "start" }
            let completes = hbEntries.filter { ($0["event"] as? String) == "complete" }
            let errors = hbEntries.filter { ($0["event"] as? String) == "error" }

            report += "| Metric | Value |\n|--------|-------|\n"
            report += "| Started | \(starts.count) |\n"
            report += "| Completed | \(completes.count) |\n"
            report += "| Errored | \(errors.count) |\n\n"

            if !errors.isEmpty {
                report += "### Heartbeat Errors\n\n"
                for entry in errors {
                    let agent = entry["agent"] as? String ?? "?"
                    let detail = entry["detail"] as? String ?? "unknown"
                    let ts = entry["ts"] as? String ?? ""
                    report += "- **\(ts)** \(agent): \(detail)\n"
                }
                report += "\n"
            }
        }

        // Errors
        let errorEntries = readLog(logsDir.appendingPathComponent("errors-\(targetDate).jsonl"))
        report += "## Errors (\(errorEntries.count) total)\n\n"
        if !errorEntries.isEmpty {
            for entry in errorEntries {
                let source = entry["source"] as? String ?? "?"
                let msg = entry["message"] as? String ?? "?"
                let ts = entry["ts"] as? String ?? ""
                report += "- **\(ts)** [\(source)] \(msg)\n"
            }
            report += "\n"
        }

        // Events
        let eventEntries = readLog(logsDir.appendingPathComponent("events-\(targetDate).jsonl"))
        report += "## Events (\(eventEntries.count) total)\n\n"
        if !eventEntries.isEmpty {
            let byCategory = Dictionary(grouping: eventEntries, by: { $0["category"] as? String ?? "other" })
            for (cat, entries) in byCategory.sorted(by: { $0.key < $1.key }) {
                report += "### \(cat) (\(entries.count))\n"
                for entry in entries.prefix(30) {
                    let action = entry["action"] as? String ?? "?"
                    let detail = entry["detail"] as? String ?? ""
                    report += "- \(action): \(detail)\n"
                }
                report += "\n"
            }
        }

        // Quality score
        report += "## Quality Score\n\n"
        let llmSuccess = llmEntries.isEmpty ? 100 : (llmEntries.filter { $0["success"] as? Bool == true }.count * 100 / llmEntries.count)
        let execSuccess = execEntries.isEmpty ? 100 : (execEntries.filter { ($0["exit_code"] as? Int) == 0 }.count * 100 / execEntries.count)
        let hbSuccess = hbEntries.filter { ($0["event"] as? String) == "start" }.count == 0 ? 100 :
            (hbEntries.filter { ($0["event"] as? String) == "complete" }.count * 100 / max(hbEntries.filter { ($0["event"] as? String) == "start" }.count, 1))

        report += "| Component | Score |\n|-----------|-------|\n"
        report += "| LLM call success rate | \(llmSuccess)% |\n"
        report += "| Command success rate | \(execSuccess)% |\n"
        report += "| Heartbeat completion rate | \(hbSuccess)% |\n"
        report += "| Error count | \(errorEntries.count) |\n\n"

        let overall = (llmSuccess + execSuccess + hbSuccess) / 3
        report += "**Overall health: \(overall)%**\n\n"

        if overall < 70 {
            report += "**STATUS: NEEDS ATTENTION** — Multiple subsystems underperforming.\n"
        } else if overall < 90 {
            report += "**STATUS: ACCEPTABLE** — Some issues to address.\n"
        } else {
            report += "**STATUS: HEALTHY** — All systems nominal.\n"
        }

        return report
    }

    /// Write the daily report to disk.
    static func writeDailyReport(for date: String? = nil) -> URL {
        let targetDate = date ?? today
        let reportsDir = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/reports")
        try? fm.createDirectory(at: reportsDir, withIntermediateDirectories: true)
        let reportPath = reportsDir.appendingPathComponent("daily-\(targetDate).md")
        let report = generateDailyReport(for: targetDate)
        try? report.write(to: reportPath, atomically: true, encoding: .utf8)
        return reportPath
    }

    // MARK: - Log Rotation

    /// Delete logs older than 14 days.
    static func rotateOldLogs() {
        guard let files = try? fm.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-14 * 24 * 3600)
        for file in files {
            if let created = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
               created < cutoff {
                try? fm.removeItem(at: file)
            }
        }
    }

    // MARK: - Internals

    private static func append(_ entry: [String: Any], to path: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              let line = String(data: data, encoding: .utf8) else { return }
        if fm.fileExists(atPath: path.path) {
            if let handle = try? FileHandle(forWritingTo: path) {
                handle.seekToEndOfFile()
                handle.write(Data((line + "\n").utf8))
                handle.closeFile()
            }
        } else {
            fm.createFile(atPath: path.path, contents: Data((line + "\n").utf8))
        }
    }

    private static func readLog(_ path: URL) -> [[String: Any]] {
        guard let content = try? String(contentsOf: path, encoding: .utf8) else { return [] }
        return content.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return obj
        }
    }
}
