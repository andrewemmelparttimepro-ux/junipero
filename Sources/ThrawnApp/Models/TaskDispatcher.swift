import Foundation

// MARK: - Native Task Dispatcher
//
// Reads per-agent update files (updates-*.json) and the legacy
// agent-updates.json, applies changes to TASK_BOARD.md.
//
// Reliability guarantees:
//   • Bad JSON is logged and quarantined, never silently eaten
//   • Board is backed up before every mutation batch
//   • Per-agent files eliminate read-modify-write race conditions
//   • Failed mutations don't corrupt the board — changes are atomic

@MainActor
final class TaskDispatcher: ObservableObject {
    @Published var lastDispatchTime: Date?
    @Published var lastDispatchCount: Int = 0
    @Published var lastError: String?

    private var timerTask: Task<Void, Never>?

    private var opsDir: URL { ThrawnPaths.opsDir }
    private var updatesDir: URL { ThrawnPaths.opsDir.appendingPathComponent("pending-updates") }
    private var legacyUpdatesPath: URL { opsDir.appendingPathComponent("agent-updates.json") }
    private var boardPath: URL { opsDir.appendingPathComponent("TASK_BOARD.md") }
    private var logPath: URL { opsDir.appendingPathComponent("dispatch-log.jsonl") }
    private var errorLogPath: URL { opsDir.appendingPathComponent("dispatch-errors.jsonl") }
    private var backupDir: URL { opsDir.appendingPathComponent("board-backups") }

    private let fm = FileManager.default

    // MARK: - Start/Stop

