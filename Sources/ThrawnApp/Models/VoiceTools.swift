import Foundation

// MARK: - Voice Tools
//
// The action layer behind the microphone. Voice turns don't just chat —
// they can read and move the board, check agent state, and read proof
// verdicts. Every call is executed natively in Swift (no shell round
// trip) so a spoken question answers in milliseconds, and every mutating
// call is gated by the same per-agent autonomy ladder that governs
// heartbeats.
//
// Two consumers share these definitions:
//   • The local fast lane, which speaks a compact text protocol.
//   • The Realtime service, which uses OpenAI function-calling schemas.
//
// Read tools never mutate. Write tools go through the existing
// pending-updates JSON pipeline — the same path heartbeat agents use —
// so the dispatcher, board backups, and audit log all behave identically
// whether a change came from a heartbeat or from Andrew's voice.

struct VoiceToolResult {
    let spoken: String
    var mutated: Bool = false
    var denied: Bool = false
}

@MainActor
final class VoiceTools: ObservableObject {
    private weak var scheduler: AgentScheduler?
    private weak var dispatcher: TaskDispatcher?

    /// Which agent's autonomy ladder governs voice actions. Voice is Andrew
    /// speaking to command, so Thrawn's ceiling applies.
    private let governingAgentId = "thrawn"

    init(scheduler: AgentScheduler? = nil, dispatcher: TaskDispatcher? = nil) {
        self.scheduler = scheduler
        self.dispatcher = dispatcher
    }

    func bind(scheduler: AgentScheduler?, dispatcher: TaskDispatcher?) {
        self.scheduler = scheduler
        self.dispatcher = dispatcher
    }

    // MARK: - Catalog

    struct ToolDef {
        let name: String
        let summary: String
        let args: [(name: String, type: String, required: Bool, desc: String)]
        /// Autonomy capability this maps to, and the level it needs.
        let capability: String
        let requires: AutonomyLevel
    }

    static let catalog: [ToolDef] = [
        ToolDef(
            name: "board_summary",
            summary: "Counts of live cards per lane plus who owns them. Use for 'what's going on', 'status', 'how's the board'.",
            args: [],
            capability: "board", requires: .observe
        ),
        ToolDef(
            name: "list_tasks",
            summary: "List cards, optionally filtered. Use for 'what's blocked', 'what's Davos working on', 'what's ready'.",
            args: [
                ("status", "string", false, "Inbox, Ready, In Progress, Review, Blocked, or Done"),
                ("owner", "string", false, "Agent name, e.g. Thrawn, Dwight, Samwell Tarly, Sir Davos, Steven"),
            ],
            capability: "board", requires: .observe
        ),
        ToolDef(
            name: "task_detail",
            summary: "Full detail for one card including notes, blockers, and next step.",
            args: [("task_id", "string", true, "Card id such as TASK-021")],
            capability: "board", requires: .observe
        ),
        ToolDef(
            name: "update_task",
            summary: "Change a field on a card — status, owner, notes, next step. Use for 'move task 21 to done', 'assign it to Davos'.",
            args: [
                ("task_id", "string", true, "Card id such as TASK-021"),
                ("field", "string", true, "Status, Owner, Priority, Notes, or Next step"),
                ("value", "string", true, "New value"),
            ],
            capability: "board", requires: .execute
        ),
        ToolDef(
            name: "create_task",
            summary: "Put a new card on the board. Use when Andrew says 'add a task', 'remind me to', 'put it on the board'.",
            args: [
                ("title", "string", true, "Short card title"),
                ("owner", "string", false, "Agent name, defaults to Thrawn"),
                ("notes", "string", false, "Context or source for the card"),
            ],
            capability: "board", requires: .execute
        ),
        ToolDef(
            name: "agent_status",
            summary: "Which agents are running or idle and when each last woke.",
            args: [],
            capability: "board", requires: .observe
        ),
        ToolDef(
            name: "latest_proofs",
            summary: "Most recent Product Sentinel verdict for each product.",
            args: [],
            capability: "local", requires: .observe
        ),
        ToolDef(
            name: "trigger_agent",
            summary: "Wake an agent right now instead of waiting for its heartbeat.",
            args: [("agent", "string", true, "Agent name or id: thrawn, dwight, archivist, sentinel, steven")],
            capability: "local", requires: .execute
        ),
    ]

    /// Compact tool protocol for the local fast-lane model.
    static var promptCatalog: String {
        var lines: [String] = []
        for tool in catalog {
            let argList = tool.args.isEmpty
                ? "none"
                : tool.args.map { "\($0.name)\($0.required ? "" : "?")" }.joined(separator: ", ")
            lines.append("- \(tool.name)(\(argList)) — \(tool.summary)")
        }
        return lines.joined(separator: "\n")
    }

