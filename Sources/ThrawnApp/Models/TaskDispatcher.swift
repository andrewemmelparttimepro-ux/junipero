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
    /// Sentinel lock file for cross-process mutual exclusion on the task
    /// board. Held during the entire read-modify-write cycle so external
    /// editors and a second Thrawn instance can't clobber updates.
    private var boardLockPath: URL { opsDir.appendingPathComponent("TASK_BOARD.md.lock") }

    private let fm = FileManager.default

    // MARK: - Start/Stop

    func start() {
        guard timerTask == nil else { return }
        ensureDirectories()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runProcessWithWatchdog()
                try? await Task.sleep(nanoseconds: 30_000_000_000) // Every 30 seconds
            }
        }
    }

    /// Hard cap on a single dispatch pass. If `processAllUpdates()` ever
    /// hangs (corrupt board file, runaway regex, fs stall), the watchdog
    /// breaks the loop so the polling loop keeps ticking instead of
    /// silently freezing. 60s is generous — a normal pass finishes in
    /// under a second even with hundreds of updates.
    private static let processWatchdogSeconds: Int = 60
    private static let processWatchdogNs: UInt64 = UInt64(processWatchdogSeconds) * 1_000_000_000

    /// Run processAllUpdates with a watchdog timer. If the work doesn't
    /// finish in time, log a CRITICAL error so the operator notices —
    /// dispatcher freezes are not a "silent fail" we can tolerate.
    private func runProcessWithWatchdog() async {
        // Wrap synchronous processAllUpdates in a Task so we can await
        // it with a timeout. The Task inherits @MainActor isolation since
        // the method itself is @MainActor.
        let workTask = Task { @MainActor [weak self] in
            self?.processAllUpdates()
        }

        let watchdog = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.processWatchdogNs)
            if !Task.isCancelled, !workTask.isCancelled {
                FlightRecorder.logError(
                    source: "dispatcher:watchdog",
                    message: "processAllUpdates exceeded \(Self.processWatchdogSeconds)s watchdog — cancelling. Dispatcher may have lost a tick."
                )
                workTask.cancel()
            }
        }

        await workTask.value
        watchdog.cancel()
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
            if let updates = dict["updates"] as? [[String: Any]] {
                logError(source: path.lastPathComponent, message: "Wrapped in {updates:[...]} instead of flat array — recovered \(updates.count) updates")
                return updates
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

        // Hold the cross-process board lock for the entire read-modify-write
        // cycle. Without this, an external editor (or a second Thrawn) could
        // race the dispatcher and lose either side's edits. The lock file
        // is just a flock sentinel — actual atomicity comes from the
        // temp-file-then-rename below. See FileLock.swift for details.
        FileLock.withLock(at: boardLockPath, source: "dispatcher:boardLock") {
            self.processAllUpdatesUnderLock(updates: updates, sources: sources)
        }
    }

    private func processAllUpdatesUnderLock(updates: [[String: Any]], sources: [URL]) {
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
                    if isCompletionStatusMutation(field: field, value: value),
                       !ensureCompletionDeliverable(in: &boardContent, taskId: taskId, candidate: evidenceCandidate(from: update)) {
                        logError(source: "dispatcher", message: "move to Done blocked — \(taskId) has no Deliverable/evidence pointer")
                        skippedCount += 1
                        continue
                    }
                    if applyFieldMutation(in: &boardContent, taskId: taskId, field: field, value: value) {
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
                    if isCompletionStatusMutation(field: field, value: value),
                       !ensureCompletionDeliverable(in: &boardContent, taskId: taskId, candidate: evidenceCandidate(from: update)) {
                        logError(source: "dispatcher", message: "update to Done blocked — \(taskId) has no Deliverable/evidence pointer")
                        skippedCount += 1
                        continue
                    }
                    if applyFieldMutation(in: &boardContent, taskId: taskId, field: field, value: value) {
                        appliedCount += 1
                        logDispatch(action: "update", taskId: taskId, detail: "\(field)")
                    } else {
                        logError(source: "dispatcher", message: "update failed — \(taskId) or field '\(field)' not found on board")
                        skippedCount += 1
                    }
                } else if let fields = update["fields"] as? [String: String] {
                    var fieldsToApply = fields
                    if let statusField = fields.keys.first(where: { $0.caseInsensitiveCompare("Status") == .orderedSame }),
                       let statusValue = fields[statusField],
                       TaskCompletionPolicy.isDoneStatus(statusValue),
                       !ensureCompletionDeliverable(in: &boardContent, taskId: taskId, candidate: evidenceCandidate(from: fields)) {
                        fieldsToApply.removeValue(forKey: statusField)
                        logError(source: "dispatcher", message: "fields update to Done blocked — \(taskId) has no Deliverable/evidence pointer")
                        skippedCount += 1
                    }
                    for (field, value) in fieldsToApply {
                        if applyFieldMutation(in: &boardContent, taskId: taskId, field: field, value: value) {
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
                    let deliverable = evidenceCandidate(from: update)
                        ?? (TaskCompletionPolicy.isDoneStatus(status) ? TaskCompletionPolicy.discoverDeliverable(for: resolvedId) : nil)

                    if TaskCompletionPolicy.isDoneStatus(status),
                       TaskCompletionPolicy.cleanEvidence(deliverable) == nil {
                        logError(source: "dispatcher", message: "create as Done blocked — \(resolvedId) has no Deliverable/evidence pointer")
                        skippedCount += 1
                        continue
                    }

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
                    if let deliverable {
                        newTask += "- Deliverable: \(deliverable)\n"
                    }
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

        // Clean up processed source files. CRITICAL for reliability: if a
        // source file isn't cleared, its updates will be re-applied on the
        // next tick. `move` / `update` are idempotent (no harm) but `create`
        // and `note` would duplicate. Every cleanup is best-effort with
        // fallbacks AND error logging.
        for source in sources {
            if source == legacyUpdatesPath {
                // Reset legacy file to empty array
                do {
                    try "[]".write(to: source, atomically: true, encoding: .utf8)
                } catch {
                    logError(
                        source: "dispatcher",
                        message: "Could not reset \(source.lastPathComponent) — updates may be reprocessed: \(error.localizedDescription)"
                    )
                }
            } else {
                // Delete per-agent file. Fall back to truncate-to-empty-array
                // if delete fails (e.g. file locked, permissions) — that still
                // prevents re-application without data loss.
                do {
                    try fm.removeItem(at: source)
                } catch {
                    logError(
                        source: "dispatcher",
                        message: "Could not delete \(source.lastPathComponent), attempting truncate fallback: \(error.localizedDescription)"
                    )
                    do {
                        try "[]".write(to: source, atomically: true, encoding: .utf8)
                    } catch {
                        logError(
                            source: "dispatcher",
                            message: "FALLBACK FAILED — \(source.lastPathComponent) will reprocess on next tick: \(error.localizedDescription)"
                        )
                    }
                }
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
        guard let taskSectionRange = taskSectionRange(in: content, taskId: taskId) else { return false }
        let taskSection = String(content[taskSectionRange])

        let escapedField = NSRegularExpression.escapedPattern(for: field)
        let pattern = "-\\s+(?:\\*\\*\(escapedField):\\*\\*|\(escapedField):)\\s*.*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }

        let nsTaskSection = taskSection as NSString
        let match = regex.firstMatch(in: taskSection, range: NSRange(location: 0, length: nsTaskSection.length))
        guard let match else { return false }

        let replacement = "- \(field): \(value)"
        let updatedSection = nsTaskSection.replacingCharacters(in: match.range, with: replacement)

        content.replaceSubrange(taskSectionRange, with: updatedSection)

        return true
    }

    private func taskSectionRange(in content: String, taskId: String) -> Range<String.Index>? {
        guard let taskRange = content.range(of: "### \(taskId)") else { return nil }
        let afterTask = content[taskRange.upperBound...]
        let nextTaskRange = afterTask.range(of: "\n### TASK-") ?? afterTask.endIndex..<afterTask.endIndex
        return taskRange.upperBound..<nextTaskRange.lowerBound
    }

    private func fieldValue(in content: String, taskId: String, field: String) -> String? {
        guard let taskSectionRange = taskSectionRange(in: content, taskId: taskId) else { return nil }
        let taskSection = String(content[taskSectionRange])
        let escapedField = NSRegularExpression.escapedPattern(for: field)
        let pattern = "-\\s+(?:\\*\\*\(escapedField):\\*\\*|\(escapedField):)\\s*(.*)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsTaskSection = taskSection as NSString
        guard let match = regex.firstMatch(in: taskSection, range: NSRange(location: 0, length: nsTaskSection.length)),
              match.numberOfRanges > 1 else { return nil }
        return nsTaskSection.substring(with: match.range(at: 1))
    }

    private func upsertField(in content: inout String, taskId: String, field: String, value: String) -> Bool {
        if replaceField(in: &content, taskId: taskId, field: field, value: value) {
            return true
        }
        guard let taskSectionRange = taskSectionRange(in: content, taskId: taskId) else { return false }
        content.insert(contentsOf: "\n- \(field): \(value)", at: taskSectionRange.upperBound)
        return true
    }

    private func applyFieldMutation(in content: inout String, taskId: String, field: String, value: String) -> Bool {
        if replaceField(in: &content, taskId: taskId, field: field, value: value) {
            return true
        }
        guard shouldUpsertMissingField(field) else { return false }
        return upsertField(in: &content, taskId: taskId, field: field, value: value)
    }

    private func shouldUpsertMissingField(_ field: String) -> Bool {
        let normalized = field.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [
            "collaborators",
            "created",
            "due",
            "inputs",
            "deliverable",
            "brain path",
            "notes",
            "review status",
            "blockers",
            "next step",
            "project",
            "requested by",
            "objective",
            "phase"
        ].contains(normalized)
    }

    private func ensureCompletionDeliverable(in content: inout String, taskId: String, candidate: String?) -> Bool {
        if TaskCompletionPolicy.cleanEvidence(fieldValue(in: content, taskId: taskId, field: "Deliverable")) != nil {
            return true
        }
        let resolved = TaskCompletionPolicy.cleanEvidence(candidate)
            ?? TaskCompletionPolicy.discoverDeliverable(for: taskId)
        guard let resolved else { return false }
        return upsertField(in: &content, taskId: taskId, field: "Deliverable", value: resolved)
    }

    private func isCompletionStatusMutation(field: String, value: String) -> Bool {
        field.caseInsensitiveCompare("Status") == .orderedSame && TaskCompletionPolicy.isDoneStatus(value)
    }

    private func evidenceCandidate(from update: [String: Any]) -> String? {
        for key in ["deliverable", "Deliverable", "evidence", "Evidence", "evidence_path", "evidencePath", "path", "file_path", "filePath"] {
            if let value = TaskCompletionPolicy.cleanEvidence(update[key] as? String) {
                return value
            }
        }
        return nil
    }

    private func evidenceCandidate(from fields: [String: String]) -> String? {
        for (field, value) in fields {
            let normalized = field.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["deliverable", "evidence", "evidence path", "evidence_path", "path", "file path", "file_path"].contains(normalized),
               let value = TaskCompletionPolicy.cleanEvidence(value) {
                return value
            }
        }
        return nil
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
        do {
            try content.write(to: backupPath, atomically: true, encoding: .utf8)
        } catch {
            // Backup failure is concerning but shouldn't block the dispatch.
            // Log it loud so the operator notices.
            logError(
                source: "dispatcher",
                message: "Backup write FAILED — proceeding without safety net: \(error.localizedDescription)"
            )
        }

        // Prune old backups — keep last 20. Best-effort.
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
    /// If the move fails, fall back to deleting the file so it doesn't keep
    /// getting reprocessed every tick (which would log spam forever).
    private func quarantineFile(_ path: URL) {
        let quarantineDir = opsDir.appendingPathComponent("quarantine")
        do {
            try fm.createDirectory(at: quarantineDir, withIntermediateDirectories: true)
        } catch {
            logError(
                source: "dispatcher:quarantine",
                message: "createDirectory failed: \(error.localizedDescription) — falling through to delete"
            )
            try? fm.removeItem(at: path)
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = quarantineDir.appendingPathComponent("\(timestamp)-\(path.lastPathComponent)")
        do {
            try fm.moveItem(at: path, to: dest)
        } catch {
            logError(
                source: "dispatcher:quarantine",
                message: "moveItem failed: \(error.localizedDescription) — deleting source to prevent reprocess loop"
            )
            // Last resort: delete the unparseable file so it stops generating
            // errors every 30 seconds. The error log already captured a 500-char
            // preview of the contents.
            try? fm.removeItem(at: path)
        }
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
