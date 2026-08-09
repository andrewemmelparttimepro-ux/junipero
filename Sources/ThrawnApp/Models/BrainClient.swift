import Foundation

// MARK: - NDAI Brain client
// Fire-and-forget writer to the Brain's token-gated ingest endpoint. The local
// JSONL flight-recorder files remain the debug cache; the Brain is the system
// of record for fleet events and credential health. Every call here is
// non-blocking and must never fail into a caller path — a dead network makes
// the fleet quieter upstream, never broken locally.
final class BrainClient: @unchecked Sendable {
    static let shared = BrainClient()

    private struct Config {
        let url: URL
        let token: String
    }

    private let queue = DispatchQueue(label: "thrawn.brain-client")
    private let session: URLSession
    private let config: Config?

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        session = URLSession(configuration: cfg)

        let path = ThrawnPaths.appSupportDir.appendingPathComponent("brain.json")
        if let data = try? Data(contentsOf: path),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let urlString = object["url"] as? String,
           let url = URL(string: urlString),
           let token = object["ingest_token"] as? String {
            config = Config(url: url, token: token)
        } else {
            config = nil
            print("⚠️ BrainClient: no brain.json — Brain reporting disabled")
        }
    }

    /// Mirror a fleet event to the Brain's append-only ledger.
    func postEvent(
        agentSlug: String,
        actor: String? = nil,
        kind: String,
        status: String? = nil,
        summary: String? = nil,
        detail: [String: Any] = [:]
    ) {
        var row: [String: Any] = [
            "agent_slug": agentSlug,
            "actor": actor ?? agentSlug,
            "kind": kind,
            "detail": detail,
        ]
        if let status { row["status"] = String(status.prefix(40)) }
        if let summary { row["summary"] = String(summary.prefix(500)) }
        post(table: "agent_events", rows: [row])
    }

    /// Upsert an agent × provider credential state.
    func postCredentialStatus(
        agentSlug: String,
        provider: String,
        state: String,
        detail: String? = nil,
        account: String? = nil
    ) {
        var row: [String: Any] = [
            "agent_slug": agentSlug,
            "provider": provider,
            "state": state,
            "checked_at": ISO8601DateFormatter().string(from: Date()),
        ]
        if let detail { row["detail"] = String(detail.prefix(300)) }
        if let account { row["account"] = account }
        if state == "ready" {
            row["last_ok_at"] = ISO8601DateFormatter().string(from: Date())
        }
        post(table: "credential_status", rows: [row], upsert: true)
    }

    // MARK: - Unified feed (Phase 3)

    struct FeedEvent: Identifiable, Decodable {
        let id: Int64
        let at: Date
        let agentSlug: String
        let actor: String
        let kind: String
        let status: String?
        let summary: String?

        enum CodingKeys: String, CodingKey {
            case id, at, actor, kind, status, summary
            case agentSlug = "agent_slug"
        }
    }

    /// Fetch the most recent events across the whole stable — local fleet,
    /// deployed agents, watchdog, proofs — newest first.
    func fetchFeed(limit: Int = 120, completion: @escaping @MainActor ([FeedEvent]) -> Void) {
        guard let config else {
            Task { @MainActor in completion([]) }
            return
        }
        var request = URLRequest(url: config.url.appendingPathComponent("functions/v1/ingest"))
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["action": "feed", "limit": limit])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.token, forHTTPHeaderField: "x-brain-token")

        struct FeedResponse: Decodable {
            let ok: Bool
            let events: [FeedEvent]
        }
        session.dataTask(with: request) { data, _, _ in
            let decoder = JSONDecoder()
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoPlain = ISO8601DateFormatter()
            decoder.dateDecodingStrategy = .custom { d in
                let raw = try d.singleValueContainer().decode(String.self)
                // Postgres emits "2026-08-08 23:00:59.9+00" or ISO with T.
                let normalized = raw.replacingOccurrences(of: " ", with: "T")
                if let date = iso.date(from: normalized) ?? isoPlain.date(from: normalized) {
                    return date
                }
                return iso.date(from: normalized + "Z") ?? Date.distantPast
            }
            let events = data.flatMap { try? decoder.decode(FeedResponse.self, from: $0).events } ?? []
            Task { @MainActor in completion(events) }
        }.resume()
    }

    // MARK: - Board mirroring (Phase 2 dual-write)
    // The Markdown board stays authoritative while every applied dispatch is
    // replayed into the Brain, so parity is provable before the flip.

    private static let fieldColumns: [String: String] = [
        "status": "status", "priority": "priority", "owner": "owner_slug",
        "title": "title", "notes": "body", "blockers": "blockers",
        "next step": "next_step",
    ]
    private static let ownerSlugs: [String: String] = [
        "thrawn": "thrawn", "sir davos": "sentinel", "sentinel": "sentinel",
        "samwell tarly": "archivist", "samwell": "archivist", "archivist": "archivist",
        "dwight": "dwight", "steven": "steven", "andrew": "andrew",
    ]

    static func brainSlug(_ name: String) -> String {
        ownerSlugs[name.trimmingCharacters(in: .whitespaces).lowercased()]
            ?? name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func brainStatus(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespaces).lowercased() {
        case "done": return "done"
        case "in progress": return "in_progress"
        case "review": return "review"
        case "blocked": return "blocked"
        default: return "ready"
        }
    }

    private static func brainPriority(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespaces).lowercased() {
        case "high", "p0", "p1": return "high"
        case "low", "p3", "p4": return "low"
        default: return "medium"
        }
    }

    private static func ticketNumber(_ taskId: String) -> Int? {
        Int(taskId.uppercased().replacingOccurrences(of: "TASK-", with: ""))
    }

    /// Mirror one applied field mutation. Done-moves must go through
    /// `mirrorDone` instead so evidence lands atomically with the move.
    func mirrorFieldChange(taskId: String, field: String, value: String, actor: String) {
        guard let ticket = Self.ticketNumber(taskId) else { return }
        let key = field.trimmingCharacters(in: .whitespaces).lowercased()
        if key == "deliverable" {
            postAction([
                "action": "deliverable_add", "ticket_no": ticket,
                "agent_slug": Self.brainSlug(actor), "artifact_path": value,
            ])
            return
        }
        guard let column = Self.fieldColumns[key] else {
            postAction([
                "action": "task_comment", "ticket_no": ticket,
                "actor": Self.brainSlug(actor), "text": "\(field): \(value)",
            ])
            return
        }
        var mapped = value
        if column == "status" { mapped = Self.brainStatus(value) }
        if column == "priority" { mapped = Self.brainPriority(value) }
        if column == "owner_slug" { mapped = Self.brainSlug(value) }
        postAction([
            "action": "task_update", "ticket_no": ticket,
            "field": column, "value": mapped, "actor": Self.brainSlug(actor),
        ])
    }

    /// Mirror a move to Done together with its evidence pointer.
    func mirrorDone(taskId: String, deliverablePath: String?, actor: String) {
        guard let ticket = Self.ticketNumber(taskId) else { return }
        var payload: [String: Any] = [
            "action": "task_done", "ticket_no": ticket, "actor": Self.brainSlug(actor),
        ]
        if let deliverablePath, !deliverablePath.isEmpty {
            payload["deliverable_path"] = deliverablePath
        }
        postAction(payload)
    }

    /// Mirror a created card, keeping the Markdown ticket number.
    func mirrorCreate(
        taskId: String, title: String, owner: String, status: String,
        priority: String, notes: String, actor: String, deliverable: String?
    ) {
        guard let ticket = Self.ticketNumber(taskId) else { return }
        var row: [String: Any] = [
            "ticket_no": ticket,
            "title": String(title.prefix(500)),
            "status": Self.brainStatus(status),
            "priority": Self.brainPriority(priority),
            "owner_slug": Self.brainSlug(owner),
            "created_by": Self.brainSlug(actor),
        ]
        if !notes.isEmpty { row["body"] = notes }
        post(table: "tasks", rows: [row])
        if let deliverable, !deliverable.isEmpty {
            postAction([
                "action": "deliverable_add", "ticket_no": ticket,
                "agent_slug": Self.brainSlug(actor), "artifact_path": deliverable,
            ])
        }
    }

    func mirrorNote(taskId: String, note: String, actor: String) {
        guard let ticket = Self.ticketNumber(taskId) else { return }
        postAction([
            "action": "task_comment", "ticket_no": ticket,
            "actor": Self.brainSlug(actor), "text": note,
        ])
    }

    private func postAction(_ payload: [String: Any], attempt: Int = 0) {
        guard let config else { return }
        guard JSONSerialization.isValidJSONObject(payload),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }
        var request = URLRequest(url: config.url.appendingPathComponent("functions/v1/ingest"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.token, forHTTPHeaderField: "x-brain-token")
        queue.async { [weak self] in
            guard let self else { return }
            self.session.dataTask(with: request) { _, response, error in
                let failed = error != nil
                    || ((response as? HTTPURLResponse).map { $0.statusCode >= 300 } ?? true)
                if failed && attempt == 0 {
                    self.queue.asyncAfter(deadline: .now() + 5) {
                        self.postAction(payload, attempt: 1)
                    }
                }
            }.resume()
        }
    }

    private func post(table: String, rows: [[String: Any]], upsert: Bool = false, attempt: Int = 0) {
        guard let config else { return }
        let payload: [String: Any] = ["table": table, "rows": rows, "upsert": upsert]
        guard JSONSerialization.isValidJSONObject(payload),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }
        var request = URLRequest(url: config.url.appendingPathComponent("functions/v1/ingest"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.token, forHTTPHeaderField: "x-brain-token")

        queue.async { [weak self] in
            guard let self else { return }
            let task = self.session.dataTask(with: request) { _, response, error in
                let failed = error != nil
                    || ((response as? HTTPURLResponse).map { $0.statusCode >= 300 } ?? true)
                if failed && attempt == 0 {
                    self.queue.asyncAfter(deadline: .now() + 5) {
                        self.post(table: table, rows: rows, upsert: upsert, attempt: 1)
                    }
                }
            }
            task.resume()
        }
    }
}
