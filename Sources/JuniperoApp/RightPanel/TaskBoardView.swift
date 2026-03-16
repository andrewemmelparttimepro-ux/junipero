import SwiftUI
import Foundation

// MARK: - Model

struct ParsedTask: Identifiable, Equatable {
    let id: String
    var title: String
    var owner: String
    var status: String
    var priority: String
    var due: String
    var nextStep: String
    var blockers: String
    var deliverable: String
    var notes: String

    static func == (lhs: ParsedTask, rhs: ParsedTask) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Activity Log (companion JSON file)

struct TaskActivity: Codable, Identifiable {
    var id: UUID = UUID()
    var taskId: String
    var timestamp: Date
    var author: String
    var action: String          // e.g., "moved to In Progress", "updated priority to High"
    var fieldChanged: String?   // e.g., "status", "priority", "owner"
    var oldValue: String?
    var newValue: String?
}

struct TaskComment: Codable, Identifiable {
    var id: UUID = UUID()
    var taskId: String
    var timestamp: Date
    var author: String
    var text: String
}

struct TaskChecklist: Codable, Identifiable {
    var id: UUID = UUID()
    var taskId: String
    var items: [ChecklistItem]

    struct ChecklistItem: Codable, Identifiable {
        var id: UUID = UUID()
        var text: String
        var completed: Bool
    }
}

// MARK: - Parser

func parseTaskBoard(from text: String) -> [ParsedTask] {
    var tasks: [ParsedTask] = []
    let lines = text.components(separatedBy: "\n")
    var i = 0

    while i < lines.count {
        let line = lines[i]
        if line.hasPrefix("### TASK-") {
            let taskId = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            var fields: [String: String] = [:]
            i += 1
            while i < lines.count && !lines[i].hasPrefix("### ") {
                let l = lines[i]
                if l.hasPrefix("- "), let colon = l.range(of: ": ") {
                    let key = String(l[l.index(l.startIndex, offsetBy: 2)..<colon.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let value = String(l[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
                    fields[key] = value
                }
                i += 1
            }
            let task = ParsedTask(
                id: taskId,
                title: fields["Title"] ?? taskId,
                owner: fields["Owner"] ?? "",
                status: fields["Status"] ?? "",
                priority: fields["Priority"] ?? "",
                due: fields["Due"] ?? "",
                nextStep: fields["Next step"] ?? "",
                blockers: fields["Blockers"] ?? "",
                deliverable: fields["Deliverable"] ?? "",
                notes: fields["Notes"] ?? ""
            )
            tasks.append(task)
        } else {
            i += 1
        }
    }
    return tasks
}

// MARK: - Serializer (write tasks back to markdown)

func serializeTaskBoard(_ tasks: [ParsedTask]) -> String {
    var lines: [String] = [
        "# TASK BOARD",
        "",
        "> Auto-managed by Thrawn Console. Edit fields in-app or here directly.",
        ""
    ]

    for task in tasks {
        lines.append("### \(task.id)")
        lines.append("- Title: \(task.title)")
        lines.append("- Owner: \(task.owner)")
        lines.append("- Status: \(task.status)")
        lines.append("- Priority: \(task.priority)")
        if !task.due.isEmpty     { lines.append("- Due: \(task.due)") }
        if !task.nextStep.isEmpty { lines.append("- Next step: \(task.nextStep)") }
        if !task.blockers.isEmpty { lines.append("- Blockers: \(task.blockers)") }
        if !task.deliverable.isEmpty { lines.append("- Deliverable: \(task.deliverable)") }
        if !task.notes.isEmpty   { lines.append("- Notes: \(task.notes)") }
        lines.append("")
    }

    return lines.joined(separator: "\n")
}

// MARK: - Store

@MainActor
final class TaskBoardStore: ObservableObject {
    @Published var tasks: [ParsedTask] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var activities: [TaskActivity] = []
    @Published var comments: [TaskComment] = []
    @Published var checklists: [TaskChecklist] = []

    private static let filePath = ThrawnPaths.opsFile("TASK_BOARD.md")
    private static let activityPath = ThrawnPaths.opsFile("task_activity.json")
    private static let commentsPath = ThrawnPaths.opsFile("task_comments.json")
    private static let checklistsPath = ThrawnPaths.opsFile("task_checklists.json")

    // File watcher — reloads board when agents modify TASK_BOARD.md on disk
    private var fileWatcherSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    /// Suppress file-watcher reload right after we save ourselves
    private var suppressNextReload = false
    /// Fallback poll timer catches changes the dispatch source misses (atomic renames)
    private var pollTimer: Timer?
    /// Hash of last-loaded content to detect real changes during polling
    private var lastContentHash: Int = 0

    private static let seed: [ParsedTask] = [
        ParsedTask(id: "TASK-001", title: "Gateway client.id fix", owner: "R2-D2", status: "Ready", priority: "Critical", due: "", nextStep: "One-line fix in GatewayWSClient.swift", blockers: "", deliverable: "Working gateway chat", notes: ""),
        ParsedTask(id: "TASK-002", title: "Wire live data into console", owner: "R2-D2", status: "Done", priority: "High", due: "", nextStep: "", blockers: "", deliverable: "FlowBoard reads TASK_BOARD.md, agent jewels reflect state", notes: ""),
        ParsedTask(id: "TASK-003", title: "Enable persistent agent sessions via ACP", owner: "Thrawn", status: "In Progress", priority: "High", due: "", nextStep: "Use sessions_spawn with runtime: acp and thread: true", blockers: "Needs gateway fix first", deliverable: "Persistent specialist sessions", notes: ""),
        ParsedTask(id: "TASK-004", title: "Wire Cognee memory system", owner: "Thrawn", status: "In Progress", priority: "Medium", due: "", nextStep: "Index workspace, enable recall", blockers: "", deliverable: "Agents remember context across sessions", notes: "Cognee healthy on :8000"),
        ParsedTask(id: "TASK-005", title: "Blender CLI automation", owner: "R2-D2", status: "Ready", priority: "Medium", due: "", nextStep: "CLI-Anything installed, Phase 1 scope defined", blockers: "", deliverable: "Automated 3D pipeline", notes: ""),
        ParsedTask(id: "TASK-006", title: "GUI control layer research", owner: "Qui-Gon", status: "Inbox", priority: "High", due: "", nextStep: "Research approaches for GUI automation", blockers: "", deliverable: "Major autonomy unlock", notes: ""),
    ]

    func load() {
        isLoading = true
        errorText = nil
        Task {
            if let content = try? String(contentsOfFile: Self.filePath, encoding: .utf8) {
                let parsed = parseTaskBoard(from: content)
                if parsed.isEmpty {
                    tasks = Self.seed
                    save()
                } else {
                    tasks = parsed
                    validateTaskStatuses(parsed)
                }
                lastContentHash = content.hashValue
            } else {
                tasks = Self.seed
                save()
            }
            loadCompanionData()
            isLoading = false
            startFileWatcher()
        }
    }

    func save() {
        suppressNextReload = true
        let markdown = serializeTaskBoard(tasks)
        try? markdown.write(toFile: Self.filePath, atomically: true, encoding: .utf8)
        lastContentHash = markdown.hashValue
    }

    // MARK: - File Watcher
    //
    // Two-layer approach:
    //   1. DispatchSource watches the file descriptor for write/rename/delete events.
    //      On rename (atomic save), we tear down and re-create the source on the new inode.
    //   2. A 4-second poll timer catches anything the dispatch source misses (belt + suspenders).

    func startFileWatcher() {
        stopFileWatcher()
        installDispatchSource()
        startPollTimer()
    }

    private func installDispatchSource() {
        fileWatcherSource?.cancel()
        fileWatcherSource = nil
        if fileDescriptor >= 0 { close(fileDescriptor); fileDescriptor = -1 }

        let path = Self.filePath
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let flags = source.data
            // Debounce — agents may do rapid writes
            Thread.sleep(forTimeInterval: 0.3)
            DispatchQueue.main.async {
                if self.suppressNextReload {
                    self.suppressNextReload = false
                    // After an atomic save the fd is stale — reinstall watcher on new inode
                    if flags.contains(.rename) { self.installDispatchSource() }
                    return
                }
                self.reloadFromDiskIfChanged()
                // Atomic writes rename the temp file over the original → old fd is dead.
                // Re-open on the new file so we keep watching.
                if flags.contains(.rename) || flags.contains(.delete) {
                    self.installDispatchSource()
                }
            }
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 { close(fd) }
            self?.fileDescriptor = -1
        }

        source.resume()
        fileWatcherSource = source
    }

    private func startPollTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in self.reloadFromDiskIfChanged() }
        }
    }

    func stopFileWatcher() {
        pollTimer?.invalidate()
        pollTimer = nil
        fileWatcherSource?.cancel()
        fileWatcherSource = nil
        if fileDescriptor >= 0 { close(fileDescriptor); fileDescriptor = -1 }
    }

    /// Re-parse the markdown file only if it actually changed (hash comparison)
    private func reloadFromDiskIfChanged() {
        guard let content = try? String(contentsOfFile: Self.filePath, encoding: .utf8) else { return }
        let hash = content.hashValue
        guard hash != lastContentHash else { return }
        lastContentHash = hash
        let parsed = parseTaskBoard(from: content)
        guard !parsed.isEmpty else { return }
        tasks = parsed
        validateTaskStatuses(parsed)
        loadCompanionData()
    }

    deinit {
        pollTimer?.invalidate()
        fileWatcherSource?.cancel()
        fileWatcherSource = nil
        if fileDescriptor >= 0 { close(fileDescriptor) }
    }

    func tasksInLane(_ lane: String) -> [ParsedTask] {
        tasks.filter { $0.status.lowercased() == lane.lowercased() }
    }

    // MARK: - Status Validation

    /// Canonical lane names as defined in TASKBOARD-FORMAT-CONTRACT.md.
    /// If a task arrives from disk with a status not in this set it will render in no lane —
    /// a silent disappearance that is very hard to debug.  validateTaskStatuses() surfaces
    /// those tasks immediately in the Xcode console so the author can correct the value.
    private static let canonicalLanes: Set<String> = [
        "inbox", "ready", "in progress", "review", "blocked", "done"
    ]

    private func validateTaskStatuses(_ parsed: [ParsedTask]) {
        let invalid = parsed.filter { !Self.canonicalLanes.contains($0.status.lowercased()) }
        guard !invalid.isEmpty else { return }
        for task in invalid {
            print("⚠️ TaskBoardStore: \(task.id) (\"\(task.title)\") has unrecognized status '\(task.status)' — task will not appear in any lane")
        }
        // Surface a transient warning in the UI so Andrew can spot rogue statuses at a glance.
        let ids = invalid.map { $0.id }.joined(separator: ", ")
        errorText = "Unrecognized status on: \(ids) — check TASK_BOARD.md"
    }

    // MARK: - Mutations (with activity logging)

    func updateTask(_ taskId: String, field: String, oldValue: String, newValue: String, apply: (inout ParsedTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        apply(&tasks[index])
        save()
        logActivity(taskId: taskId, action: "Updated \(field)", fieldChanged: field, oldValue: oldValue, newValue: newValue)
    }

    func moveTask(_ taskId: String, to newStatus: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        let old = tasks[index].status
        guard old != newStatus else { return }
        tasks[index].status = newStatus
        save()
        logActivity(taskId: taskId, action: "Moved from \(old) to \(newStatus)", fieldChanged: "status", oldValue: old, newValue: newStatus)
    }

    func addTask(title: String, owner: String, status: String = "Inbox", priority: String = "Medium") {
        let nextId = (tasks.compactMap { id -> Int? in
            let digits = id.id.replacingOccurrences(of: "TASK-", with: "")
            return Int(digits)
        }.max() ?? 0) + 1
        let taskId = String(format: "TASK-%03d", nextId)
        let task = ParsedTask(id: taskId, title: title, owner: owner, status: status, priority: priority, due: "", nextStep: "", blockers: "", deliverable: "", notes: "")
        tasks.append(task)
        save()
        logActivity(taskId: taskId, action: "Created task", fieldChanged: nil, oldValue: nil, newValue: nil)
    }

    func deleteTask(_ taskId: String) {
        tasks.removeAll { $0.id == taskId }
        save()
        logActivity(taskId: taskId, action: "Deleted task", fieldChanged: nil, oldValue: nil, newValue: nil)
    }

    // MARK: - Activity Log

    func activitiesForTask(_ taskId: String) -> [TaskActivity] {
        activities.filter { $0.taskId == taskId }.sorted { $0.timestamp > $1.timestamp }
    }

    private func logActivity(taskId: String, action: String, fieldChanged: String?, oldValue: String?, newValue: String?) {
        let entry = TaskActivity(taskId: taskId, timestamp: Date(), author: "Andrew", action: action, fieldChanged: fieldChanged, oldValue: oldValue, newValue: newValue)
        activities.append(entry)
        saveActivities()
    }

    // MARK: - Comments

    func commentsForTask(_ taskId: String) -> [TaskComment] {
        comments.filter { $0.taskId == taskId }.sorted { $0.timestamp > $1.timestamp }
    }

    func addComment(taskId: String, text: String, author: String = "Andrew") {
        let comment = TaskComment(taskId: taskId, timestamp: Date(), author: author, text: text)
        comments.append(comment)
        saveComments()
        logActivity(taskId: taskId, action: "Added comment", fieldChanged: nil, oldValue: nil, newValue: nil)
    }

    func deleteComment(_ commentId: UUID) {
        comments.removeAll { $0.id == commentId }
        saveComments()
    }

    // MARK: - Checklists

    func checklistForTask(_ taskId: String) -> TaskChecklist {
        if let existing = checklists.first(where: { $0.taskId == taskId }) {
            return existing
        }
        let new = TaskChecklist(taskId: taskId, items: [])
        checklists.append(new)
        return new
    }

    func addChecklistItem(taskId: String, text: String) {
        if let idx = checklists.firstIndex(where: { $0.taskId == taskId }) {
            checklists[idx].items.append(TaskChecklist.ChecklistItem(text: text, completed: false))
        } else {
            checklists.append(TaskChecklist(taskId: taskId, items: [TaskChecklist.ChecklistItem(text: text, completed: false)]))
        }
        saveChecklists()
    }

    func toggleChecklistItem(taskId: String, itemId: UUID) {
        guard let cIdx = checklists.firstIndex(where: { $0.taskId == taskId }),
              let iIdx = checklists[cIdx].items.firstIndex(where: { $0.id == itemId }) else { return }
        checklists[cIdx].items[iIdx].completed.toggle()
        saveChecklists()
    }

    func deleteChecklistItem(taskId: String, itemId: UUID) {
        guard let cIdx = checklists.firstIndex(where: { $0.taskId == taskId }) else { return }
        checklists[cIdx].items.removeAll { $0.id == itemId }
        saveChecklists()
    }

    // MARK: - Persistence (companion files)

    private func loadCompanionData() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: URL(fileURLWithPath: Self.activityPath)),
           let decoded = try? decoder.decode([TaskActivity].self, from: data) {
            activities = decoded
        }
        if let data = try? Data(contentsOf: URL(fileURLWithPath: Self.commentsPath)),
           let decoded = try? decoder.decode([TaskComment].self, from: data) {
            comments = decoded
        }
        if let data = try? Data(contentsOf: URL(fileURLWithPath: Self.checklistsPath)),
           let decoded = try? decoder.decode([TaskChecklist].self, from: data) {
            checklists = decoded
        }
    }

    private func saveActivities() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(activities) {
            try? data.write(to: URL(fileURLWithPath: Self.activityPath), options: .atomic)
        }
    }

    private func saveComments() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(comments) {
            try? data.write(to: URL(fileURLWithPath: Self.commentsPath), options: .atomic)
        }
    }

    private func saveChecklists() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(checklists) {
            try? data.write(to: URL(fileURLWithPath: Self.checklistsPath), options: .atomic)
        }
    }
}

// MARK: - View (legacy — Tasks tab now uses FlowBoardView(embedded: true))

struct TaskBoardView: View {
    @StateObject private var store = TaskBoardStore()
    private let lanes = ["In Progress", "Review", "Blocked", "Ready", "Inbox", "Done"]

    var body: some View {
        FlowBoardView(embedded: true)
    }
}
