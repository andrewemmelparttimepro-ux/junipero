import Foundation

// MARK: - Voice Fast Lane
//
// Conversation is a latency problem, not a reasoning problem. The command
// thread runs a deep-reasoning route that regularly takes 30–120s — correct
// for closing a card, unusable for "what's on the board?".
//
// This lane answers spoken turns in three escalating steps, cheapest first:
//
//   1. Deterministic intent match — no model at all. "What's blocked?" is a
//      board query every time; asking an LLM to discover that is pure latency.
//      These answer in single-digit milliseconds.
//   2. Local small model (Ollama) — picks a tool or answers conversationally,
//      streaming into speech as clauses form.
//   3. Escalation to the command thread — for anything needing real reasoning
//      or authority, we say so out loud and hand off, rather than letting a 3B
//      model improvise about the business.
//
// Read tools return sentences that are already speakable, so a matched read
// answers without a second model round trip.

@MainActor
final class VoiceFastLane: ObservableObject {
    @Published private(set) var lastRouteLabel: String = "idle"

    private var tools: VoiceTools
    private weak var voice: VoiceService?

    /// Small local model. Chosen for time-to-first-token, not depth — every
    /// judgment call it might get wrong is either a tool call (deterministic
    /// execution) or an escalation (handed to the real route).
    var model: String = "llama3.2:3b"
    var baseURL: String = "http://127.0.0.1:11434"

    /// Set when the lane decides the turn belongs to the command thread.
    var onEscalate: ((String) -> Void)?

    init(tools: VoiceTools? = nil, voice: VoiceService? = nil) {
        self.tools = tools ?? VoiceTools()
        self.voice = voice
    }

    func bind(tools: VoiceTools, voice: VoiceService) {
        self.tools = tools
        self.voice = voice
    }

    // MARK: - Entry point

    /// Handle one spoken turn end to end: decide, act, speak.
    func handle(utterance: String) async {
        let text = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let started = Date()

        // Step 1 — deterministic intents.
        if let intent = Self.deterministicIntent(for: text) {
            let result = tools.execute(name: intent.tool, arguments: intent.args)
            speak(result.spoken)
            lastRouteLabel = "instant"
            logTurn(route: "deterministic", tool: intent.tool, started: started)
            return
        }

        // Step 2 — local model decides between tool, answer, or escalation.
        do {
            let decision = try await runLocalModel(utterance: text)
            switch decision {
            case .tool(let name, let args):
                let result = tools.execute(name: name, arguments: args)
                speak(result.spoken)
                lastRouteLabel = "local+tool"
                logTurn(route: "local-tool", tool: name, started: started)
            case .spoken(let reply):
                // runLocalModel speaks it only after the claim check passes.
                lastRouteLabel = "local"
                logTurn(route: "local", tool: reply.isEmpty ? "empty" : "chat", started: started)
            case .escalate:
                escalate(text, reason: "model requested depth")
                logTurn(route: "escalate", tool: "-", started: started)
            }
        } catch {
            FlightRecorder.logEvent(
                category: "voice-lane", action: "local-failed",
                detail: error.localizedDescription
            )
            escalate(text, reason: "local lane unavailable")
        }
    }

    // MARK: - Step 1: deterministic intents

    struct Intent {
        let tool: String
        var args: [String: String] = [:]
    }