    /// OpenAI function-calling schemas for the Realtime session.
    static var realtimeSchemas: [[String: Any]] {
        catalog.map { tool in
            var properties: [String: Any] = [:]
            var required: [String] = []
            for arg in tool.args {
                properties[arg.name] = ["type": arg.type, "description": arg.desc]
                if arg.required { required.append(arg.name) }
            }
            return [
                "type": "function",
                "name": tool.name,
                "description": tool.summary,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": required,
                ] as [String: Any],
            ]
        }
    }

    // MARK: - Execution

    func execute(name: String, arguments: [String: String]) -> VoiceToolResult {
        guard let def = Self.catalog.first(where: { $0.name == name }) else {
            return VoiceToolResult(spoken: "I don't have a tool called \(name).")
        }

        // Autonomy gate — identical ceiling the heartbeats obey.
        let level = AgentAutonomyStore.effectiveLevel(agentId: governingAgentId, capability: def.capability)
        guard level >= def.requires else {
            let capTitle = AutonomyCatalog.capability(def.capability)?.title ?? def.capability
            FlightRecorder.logEvent(
                category: "voice-tool", action: "denied",
                detail: "\(name) needs \(def.requires.rawValue), ceiling is \(level.rawValue)"
            )
            return VoiceToolResult(
                spoken: "That needs \(def.requires.label.lowercased()) authority for \(capTitle.lowercased()), but the ceiling is set to \(level.label.lowercased()). Raise it from the agent's gear panel first.",
                denied: true
            )
        }

        FlightRecorder.logEvent(category: "voice-tool", action: "run", detail: "\(name) \(arguments)")

        switch name {
        case "board_summary":  return boardSummary()
        case "list_tasks":     return listTasks(status: arguments["status"], owner: arguments["owner"])
        case "task_detail":    return taskDetail(id: arguments["task_id"] ?? "")
        case "update_task":    return updateTask(id: arguments["task_id"] ?? "",
                                                 field: arguments["field"] ?? "",
                                                 value: arguments["value"] ?? "")
        case "create_task":    return createTask(title: arguments["title"] ?? "",
                                                 owner: arguments["owner"],
                                                 notes: arguments["notes"])
        case "agent_status":   return agentStatus()
        case "latest_proofs":  return latestProofs()
        case "trigger_agent":  return triggerAgent(arguments["agent"] ?? "")
        default:
            return VoiceToolResult(spoken: "I don't know how to run \(name) yet.")
        }
    }

    // MARK: - Board model

    struct BoardCard {
        var id: String
        var fields: [String: String] = [:]
        var title: String { fields["Title"] ?? "untitled" }
        var owner: String { fields["Owner"] ?? "unassigned" }
        var status: String { fields["Status"] ?? "Inbox" }
        var isDone: Bool { status.caseInsensitiveCompare("Done") == .orderedSame }
    }

    private var boardURL: URL { ThrawnPaths.opsDir.appendingPathComponent("TASK_BOARD.md") }

    private func loadBoard() -> [BoardCard] {
        guard let text = try? String(contentsOf: boardURL, encoding: .utf8) else { return [] }
        var cards: [BoardCard] = []
        var current: BoardCard?
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("### TASK-") {
                if let current { cards.append(current) }
                current = BoardCard(id: String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces))
                continue
            }
            guard current != nil, line.hasPrefix("- ") else { continue }
            let body = String(line.dropFirst(2))
            guard let colon = body.firstIndex(of: ":") else { continue }
            let key = String(body[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(body[body.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { current?.fields[key] = value }
        }
        if let current { cards.append(current) }
        // The template block at the top of the board isn't a real card.
        return cards.filter { $0.id != "TASK-000" }
    }

    /// Speech-friendly card id — "TASK-021" reads badly as a whole token.
    private func spokenId(_ id: String) -> String {
        let digits = id.replacingOccurrences(of: "TASK-", with: "")
        let number = Int(digits) ?? 0
        return "task \(number)"
    }

    // MARK: - Read tools

    private func boardSummary() -> VoiceToolResult {
        let cards = loadBoard()
        let live = cards.filter { !$0.isDone }
        guard !live.isEmpty else {
            return VoiceToolResult(spoken: "The board is clear. \(cards.count) cards total, all done.")
        }

        var byStatus: [String: Int] = [:]
        for card in live { byStatus[card.status, default: 0] += 1 }
        let laneOrder = ["Blocked", "In Progress", "Review", "Ready", "Inbox"]
        let lanes = laneOrder.compactMap { lane -> String? in
            guard let n = byStatus[lane], n > 0 else { return nil }
            return "\(n) \(lane.lowercased())"
        }.joined(separator: ", ")

        var byOwner: [String: Int] = [:]
        for card in live { byOwner[card.owner, default: 0] += 1 }
        let owners = byOwner.sorted { $0.value > $1.value }.prefix(3)
            .map { "\($0.key) has \($0.value)" }.joined(separator: ", ")

        var spoken = "\(live.count) live cards: \(lanes)."
        if !owners.isEmpty { spoken += " \(owners)." }
        if let blocked = byStatus["Blocked"], blocked > 0 {
            spoken += " The blocked ones need you."
        }
        return VoiceToolResult(spoken: spoken)
    }

    private func listTasks(status: String?, owner: String?) -> VoiceToolResult {
        var cards = loadBoard().filter { !$0.isDone }
        // An unrecognizable filter is dropped rather than applied — returning
        // "nothing matches" because the model said "progressed" instead of
        // "In Progress" would be a confidently wrong answer.
        if let status, let lane = Self.canonicalStatus(status) {
            cards = cards.filter { $0.status.caseInsensitiveCompare(lane) == .orderedSame }
        }
        if let owner, let target = Self.canonicalOwnerKey(owner) {
            cards = cards.filter { Self.canonicalOwnerKey($0.owner) == target }
        }
        guard !cards.isEmpty else {
            return VoiceToolResult(spoken: "Nothing matches that.")
        }
        let head = cards.prefix(5).map { card in
            "\(spokenId(card.id)), \(card.title), owned by \(card.owner), \(card.status.lowercased())"
        }.joined(separator: ". ")
        let more = cards.count > 5 ? " Plus \(cards.count - 5) more." : ""
        return VoiceToolResult(spoken: head + "." + more)
    }

    private func taskDetail(id: String) -> VoiceToolResult {
        let wanted = normalizeTaskId(id)
        guard let card = loadBoard().first(where: { $0.id == wanted }) else {
            return VoiceToolResult(spoken: "I can't find \(spokenId(wanted)) on the board.")
        }
        var parts = ["\(spokenId(card.id)): \(card.title). Owner \(card.owner), status \(card.status)"]
        if let next = card.fields["Next step"], !next.isEmpty {
            parts.append("Next step: \(truncate(next, 260))")
        }
        if let blockers = card.fields["Blockers"], !blockers.isEmpty,
           blockers.lowercased() != "none" {
            parts.append("Blocked on: \(truncate(blockers, 200))")
        }
        return VoiceToolResult(spoken: parts.joined(separator: ". ") + ".")
    }

    private func agentStatus() -> VoiceToolResult {
        guard let scheduler else {
            return VoiceToolResult(spoken: "The scheduler isn't available right now.")
        }
        let running = scheduler.runningAgents
        let enabled = scheduler.agents.filter { $0.enabled }
        var spoken = "\(enabled.count) agents enabled."
        if running.isEmpty {
            spoken += " None running right now."
        } else {
            let names = enabled.filter { running.contains($0.id) }.map(\.name)
            spoken += " Running now: \(names.joined(separator: ", "))."
        }
        if let latest = scheduler.lastRunTimes.max(by: { $0.value < $1.value }),
           let agent = enabled.first(where: { $0.id == latest.key }) {
            let mins = Int(Date().timeIntervalSince(latest.value) / 60)
            spoken += " \(agent.name) woke \(mins) minute\(mins == 1 ? "" : "s") ago."
        }
        return VoiceToolResult(spoken: spoken)
    }

    private func latestProofs() -> VoiceToolResult {
        let proofsRoot = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/proofs")
        let fm = FileManager.default
        guard let products = try? fm.contentsOfDirectory(atPath: proofsRoot.path), !products.isEmpty else {
            return VoiceToolResult(spoken: "No proof runs on disk yet.")
        }
        var lines: [String] = []
        for product in products.sorted() where !product.hasPrefix(".") {
            let productDir = proofsRoot.appendingPathComponent(product)
            guard let days = try? fm.contentsOfDirectory(atPath: productDir.path),
                  let newestDay = days.filter({ !$0.hasPrefix(".") }).sorted().last else { continue }
            let dayDir = productDir.appendingPathComponent(newestDay)
            guard let runs = try? fm.contentsOfDirectory(atPath: dayDir.path),
                  let newestRun = runs.filter({ !$0.hasPrefix(".") }).sorted().last else { continue }
            let verdict = dayDir.appendingPathComponent(newestRun).appendingPathComponent("verdict.md")
            guard let text = try? String(contentsOf: verdict, encoding: .utf8) else { continue }
            let lower = text.lowercased()
            let state = lower.contains("fail") ? "failing" : (lower.contains("pass") ? "passing" : "unclear")
            lines.append("\(product) \(state) as of \(newestDay)")
        }
        guard !lines.isEmpty else {
            return VoiceToolResult(spoken: "No readable proof verdicts yet.")
        }
        return VoiceToolResult(spoken: lines.joined(separator: ". ") + ".")
    }

    // MARK: - Write tools

    private func updateTask(id: String, field: String, value: String) -> VoiceToolResult {
        let wanted = normalizeTaskId(id)
        guard !wanted.isEmpty, !field.isEmpty, !value.isEmpty else {
            return VoiceToolResult(spoken: "I need a card, a field, and a value to change it.")
        }
        guard loadBoard().contains(where: { $0.id == wanted }) else {
            return VoiceToolResult(spoken: "I can't find \(spokenId(wanted)) on the board.")
        }
        let canonicalField = canonicalizeField(field)
        if canonicalField == "Status" {
            guard let match = Self.canonicalStatus(value) else {
                return VoiceToolResult(spoken: "\(value) isn't a lane. Use inbox, ready, in progress, review, blocked, or done.")
            }
            return writeUpdate(
                [["action": "move", "task_id": wanted, "field": "Status", "value": match, "agent": "Voice"]],
                spoken: "Moved \(spokenId(wanted)) to \(match)."
            )
        }
        return writeUpdate(
            [["action": "update", "task_id": wanted, "field": canonicalField, "value": value, "agent": "Voice"]],
            spoken: "Updated \(canonicalField.lowercased()) on \(spokenId(wanted))."
        )
    }

    private func createTask(title: String, owner: String?, notes: String?) -> VoiceToolResult {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            return VoiceToolResult(spoken: "What should the card say?")
        }
        let resolvedOwner = resolveAgentName(owner ?? "") ?? "Thrawn"
        var update: [String: Any] = [
            "action": "create",
            "task_id": "TASK-NEW",
            "title": cleanTitle,
            "owner": resolvedOwner,
            "status": "Ready",
            "priority": "Medium",
            "agent": "Voice",
        ]
        let sourceNote = "Source: Andrew by voice on \(Self.stamp()). \(notes ?? "")"
            .trimmingCharacters(in: .whitespaces)
        update["notes"] = sourceNote
        return writeUpdate([update], spoken: "Added it for \(resolvedOwner): \(cleanTitle).", mutated: true)
    }

    private func triggerAgent(_ raw: String) -> VoiceToolResult {
        guard let scheduler else {
            return VoiceToolResult(spoken: "The scheduler isn't available right now.")
        }
        guard let agent = matchAgent(raw, in: scheduler.agents) else {
            return VoiceToolResult(spoken: "I don't know an agent called \(raw).")
        }
        scheduler.triggerAgent(agent.id)
        return VoiceToolResult(spoken: "Waking \(agent.name) now.", mutated: true)
    }

    /// Write to the voice lane's own update file, then nudge the dispatcher so
    /// the change lands on the board immediately instead of on the next tick.
    private func writeUpdate(_ updates: [[String: Any]], spoken: String, mutated: Bool = true) -> VoiceToolResult {
        let dir = ThrawnPaths.opsDir.appendingPathComponent("pending-updates")
        let file = dir.appendingPathComponent("updates-voice.json")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // Merge with anything still queued so a fast second command can't
            // clobber the first before the dispatcher drains the file.
            var merged: [[String: Any]] = []
            if let existing = try? Data(contentsOf: file),
               let parsed = try? JSONSerialization.jsonObject(with: existing) as? [[String: Any]] {
                merged = parsed
            }
            merged.append(contentsOf: updates)
            let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted])
            try data.write(to: file, options: .atomic)
        } catch {
            FlightRecorder.logError(source: "voice-tool:write", message: error.localizedDescription)
            return VoiceToolResult(spoken: "I couldn't write that to the board: \(error.localizedDescription)")
        }
        dispatcher?.processAllUpdates()
        return VoiceToolResult(spoken: spoken, mutated: mutated)
    }

    // MARK: - Normalizing spoken input
    //
    // Speech gives us "task twenty one", "task 21", "TASK-21" — all the same
    // card. Field and agent names arrive equally loose.

    private func normalizeTaskId(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let digits = lowered.compactMap { $0.isNumber ? $0 : nil }
        if !digits.isEmpty, let n = Int(String(digits)) {
            return String(format: "TASK-%03d", n)
        }
        if let n = Self.spokenNumber(from: lowered) {
            return String(format: "TASK-%03d", n)
        }
        return raw.uppercased()
    }

    /// Map whatever the model or the speaker called a lane onto a real one.
    /// Returns nil when there's no confident match, so callers can drop the
    /// filter instead of silently returning an empty result.
    static func canonicalStatus(_ raw: String) -> String? {
        let t = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let table: [(keys: [String], lane: String)] = [
            (["inbox", "new", "unsorted", "needs routing"], "Inbox"),
            (["ready", "todo", "to do", "queued", "open"], "Ready"),
            (["in progress", "inprogress", "progress", "progressed", "working",
              "active", "started", "doing"], "In Progress"),
            (["review", "reviewing", "in review", "awaiting review"], "Review"),
            (["blocked", "block", "stuck", "waiting"], "Blocked"),
            (["done", "complete", "completed", "finished", "closed"], "Done"),
        ]
        for entry in table where entry.keys.contains(t) { return entry.lane }
        for entry in table where entry.keys.contains(where: { t.contains($0) }) { return entry.lane }
        return nil
    }

    /// Comparison key that survives "SirDavos", "sir davos", and "Davos".
    static func canonicalOwnerKey(_ raw: String) -> String? {
        let compact = raw.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        guard !compact.isEmpty else { return nil }
        let table: [(keys: [String], key: String)] = [
            (["thrawn", "command", "lead"], "thrawn"),
            (["dwight", "router"], "dwight"),
            (["samwelltarly", "samwell", "sam", "tarly", "archivist"], "samwell"),
            (["sirdavos", "davos", "sentinel"], "davos"),
            (["steven", "stephen"], "steven"),
            (["andrew", "me", "myself"], "andrew"),
        ]
        for entry in table where entry.keys.contains(compact) { return entry.key }
        for entry in table where entry.keys.contains(where: { compact.contains($0) }) { return entry.key }
        return compact
    }

    private func canonicalizeField(_ raw: String) -> String {
        switch raw.lowercased().trimmingCharacters(in: .whitespaces) {
        case "status", "lane", "state": return "Status"
        case "owner", "assignee", "who": return "Owner"
        case "priority": return "Priority"
        case "notes", "note": return "Notes"
        case "next", "next step", "nextstep": return "Next step"
        case "blockers", "blocker": return "Blockers"
        default: return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }

    private func resolveAgentName(_ raw: String) -> String? {
        let lowered = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lowered.isEmpty else { return nil }
        let table: [(keys: [String], name: String)] = [
            (["thrawn", "command", "lead"], "Thrawn"),
            (["dwight", "router"], "Dwight"),
            (["samwell", "sam", "tarly", "archivist", "sandpro"], "Samwell Tarly"),
            (["davos", "sir davos", "sentinel", "hit zero", "hitzero"], "Sir Davos"),
            (["steven", "stephen", "spas"], "Steven"),
            (["andrew", "me", "myself"], "Andrew"),
        ]
        for entry in table where entry.keys.contains(where: { lowered.contains($0) }) {
            return entry.name
        }
        return nil
    }

    private func matchAgent(_ raw: String, in agents: [AgentHeartbeatConfig]) -> AgentHeartbeatConfig? {
        let lowered = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lowered.isEmpty else { return nil }
        if let direct = agents.first(where: { $0.id.lowercased() == lowered }) { return direct }
        if let byName = agents.first(where: { $0.name.lowercased().contains(lowered) }) { return byName }
        if let resolved = resolveAgentName(lowered),
           let byResolved = agents.first(where: { $0.name == resolved }) { return byResolved }
        return nil
    }

    private func truncate(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }

    private static func stamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        return fmt.string(from: Date())
    }

    /// "twenty one" → 21. Covers the range a board id realistically hits.
    static func spokenNumber(from text: String) -> Int? {
        let units = ["zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
                     "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
                     "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
                     "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
                     "nineteen": 19]
        let tens = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
                    "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]
        let words = text.replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: " ")
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
        var total: Int?
        var pending = 0
        for word in words {
            if let t = tens[word] {
                pending = t
                total = (total ?? 0) + t
            } else if let u = units[word] {
                if pending > 0 {
                    total = (total ?? 0) - pending + (pending + u)
                    pending = 0
                } else {
                    total = (total ?? 0) + u
                }
            }
        }
        return total
    }
}