    func start() {
        guard timerTask == nil else { return }
        ensureDirectories()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.processAllUpdates()
                try? await Task.sleep(nanoseconds: 30_000_000_000) // Every 30 seconds
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func ensureDirectories() {
        try? fm.createDirectory(at: updatesDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        // Ensure legacy file exists for backward compat
        if !fm.fileExists(atPath: legacyUpdatesPath.path) {
            try? "[]".write(to: legacyUpdatesPath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Collect Updates from All Sources

    /// Read updates from per-agent files AND the legacy shared file.
    private func collectUpdates() -> (updates: [[String: Any]], sources: [URL]) {
        var allUpdates: [[String: Any]] = []
        var sources: [URL] = []

        // 1. Per-agent update files: pending-updates/updates-*.json
        if let files = try? fm.contentsOfDirectory(at: updatesDir, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("updates-") && file.pathExtension == "json" {
                if let parsed = parseUpdateFile(file) {
                    allUpdates.append(contentsOf: parsed)
                    sources.append(file)
                }
            }
        }

        // 2. Legacy shared file: agent-updates.json
        if let parsed = parseUpdateFile(legacyUpdatesPath), !parsed.isEmpty {
            allUpdates.append(contentsOf: parsed)
            sources.append(legacyUpdatesPath)
        }

        return (allUpdates, sources)
    }

    /// Parse a single update file. Returns nil only on read error.
    /// Logs and quarantines bad JSON instead of silently dropping.
    private func parseUpdateFile(_ path: URL) -> [[String: Any]]? {
        guard let data = try? Data(contentsOf: path) else { return nil }

        // Empty or whitespace-only file
        let text = String(data: data, encoding: .utf8) ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "[]" { return [] }

        // Try parsing as JSON array (expected format)
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return array
        }

        // Try parsing as single object (common model mistake — wraps in {})
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Check if it has a "tasks" array inside (another common model format)
            if let tasks = dict["tasks"] as? [[String: Any]] {
                logError(source: path.lastPathComponent, message: "Wrapped in {tasks:[...]} instead of flat array — recovered \(tasks.count) updates")
                return tasks
            }
            // Single update object — wrap in array
            if dict["action"] != nil {
                logError(source: path.lastPathComponent, message: "Single object instead of array — recovered 1 update")
                return [dict]
            }
        }

        // Truly unparseable — quarantine the file
        logError(source: path.lastPathComponent, message: "Invalid JSON — quarantined. Content: \(String(trimmed.prefix(500)))")
        quarantineFile(path)
        return nil
    }

    // MARK: - Process All Updates

    func processAllUpdates() {
        let (updates, sources) = collectUpdates()
        guard !updates.isEmpty else { return }

        // Read board
        guard var boardContent = try? String(contentsOf: boardPath, encoding: .utf8) else {
            logError(source: "dispatcher", message: "Cannot read TASK_BOARD.md at \(boardPath.path)")
            return
        }

        // Backup board before mutations
        backupBoard(boardContent)

        var appliedCount = 0
        var skippedCount = 0

        for update in updates {
            guard let action = update["action"] as? String else {
                logError(source: "dispatcher", message: "Update missing 'action' field: \(describeUpdate(update))")
                skippedCount += 1
                continue
            }

            // Accept both camelCase ("taskId") and snake_case ("task_id")
            let taskId = (update["taskId"] as? String) ?? (update["task_id"] as? String)

            switch action {
            case "move":
                if let taskId,
                   let field = update["field"] as? String,
                   let value = update["value"] as? String {
                    if replaceField(in: &boardContent, taskId: taskId, field: field, value: value) {
                        appliedCount += 1
                        logDispatch(action: "move", taskId: taskId, detail: "\(field) → \(value)")
                    } else {
                        logError(source: "dispatcher", message: "move failed — \(taskId) or field '\(field)' not found on board")
                        skippedCount += 1
                    }
                } else {
                    logError(source: "dispatcher", message: "move missing required fields (task_id, field, value): \(describeUpdate(update))")
                    skippedCount += 1
                }

            case "update":
                guard let taskId else {
                    logError(source: "dispatcher", message: "update missing task_id: \(describeUpdate(update))")
                    skippedCount += 1
                    break
                }
                if let field = update["field"] as? String,
                   let value = update["value"] as? String {
                    if replaceField(in: &boardContent, taskId: taskId, field: field, value: value) {
                        appliedCount += 1
                        logDispatch(action: "update", taskId: taskId, detail: "\(field)")
                    } else {
                        logError(source: "dispatcher", message: "update failed — \(taskId) or field '\(field)' not found on board")
                        skippedCount += 1
                    }
                } else if let fields = update["fields"] as? [String: String] {
                    for (field, value) in fields {
                        if replaceField(in: &boardContent, taskId: taskId, field: field, value: value) {
                            appliedCount += 1
                        } else {
                            skippedCount += 1
                        }
                    }
                    logDispatch(action: "update", taskId: taskId, detail: "\(fields.count) fields")
                } else {
                    logError(source: "dispatcher", message: "update missing field/value or fields dict: \(describeUpdate(update))")
                    skippedCount += 1
                }

            case "create":
                if let title = update["title"] as? String {
                    let resolvedId: String
                    if let taskId, taskId != "TASK-NEW" {
                        resolvedId = taskId
                    } else {
                        resolvedId = nextTaskId(in: boardContent)
                    }
                    let owner = update["owner"] as? String ?? "Thrawn"
                    let status = update["status"] as? String ?? "Ready"
                    let priority = update["priority"] as? String ?? "P2"
                    let notes = update["notes"] as? String ?? ""
                    let agent = update["agent"] as? String ?? "Thrawn"

                    // Objective linkage — if Thrawn is creating this task as
                    // part of a phase, he passes the objective id + phase
                    // index so the board scanner can count tasks against
                    // the correct phase without fragile title substring
                    // matching. Optional — tasks can still be created
                    // free-standing (ad-hoc, inbox triage, etc.).
                    let objectiveId = (update["objective"] as? String)
                        ?? (update["objectiveId"] as? String)
                        ?? (update["objective_id"] as? String)
                    let phaseAny = update["phase"] ?? update["phaseIndex"] ?? update["phase_index"]
                    let phaseIndex: Int? = {
                        if let i = phaseAny as? Int { return i }
                        if let s = phaseAny as? String, let i = Int(s) { return i }
                        return nil
                    }()

                    var newTask = "\n\n### \(resolvedId)\n"
                    newTask += "- Title: \(title)\n"
                    newTask += "- Owner: \(owner)\n"
                    newTask += "- Status: \(status)\n"
                    newTask += "- Priority: \(priority)\n"
                    newTask += "- Created: \(ISO8601DateFormatter().string(from: Date()).prefix(10))\n"
                    if let objectiveId, !objectiveId.isEmpty {
                        newTask += "- Objective: \(objectiveId)\n"
                    }
                    if let phaseIndex {
                        newTask += "- Phase: \(phaseIndex)\n"
                    }
                    if !notes.isEmpty {
                        newTask += "- Notes: \(notes)\n"
                    }
                    newTask += "- Requested by: \(agent)\n"

                    boardContent += newTask
                    appliedCount += 1
                    let linkDetail: String = {
                        if let objectiveId, let phaseIndex {
                            return " [\(objectiveId)/P\(phaseIndex)]"
                        }
                        return ""
                    }()
                    logDispatch(action: "create", taskId: resolvedId, detail: "\(title)\(linkDetail)")
                } else {
                    logError(source: "dispatcher", message: "create missing 'title': \(describeUpdate(update))")
                    skippedCount += 1
                }

            case "note":
                if let taskId,
                   let note = update["note"] as? String {
                    if appendNote(in: &boardContent, taskId: taskId, note: note) {
                        appliedCount += 1
                        logDispatch(action: "note", taskId: taskId, detail: String(note.prefix(50)))
                    } else {
                        logError(source: "dispatcher", message: "note failed — \(taskId) not found on board")
                        skippedCount += 1
                    }
                }

            default:
                logError(source: "dispatcher", message: "Unknown action '\(action)': \(describeUpdate(update))")
                skippedCount += 1
            }
        }

        // Write board only if something changed
        if appliedCount > 0 {
            let tempPath = boardPath.appendingPathExtension("tmp")
            do {
                try boardContent.write(to: tempPath, atomically: true, encoding: .utf8)
                _ = try fm.replaceItemAt(boardPath, withItemAt: tempPath)
                lastDispatchTime = Date()
                lastDispatchCount = appliedCount
                lastError = nil
            } catch {
                logError(source: "dispatcher", message: "Failed to write board: \(error.localizedDescription)")
                lastError = "Board write failed: \(error.localizedDescription)"
            }
        }

        if skippedCount > 0 {
            logDispatch(action: "summary", taskId: "-", detail: "Applied \(appliedCount), skipped \(skippedCount)")
        }

        // Clean up processed source files
        for source in sources {
            if source == legacyUpdatesPath {
                // Reset legacy file to empty array
                try? "[]".write(to: source, atomically: true, encoding: .utf8)
            } else {
                // Delete per-agent file after processing
                try? fm.removeItem(at: source)
            }
        }
    }

    // MARK: - Task ID Generation

    private func nextTaskId(in boardContent: String) -> String {
        let pattern = "### TASK-(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "TASK-100" }
        let range = NSRange(boardContent.startIndex..., in: boardContent)
        let matches = regex.matches(in: boardContent, range: range)
        var maxId = 0
        for match in matches {
            if match.numberOfRanges > 1,
               let numRange = Range(match.range(at: 1), in: boardContent),
               let num = Int(boardContent[numRange]) {
                maxId = max(maxId, num)
            }
        }
        return String(format: "TASK-%03d", maxId + 1)
    }

    // MARK: - Field Replacement

    private func replaceField(in content: inout String, taskId: String, field: String, value: String) -> Bool {
        guard let taskRange = content.range(of: "### \(taskId)") else { return false }

        let afterTask = content[taskRange.upperBound...]
        let nextTaskRange = afterTask.range(of: "\n### TASK-") ?? afterTask.endIndex..<afterTask.endIndex
        let taskSection = String(afterTask[afterTask.startIndex..<nextTaskRange.lowerBound])

        let escapedField = NSRegularExpression.escapedPattern(for: field)
        let pattern = "-\\s+(?:\\*\\*\(escapedField):\\*\\*|\(escapedField):)\\s*.+"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }

        let nsTaskSection = taskSection as NSString
        let match = regex.firstMatch(in: taskSection, range: NSRange(location: 0, length: nsTaskSection.length))
        guard let match else { return false }

        let replacement = "- \(field): \(value)"
        let updatedSection = nsTaskSection.replacingCharacters(in: match.range, with: replacement)

        let fullRange = content.index(taskRange.upperBound, offsetBy: 0)..<content.index(taskRange.upperBound, offsetBy: taskSection.count)
        content.replaceSubrange(fullRange, with: updatedSection)

        return true
    }

    private func appendNote(in content: inout String, taskId: String, note: String) -> Bool {
        guard let taskRange = content.range(of: "### \(taskId)") else { return false }

        let afterTask = content[taskRange.upperBound...]
        let nextTaskRange = afterTask.range(of: "\n### TASK-") ?? afterTask.endIndex..<afterTask.endIndex

        let insertPoint = nextTaskRange.lowerBound
        let noteText = "\n- Note: \(note)"
        content.insert(contentsOf: noteText, at: insertPoint)
        return true
    }

    // MARK: - Board Backup

    /// Keep last 20 backups. Rotate oldest out.
    private func backupBoard(_ content: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupPath = backupDir.appendingPathComponent("TASK_BOARD-\(timestamp).md")
        try? content.write(to: backupPath, atomically: true, encoding: .utf8)

        // Prune old backups — keep last 20
        if let files = try? fm.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.creationDateKey])
            .sorted(by: { a, b in
                let aDate = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let bDate = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return aDate > bDate
            }) {
            for file in files.dropFirst(20) {
                try? fm.removeItem(at: file)
            }
        }
    }