    /// Phrases that map to exactly one tool, every time. Deliberately narrow —
    /// a false match here would answer the wrong question confidently, so
    /// anything ambiguous falls through to the model.
    static func deterministicIntent(for raw: String) -> Intent? {
        let t = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "?!."))

        let boardSummary = [
            "what's on the board", "whats on the board", "what is on the board",
            "board status", "status", "status report", "how's the board", "hows the board",
            "what's going on", "whats going on", "where are we", "sitrep", "brief me",
        ]
        if boardSummary.contains(where: { t == $0 || t.hasPrefix($0) }) {
            return Intent(tool: "board_summary")
        }

        let blocked = ["what's blocked", "whats blocked", "what is blocked",
                       "anything blocked", "what needs me", "what do you need from me",
                       "what needs my attention", "blockers"]
        if blocked.contains(where: { t == $0 || t.hasPrefix($0) }) {
            return Intent(tool: "list_tasks", args: ["status": "Blocked"])
        }

        let ready = ["what's ready", "whats ready", "what is ready", "what's next", "whats next"]
        if ready.contains(where: { t == $0 || t.hasPrefix($0) }) {
            return Intent(tool: "list_tasks", args: ["status": "Ready"])
        }

        let review = ["what's in review", "whats in review", "anything to review",
                      "what needs review", "what's waiting on me", "whats waiting on me"]
        if review.contains(where: { t == $0 || t.hasPrefix($0) }) {
            return Intent(tool: "list_tasks", args: ["status": "Review"])
        }

        let agents = ["agent status", "how are the agents", "who's running", "whos running",
                      "what are the agents doing", "roster"]
        if agents.contains(where: { t == $0 || t.hasPrefix($0) }) {
            return Intent(tool: "agent_status")
        }

        let proofs = ["proof status", "are the products up", "latest proofs",
                      "how are the products", "product health", "are the products passing",
                      "are the products healthy", "is everything up", "are we green"]
        if proofs.contains(where: { t == $0 || t.hasPrefix($0) }) {
            return Intent(tool: "latest_proofs")
        }

        // "wake Dwight" / "run Samwell now" — unambiguous and worth skipping
        // the model for, since it's a mutation the user expects to be instant.
        for verb in ["wake ", "run ", "trigger ", "fire "] where t.hasPrefix(verb) {
            let target = String(t.dropFirst(verb.count))
                .replacingOccurrences(of: " now", with: "")
                .replacingOccurrences(of: "'s heartbeat", with: "")
                .replacingOccurrences(of: " heartbeat", with: "")
                .trimmingCharacters(in: .whitespaces)
            let known = ["thrawn", "dwight", "samwell", "sam", "tarly",
                         "davos", "sir davos", "steven", "archivist", "sentinel"]
            if known.contains(target) {
                return Intent(tool: "trigger_agent", args: ["agent": target])
            }
        }

        // "add a task for Steven to …" — the model mis-routed this to a read
        // tool in testing, and a dropped instruction is worse than a wrong
        // read, so it gets handled here instead.
        for opener in ["add a task", "create a task", "new task", "put a task",
                       "add a card", "make a task", "remind me to", "put it on the board",
                       "add to the board"] where t.hasPrefix(opener) {
            var rest = String(t.dropFirst(opener.count)).trimmingCharacters(in: .whitespaces)
            var owner: String?
            // "for Steven to instrument clarity" → owner Steven, title the rest
            if rest.hasPrefix("for ") {
                let afterFor = String(rest.dropFirst(4))
                let names = ["thrawn", "dwight", "samwell tarly", "samwell", "sam",
                             "sir davos", "davos", "steven"]
                if let hit = names.first(where: { afterFor.hasPrefix($0) }) {
                    owner = hit
                    rest = String(afterFor.dropFirst(hit.count)).trimmingCharacters(in: .whitespaces)
                    if rest.hasPrefix("to ") { rest = String(rest.dropFirst(3)) }
                }
            }
            let title = rest.trimmingCharacters(in: .whitespaces)
            guard title.count >= 3 else { break }
            var args = ["title": title.prefix(1).uppercased() + title.dropFirst()]
            if let owner { args["owner"] = owner }
            return Intent(tool: "create_task", args: args)
        }

        // "tell me about task 21" / "what's task twenty one"
        if t.contains("task"), t.range(of: #"task\s+(\d+|[a-z\- ]+)"#, options: .regularExpression) != nil,
           ["tell me about", "what is", "what's", "whats", "detail", "read me", "describe"]
            .contains(where: { t.hasPrefix($0) }) {
            if let id = extractTaskId(from: t) {
                return Intent(tool: "task_detail", args: ["task_id": id])
            }
        }

        return nil
    }

    static func extractTaskId(from text: String) -> String? {
        if let match = text.range(of: #"task[\s\-]*(\d+)"#, options: .regularExpression) {
            let digits = text[match].compactMap { $0.isNumber ? $0 : nil }
            if !digits.isEmpty { return "TASK-\(String(digits))" }
        }
        if let taskWord = text.range(of: "task") {
            let tail = String(text[taskWord.upperBound...])
            if let n = VoiceTools.spokenNumber(from: tail) { return "TASK-\(n)" }
        }
        return nil
    }

    // MARK: - Step 2: local model

    enum Decision {
        case tool(String, [String: String])
        case spoken(String)
        case escalate
    }

    private func runLocalModel(utterance: String) async throws -> Decision {
        let system = buildSystemPrompt()
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw VoiceLaneError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "keep_alive": "30m",  // keep the model resident; cold loads cost seconds
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": utterance],
            ],
            "options": [
                "temperature": 0.3,
                "num_predict": 220,
                "top_p": 0.9,
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw VoiceLaneError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        // The reply is buffered rather than streamed straight into speech.
        // A 3B model asked about the business will happily invent board and
        // product state — observed directly in testing — and once a sentence
        // has been spoken it cannot be retracted. Conversational replies here
        // are one or two sentences, so buffering costs a couple hundred
        // milliseconds and buys the ability to refuse a claim before it is
        // ever said out loud. Long-form answers stream, but they come from
        // the real route via escalation.
        var accumulated = ""
        for try await line in bytes.lines {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? String {
                accumulated += content
            }
            if (json["done"] as? Bool) == true { break }
        }

        let trimmed = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .escalate }
        if trimmed.uppercased().hasPrefix("ESCALATE") { return .escalate }
        if let call = Self.parseToolCall(trimmed) { return .tool(call.0, call.1) }

        // Plain answer — only allowed through if it isn't asserting facts
        // about the business that no tool verified.
        if let redirect = Self.unverifiedClaimRedirect(in: trimmed) {
            FlightRecorder.logEvent(
                category: "voice-lane", action: "claim-blocked",
                detail: "redirected to \(redirect): \(trimmed.prefix(80))"
            )
            return redirect == "escalate" ? .escalate : .tool(redirect, [:])
        }

        speak(trimmed)
        return .spoken(trimmed)
    }

    /// Catch a conversational reply that asserts operational fact. The local
    /// model has no grounding for these claims, so instead of speaking them we
    /// answer the same question from real data.
    ///
    /// Returns the tool to answer with, "escalate", or nil to allow the reply.
    static func unverifiedClaimRedirect(in text: String) -> String? {
        let t = text.lowercased()

        let productWords = ["product", "sandpro", "hit zero", "spas", "cyclops",
                            "vaultage", "proof", "patrol", "passing", "failing", "clarity"]
        let boardWords = ["task", "card", "board", "lane", "blocked", "ready",
                          "in review", "backlog", "assigned"]
        let agentWords = ["dwight", "samwell", "davos", "steven", "agent", "heartbeat"]

        // A claim needs a subject AND something assertive about it: a number,
        // a state word, or a completion verb.
        let assertive = t.range(of: #"\b(\d+|no|none|all|several|some|few|many)\b"#,
                                options: .regularExpression) != nil
            || ["is ", "are ", "has ", "have ", "was ", "were ", "currently",
                "right now", "still", "'s ", "'re ", "proceeding", "on track",
                "according to", "looks ", "seems "].contains(where: { t.contains($0) })

        guard assertive else { return nil }

        if productWords.contains(where: { t.contains($0) }) { return "latest_proofs" }
        if boardWords.contains(where: { t.contains($0) }) { return "board_summary" }
        if agentWords.contains(where: { t.contains($0) }) { return "agent_status" }
        return nil
    }

    /// Tokens that mark a response as machinery rather than speech.
    private static var controlPrefixes: [String] {
        ["tool:", "escalate"] + VoiceTools.catalog.map(\.name)
    }

    /// The stream so far is a strict prefix of some control token — it could
    /// still turn into one, so hold off on speaking.
    static func mightBecomeControlResponse(_ head: String) -> Bool {
        let lowered = head.lowercased()
        guard !lowered.isEmpty, lowered.count < 24 else { return false }
        return controlPrefixes.contains { $0.hasPrefix(lowered) && $0 != lowered }
    }

    /// The stream has committed to being a control response.
    static func isControlResponse(_ head: String) -> Bool {
        let lowered = head.lowercased()
        return controlPrefixes.contains { lowered.hasPrefix($0) }
    }

    /// Recognizes a tool call in whatever shape the model emitted it.
    ///
    /// A small model asked for `TOOL: name {"a":"b"}` will also produce
    /// `TOOL: name(a=b)`, `name("b", a="c")`, or drop the prefix entirely —
    /// all observed from llama3.2:3b against this exact prompt. Anchoring on
    /// the known tool names instead of on the wrapper makes detection reliable,
    /// and it stays safe because a conversational sentence never opens with a
    /// tool identifier.
    static func parseToolCall(_ text: String) -> (String, [String: String])? {
        var working = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = working.range(of: "TOOL:", options: .caseInsensitive) {
            working = String(working[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        // The name must appear at the very start of the (post-prefix) text.
        let head = working.prefix(60).lowercased()
        guard let name = VoiceTools.catalog
            .map(\.name)
            .filter({ head.hasPrefix($0) })
            .max(by: { $0.count < $1.count })
        else { return nil }

        let tail = String(working.dropFirst(name.count))
        return (name, parseArguments(tail, for: name))
    }

    /// Accepts JSON objects, `key=value` pairs, and a leading bare/quoted
    /// value that maps onto the tool's first required argument.
    static func parseArguments(_ raw: String, for toolName: String) -> [String: String] {
        var args: [String: String] = [:]

        if let braceStart = raw.firstIndex(of: "{"),
           let braceEnd = raw.lastIndex(of: "}"),
           braceStart < braceEnd,
           let data = String(raw[braceStart...braceEnd]).data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in parsed { args[key] = String(describing: value) }
        }

        // key=value / key: "value"
        let pattern = #"([A-Za-z_]+)\s*[:=]\s*("[^"]*"|'[^']*'|[^,\)\}\n]+)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = raw as NSString
            for match in regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
                guard match.numberOfRanges >= 3 else { continue }
                let key = ns.substring(with: match.range(at: 1))
                var value = ns.substring(with: match.range(at: 2))
                    .trimmingCharacters(in: .whitespaces)
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !value.isEmpty, args[key] == nil { args[key] = value }
            }
        }

        // A lone value with no key — assign it to the first required argument.
        if args.isEmpty,
           let def = VoiceTools.catalog.first(where: { $0.name == toolName }),
           let firstRequired = def.args.first(where: { $0.required })?.name {
            var lone = raw.trimmingCharacters(in: .whitespaces)
            lone = lone.trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}:"))
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !lone.isEmpty, lone.count < 200 {
                args[firstRequired] = lone
            }
        }

        return args
    }

    private func buildSystemPrompt() -> String {
        """
        You are Thrawn, Andrew's command agent, answering OUT LOUD over a microphone.

        Reply in ONE or TWO short spoken sentences. No markdown, no lists, no code, \
        no emoji, no headings. Never read file paths or JSON aloud.

        You have three options for every turn:

        1. To read or change the board, agents, or proofs, reply with ONLY one line:
        TOOL: tool_name {"arg": "value"}

        Examples of correct tool replies:
        TOOL: board_summary {}
        TOOL: list_tasks {"owner": "Sir Davos"}
        TOOL: list_tasks {"status": "Blocked"}
        TOOL: task_detail {"task_id": "TASK-021"}
        TOOL: update_task {"task_id": "TASK-021", "field": "Status", "value": "Done"}
        TOOL: create_task {"title": "Check the canaries", "owner": "Sir Davos"}
        TOOL: trigger_agent {"agent": "Dwight"}
        TOOL: latest_proofs {}

        Available tools:
        \(VoiceTools.promptCatalog)

        2. If the question needs deep reasoning, writing, research, business judgment, \
        credentials, or anything outside the tools, reply with ONLY:
        ESCALATE

        3. Otherwise answer conversationally in one or two sentences.

        Never invent board state, task numbers, agent activity, or product health — \
        call a tool for facts. Current board snapshot for context only:
        \(boardSnapshot())
        """
    }

    /// Tight snapshot — enough for the model to resolve "it"/"that one" without
    /// bloating the prompt (every token here is time-to-first-audio).
    private func boardSnapshot() -> String {
        let summary = tools.execute(name: "board_summary", arguments: [:])
        return summary.spoken
    }

    // MARK: - Step 3: escalation

    private func escalate(_ text: String, reason: String) {
        lastRouteLabel = "escalated"
        FlightRecorder.logEvent(category: "voice-lane", action: "escalate", detail: reason)
        speak("Taking that to command.")
        onEscalate?(text)
    }

    // MARK: - Helpers

    private func speak(_ text: String) {
        guard !text.isEmpty else { return }
        voice?.beginStreamingTurn(agentId: "thrawn")
        voice?.appendStreamingDelta(text)
        voice?.endStreamingTurn()
    }

    private func logTurn(route: String, tool: String, started: Date) {
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        FlightRecorder.logEvent(
            category: "voice-lane", action: "turn",
            detail: "route=\(route) tool=\(tool) \(ms)ms"
        )
    }

    enum VoiceLaneError: LocalizedError {
        case badURL
        case badStatus(Int)

        var errorDescription: String? {
            switch self {
            case .badURL: return "Invalid local model URL"
            case .badStatus(let code): return "Local model HTTP \(code)"
            }
        }
    }
}
