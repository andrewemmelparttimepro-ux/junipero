import Foundation

// MARK: - Native Task Dispatcher
//
// Replaces task-dispatch.py — reads agent-updates.json and applies
// changes to TASK_BOARD.md programmatically. Runs on a timer.
// App Store compliant — pure Swift, no external processes.

@MainActor
final class TaskDispatcher: ObservableObject {
    @Published var lastDispatchTime: Date?
    @Published var lastDispatchCount: Int = 0

    private var timerTask: Task<Void, Never>?

    private var updatesPath: URL { ThrawnPaths.opsDir.appendingPathComponent("agent-updates.json") }
    private var boardPath: URL { ThrawnPaths.opsDir.appendingPathComponent("TASK_BOARD.md") }
    private var logPath: URL { ThrawnPaths.opsDir.appendingPathComponent("dispatch-log.jsonl") }

    // MARK: - Start/Stop

    func start() {
        guard timerTask == nil else { return }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.processUpdates()
                try? await Task.sleep(nanoseconds: 30_000_000_000) // Every 30 seconds
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Process Updates

    func processUpdates() {
        guard let data = try? Data(contentsOf: updatesPath),
              let updates = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !updates.isEmpty else { return }

        guard var boardContent = try? String(contentsOf: boardPath, encoding: .utf8) else { return }

        var appliedCount = 0

        for update in updates {
            guard let action = update["action"] as? String else { continue }

            switch action {
            case "move":
                if let taskId = update["taskId"] as? String,
                   let newStatus = update["status"] as? String {
                    if replaceField(in: &boardContent, taskId: taskId, field: "Status", value: newStatus) {
                        appliedCount += 1
                        logDispatch(action: "move", taskId: taskId, detail: "→ \(newStatus)")
                    }
                }

            case "update":
                if let taskId = update["taskId"] as? String,
                   let fields = update["fields"] as? [String: String] {
                    for (field, value) in fields {
                        if replaceField(in: &boardContent, taskId: taskId, field: field, value: value) {
                            appliedCount += 1
                        }
                    }
                    logDispatch(action: "update", taskId: taskId, detail: "\(fields.count) fields")
                }

            case "create":
                if let taskId = update["taskId"] as? String,
                   let title = update["title"] as? String {
                    let owner = update["owner"] as? String ?? "Thrawn"
                    let status = update["status"] as? String ?? "Ready"
                    let priority = update["priority"] as? String ?? "P2"

                    let newTask = """

                    ### \(taskId): \(title)
                    - **Owner:** \(owner)
                    - **Status:** \(status)
                    - **Priority:** \(priority)
                    """

                    boardContent += newTask
                    appliedCount += 1
                    logDispatch(action: "create", taskId: taskId, detail: title)
                }

            case "note":
                if let taskId = update["taskId"] as? String,
                   let note = update["note"] as? String {
                    if appendNote(in: &boardContent, taskId: taskId, note: note) {
                        appliedCount += 1
                        logDispatch(action: "note", taskId: taskId, detail: String(note.prefix(50)))
                    }
                }

            default:
                break
            }
        }

        if appliedCount > 0 {
            // Atomic write
            let tempPath = boardPath.appendingPathExtension("tmp")
            try? boardContent.write(to: tempPath, atomically: true, encoding: .utf8)
            try? FileManager.default.replaceItemAt(boardPath, withItemAt: tempPath)

            lastDispatchTime = Date()
            lastDispatchCount = appliedCount
        }

        // Clear the updates file
        try? "[]".write(to: updatesPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Field Replacement

    private func replaceField(in content: inout String, taskId: String, field: String, value: String) -> Bool {
        // Find the task section
        guard let taskRange = content.range(of: "### \(taskId)") else { return false }

        // Find the field line within the task section
        let afterTask = content[taskRange.upperBound...]

        // Find the next task boundary
        let nextTaskRange = afterTask.range(of: "\n### TASK-") ?? afterTask.endIndex..<afterTask.endIndex

        let taskSection = String(afterTask[afterTask.startIndex..<nextTaskRange.lowerBound])

        // Replace the field value
        let pattern = "\\*\\*\(NSRegularExpression.escapedPattern(for: field)):\\*\\*\\s*.+"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }

        let nsTaskSection = taskSection as NSString
        let match = regex.firstMatch(in: taskSection, range: NSRange(location: 0, length: nsTaskSection.length))
        guard let match else { return false }

        let replacement = "**\(field):** \(value)"
        let updatedSection = nsTaskSection.replacingCharacters(in: match.range, with: replacement)

        // Replace in full content
        let fullRange = content.index(taskRange.upperBound, offsetBy: 0)..<content.index(taskRange.upperBound, offsetBy: taskSection.count)
        content.replaceSubrange(fullRange, with: updatedSection)

        return true
    }

    private func appendNote(in content: inout String, taskId: String, note: String) -> Bool {
        guard let taskRange = content.range(of: "### \(taskId)") else { return false }

        let afterTask = content[taskRange.upperBound...]
        let nextTaskRange = afterTask.range(of: "\n### TASK-") ?? afterTask.endIndex..<afterTask.endIndex

        let insertPoint = nextTaskRange.lowerBound
        let noteText = "\n- **Note:** \(note)"
        content.insert(contentsOf: noteText, at: insertPoint)
        return true
    }

    // MARK: - Logging

    private func logDispatch(action: String, taskId: String, detail: String) {
        let entry: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "action": action,
            "taskId": taskId,
            "detail": detail
        ]
        if let data = try? JSONSerialization.data(withJSONObject: entry),
           let line = String(data: data, encoding: .utf8) {
            let handle: FileHandle
            if FileManager.default.fileExists(atPath: logPath.path) {
                handle = try! FileHandle(forWritingTo: logPath)
                handle.seekToEndOfFile()
            } else {
                FileManager.default.createFile(atPath: logPath.path, contents: nil)
                handle = try! FileHandle(forWritingTo: logPath)
            }
            handle.write(Data((line + "\n").utf8))
            handle.closeFile()
        }
    }
}