    // MARK: - Quarantine

    /// Move unparseable files to a quarantine directory instead of deleting.
    private func quarantineFile(_ path: URL) {
        let quarantineDir = opsDir.appendingPathComponent("quarantine")
        try? fm.createDirectory(at: quarantineDir, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = quarantineDir.appendingPathComponent("\(timestamp)-\(path.lastPathComponent)")
        try? fm.moveItem(at: path, to: dest)
    }

    // MARK: - Logging

    private func logDispatch(action: String, taskId: String, detail: String) {
        writeLog(to: logPath, entries: [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "action": action,
            "taskId": taskId,
            "detail": detail
        ])
        FlightRecorder.logEvent(
            category: "dispatcher",
            action: action,
            detail: "\(taskId): \(detail)"
        )
    }

    private func logError(source: String, message: String) {
        print("⚠️ TaskDispatcher: [\(source)] \(message)")
        writeLog(to: errorLogPath, entries: [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "source": source,
            "error": message
        ])
        FlightRecorder.logError(source: "dispatcher:\(source)", message: message)
    }

    private func writeLog(to path: URL, entries: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: entries),
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

    private func describeUpdate(_ update: [String: Any]) -> String {
        let keys = update.keys.sorted().joined(separator: ", ")
        return "{\(keys)}"
    }
}
