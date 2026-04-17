import Foundation
import SwiftUI
import AVFoundation

// MARK: - Briefing Service
//
// SOD/EOD self-reviews with audio output.
//
// Every morning (SOD) and evening (EOD), each agent that was active in
// the last 24 hours produces a short briefing:
//   • a self-grade (A–F letter),
//   • one concrete improvement they'll implement,
//   • a 30–45 second spoken briefing, in their own voice.
//
// Text goes to ~/Desktop/Thrawn Briefings/{YYYY-MM-DD}/{sod|eod}/{id}.md
// Audio goes to ~/Desktop/Thrawn Briefings/{YYYY-MM-DD}/{sod|eod}/{id}.caf
// A JSON index alongside lists everything generated for that half.
//
// Playback: one giant play button plays every briefing in order
//   — Thrawn first, then by rank (S > A > B > C), then alphabetical —
// with a short gap between each agent.
//
// SOD = today's plan (review last 24h, pledge one improvement, lay out today)
// EOD = yesterday's review (grade the day, name the miss, fix for tomorrow)

@MainActor
final class BriefingService: NSObject, ObservableObject {
    // MARK: Published state (UI)

    /// Latest briefings for today's SOD and EOD, in play order.
    @Published private(set) var latestSOD: [BriefingEntry] = []
    @Published private(set) var latestEOD: [BriefingEntry] = []

    /// Generation state — UI shows a spinner when true.
    @Published private(set) var isGenerating: Bool = false

    /// Playback state — UI hiliTes the currently-playing agent.
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentlyPlayingAgentId: String?

    /// Last-run timestamps per kind so the scheduler doesn't double-fire.
    @Published private(set) var lastRunAt: [BriefingKind: Date] = [:]

    // MARK: Dependencies (weak — services outlive this)

    private weak var specStore: AgentSpecStore?
    private weak var scheduler: AgentScheduler?
    private weak var voice: VoiceService?

    // MARK: Playback state

    private var player: AVAudioPlayer?
    private var playQueue: [BriefingEntry] = []
    private var playIndex: Int = 0

    // MARK: Paths
    //
    // Briefings live on the desktop in a labeled folder so the user can
    // find and file them without opening the app. One folder per day,
    // SOD and EOD as sub-folders, agent files inside.

    /// Root folder on the user's desktop. Created on first write.
    static let rootDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Desktop/Thrawn Briefings")
    }()

    /// Folder for a given date (e.g. "2026-04-14").
    static func dayFolder(for date: Date) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return rootDir.appendingPathComponent(f.string(from: date))
    }

    /// Folder for a given (date, kind) pair.
    static func kindFolder(for date: Date, kind: BriefingKind) -> URL {
        dayFolder(for: date).appendingPathComponent(kind.rawValue)
    }

    /// Persistent state file — stores lastRunAt so restarts don't double-fire.
    private static let statePath = ThrawnPaths.appSupportDir
        .appendingPathComponent("briefing-state.json")

    // MARK: Init / bind

    override init() {
        super.init()
        loadState()
        try? FileManager.default.createDirectory(
            at: Self.rootDir,
            withIntermediateDirectories: true
        )
    }

    func bind(
        specStore: AgentSpecStore,
        scheduler: AgentScheduler,
        voice: VoiceService
    ) {
        self.specStore = specStore
        self.scheduler = scheduler
        self.voice = voice
        // Try to load today's briefings from disk so the UI isn't blank after a restart.
        latestSOD = loadDay(kind: .sod, date: Date())
        latestEOD = loadDay(kind: .eod, date: Date())
    }

    // MARK: - Public API

    /// Generate briefings for every active agent. Skips agents with zero
    /// activity in the last 24h (they have nothing to review).
    /// Thrawn goes first, then rank order (S→C), then alphabetical.
    func generate(kind: BriefingKind) async {
        guard !isGenerating else {
            FlightRecorder.logEvent(
                category: "briefing", action: "skip",
                detail: "\(kind.rawValue): already generating"
            )
            return
        }
        isGenerating = true
        defer { isGenerating = false }

        guard let store = specStore else {
            FlightRecorder.logEvent(
                category: "briefing", action: "skip",
                detail: "\(kind.rawValue): no specStore"
            )
            return
        }

        let ordered = Self.playOrder(for: store.specs)
        let dayDir = Self.kindFolder(for: Date(), kind: kind)
        try? FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)

        FlightRecorder.logEvent(
            category: "briefing", action: "start",
            detail: "\(kind.rawValue): \(ordered.count) candidates"
        )

        var results: [BriefingEntry] = []

        for spec in ordered {
            // Active-in-24h gate — zero rows in the flight recorder = no briefing.
            guard Self.wasActive(agentId: spec.id, windowHours: 24) else {
                FlightRecorder.logEvent(
                    category: "briefing", action: "skipped-inactive",
                    detail: "\(spec.id) \(kind.rawValue)"
                )
                continue
            }

            if let entry = await generateOne(for: spec, kind: kind, dayDir: dayDir) {
                results.append(entry)
            }
        }

        // Persist the JSON index for this day + kind so restarts can reload it.
        saveIndex(results, kind: kind, dayDir: dayDir)

        // Update published state
        switch kind {
        case .sod: latestSOD = results
        case .eod: latestEOD = results
        }
        lastRunAt[kind] = Date()
        saveState()

        FlightRecorder.logEvent(
            category: "briefing", action: "complete",
            detail: "\(kind.rawValue): \(results.count) briefings"
        )
    }

    /// Giant-play-button action: play every briefing for the given kind
    /// back-to-back, in Thrawn-first-then-rank order.
    func playAll(kind: BriefingKind) {
        let list = (kind == .sod) ? latestSOD : latestEOD
        let withAudio = list.filter { $0.audioPath != nil }
        guard !withAudio.isEmpty else {
            FlightRecorder.logEvent(
                category: "briefing", action: "play-empty",
                detail: "\(kind.rawValue): no audio files"
            )
            return
        }
        stopPlayback()
        playQueue = withAudio
        playIndex = 0
        isPlaying = true
        playCurrent()
    }

    /// Stop any in-progress playback and clear the queue.
    func stopPlayback() {
        player?.stop()
        player = nil
        playQueue = []
        playIndex = 0
        isPlaying = false
        currentlyPlayingAgentId = nil
    }

    /// Reveal today's briefings folder in Finder.
    func revealInFinder(kind: BriefingKind) {
        let dir = Self.kindFolder(for: Date(), kind: kind)
        if FileManager.default.fileExists(atPath: dir.path) {
            NSWorkspace.shared.open(dir)
        } else {
            NSWorkspace.shared.open(Self.rootDir)
        }
    }

    // MARK: - Generation per agent

    private func generateOne(
        for spec: AgentSpec,
        kind: BriefingKind,
        dayDir: URL
    ) async -> BriefingEntry? {
        let activity = Self.activitySummary(agentId: spec.id, windowHours: 24)
        let prompt = Self.buildPrompt(spec: spec, kind: kind, activity: activity)
        let system = Self.systemPrompt(for: spec, kind: kind)

        // Route through the scheduler so Bart lands on OpenAI,
        // everyone else lands on Ollama. Same code path as heartbeats.
        guard let raw = await scheduler?.sendOneShot(
            agentId: spec.id,
            prompt: prompt,
            systemPrompt: system,
            sessionKey: "briefing-\(spec.id)-\(kind.rawValue)"
        ), !raw.isEmpty else {
            FlightRecorder.logEvent(
                category: "briefing", action: "no-response",
                detail: "\(spec.id) \(kind.rawValue)"
            )
            return nil
        }

        guard let parsed = Self.parseBriefingJSON(raw) else {
            FlightRecorder.logEvent(
                category: "briefing", action: "parse-fail",
                detail: "\(spec.id) \(kind.rawValue): \(raw.prefix(200))"
            )
            // Try to salvage something so the user still gets a file.
            let fallback = BriefingPayload(
                grade: "C",
                improvement: "Return valid JSON next time.",
                spoken: raw.prefix(400).description
            )
            return await writeEntry(spec: spec, kind: kind, payload: fallback, dayDir: dayDir)
        }

        return await writeEntry(spec: spec, kind: kind, payload: parsed, dayDir: dayDir)
    }

    private func writeEntry(
        spec: AgentSpec,
        kind: BriefingKind,
        payload: BriefingPayload,
        dayDir: URL
    ) async -> BriefingEntry {
        // Text file (.md) — easy to read and version-control
        let textURL = dayDir.appendingPathComponent("\(spec.id).md")
        let md = """
        # \(spec.name) — \(kind == .sod ? "Start of Day" : "End of Day")
        \(Self.humanDate(Date()))

        **Role:** \(spec.role)
        **Grade:** \(payload.grade)

        ## Improvement
        \(payload.improvement)

        ## Spoken briefing
        \(payload.spoken)
        """
        try? md.write(to: textURL, atomically: true, encoding: .utf8)

        // Audio file (.caf) — Apple native, no transcode
        let audioURL = dayDir.appendingPathComponent("\(spec.id).caf")
        var finalAudioURL: URL? = nil
        if let voice {
            let ok = await voice.renderToFile(
                agentId: spec.id,
                text: payload.spoken,
                url: audioURL
            )
            if ok { finalAudioURL = audioURL }
        }

        // Append to rolling grade history (feeds RankEvaluator)
        specStore?.appendGrade(
            agentId: spec.id,
            entry: GradeEntry(
                date: Date(),
                kind: kind,
                grade: payload.grade,
                improvement: payload.improvement
            )
        )

        FlightRecorder.logEvent(
            category: "briefing", action: "generated",
            detail: "\(spec.id) \(kind.rawValue) grade=\(payload.grade) audio=\(finalAudioURL != nil)"
        )

        return BriefingEntry(
            id: UUID(),
            agentId: spec.id,
            agentName: spec.name,
            kind: kind,
            date: Date(),
            grade: payload.grade,
            improvement: payload.improvement,
            spokenBriefing: payload.spoken,
            textPath: textURL,
            audioPath: finalAudioURL,
            rank: spec.rank
        )
    }

    // MARK: - Play order

    /// Thrawn first, then by rank (S → C), then alphabetical by name.
    static func playOrder(for specs: [AgentSpec]) -> [AgentSpec] {
        specs.sorted { a, b in
            if a.id == "thrawn" && b.id != "thrawn" { return true }
            if b.id == "thrawn" && a.id != "thrawn" { return false }
            if a.rank != b.rank { return a.rank.sortOrder < b.rank.sortOrder }
            return a.name.lowercased() < b.name.lowercased()
        }
    }

    // MARK: - Prompts

    private static func systemPrompt(for spec: AgentSpec, kind: BriefingKind) -> String {
        let verb = (kind == .sod) ? "plan today" : "review yesterday"
        return """
        You are \(spec.name). \(spec.persona)
        Your role: \(spec.role).
        Your mission: \(spec.purpose).

        Your job right now is to \(verb) based on the activity summary below.
        Return STRICT JSON — no prose, no markdown fences, no commentary.
        Shape: {"grade":"A-F","improvement":"one sentence","spoken":"30-45s spoken briefing"}
        The "spoken" field MUST be one or two short paragraphs, in your own voice,
        suitable to be read aloud to the user. No emojis. No markdown. No lists.
        Keep it under 500 characters.
        """
    }

    private static func buildPrompt(
        spec: AgentSpec,
        kind: BriefingKind,
        activity: String
    ) -> String {
        let header = (kind == .sod)
            ? "Morning briefing — report today's plan based on your last 24 hours of work and the current board."
            : "Evening briefing — review the last 24 hours honestly. Grade yourself, name the miss, commit to one fix."
        return """
        \(header)

        AGENT: \(spec.name) (\(spec.role))

        ACTIVITY SUMMARY (last 24h):
        \(activity)

        Return JSON only. Shape:
        {"grade":"A-F","improvement":"one sentence","spoken":"30-45s spoken briefing"}
        """
    }

    // MARK: - Activity detection

    /// Was this agent active in the last N hours? Checks the flight
    /// recorder's llm + heartbeat + exec logs for any row mentioning
    /// this agent id. Silent agents get no briefing.
    static func wasActive(agentId: String, windowHours: Int) -> Bool {
        let cutoff = Date().addingTimeInterval(TimeInterval(-windowHours * 3600))
        let logs = Self.flightRecorderRows(agentId: agentId, since: cutoff)
        return !logs.isEmpty
    }

    /// Human-readable activity digest for the agent, fed to their LLM
    /// as context for the briefing.
    static func activitySummary(agentId: String, windowHours: Int) -> String {
        let cutoff = Date().addingTimeInterval(TimeInterval(-windowHours * 3600))
        let rows = Self.flightRecorderRows(agentId: agentId, since: cutoff)
        guard !rows.isEmpty else { return "No activity recorded in the last \(windowHours) hours." }

        var llmCount = 0
        var execCount = 0
        var heartbeatCount = 0
        var errorCount = 0
        var recentResponses: [String] = []

        for row in rows {
            let cat = row["__source"] as? String ?? ""
            switch cat {
            case "llm":
                llmCount += 1
                if let resp = row["response_summary"] as? String, !resp.isEmpty {
                    recentResponses.append(resp)
                }
                if let ok = row["success"] as? Bool, !ok { errorCount += 1 }
            case "exec":
                execCount += 1
                if let code = row["exit_code"] as? Int, code != 0 { errorCount += 1 }
            case "heartbeat":
                heartbeatCount += 1
            default:
                break
            }
        }

        // Cap the recent-response tail so we don't blow the prompt budget.
        let tail = recentResponses.suffix(5)
            .enumerated()
            .map { "- [\($0.offset + 1)] \($0.element.prefix(200))" }
            .joined(separator: "\n")

        return """
        • Heartbeats run: \(heartbeatCount)
        • LLM calls: \(llmCount)
        • Commands executed: \(execCount)
        • Errors / non-zero exits: \(errorCount)

        Recent response snippets:
        \(tail.isEmpty ? "(none captured)" : tail)
        """
    }

    /// Load flight-recorder rows for an agent since a cutoff. Merges
    /// today's and yesterday's log files so a 24h window always fits.
    private static func flightRecorderRows(agentId: String, since cutoff: Date) -> [[String: Any]] {
        let logsDir = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/logs")
        let fm = FileManager.default
        guard fm.fileExists(atPath: logsDir.path) else { return [] }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        let yesterday = f.string(from: Date().addingTimeInterval(-86400))
        let categories = ["llm", "exec", "heartbeat"]

        var merged: [[String: Any]] = []
        let iso = ISO8601DateFormatter()

        for cat in categories {
            for day in [today, yesterday] {
                let path = logsDir.appendingPathComponent("\(cat)-\(day).jsonl")
                guard let content = try? String(contentsOf: path, encoding: .utf8) else { continue }
                for line in content.split(separator: "\n") {
                    guard let data = line.data(using: .utf8),
                          var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { continue }

                    // Agent filter
                    let rowAgent = (obj["agent"] as? String) ?? ""
                    guard rowAgent == agentId else { continue }

                    // Time filter
                    if let ts = obj["ts"] as? String, let d = iso.date(from: ts), d >= cutoff {
                        obj["__source"] = cat
                        merged.append(obj)
                    }
                }
            }
        }
        return merged
    }

    // MARK: - JSON parsing

    /// Expected shape: `{"grade":"A","improvement":"...","spoken":"..."}`.
    /// Tolerates code fences and leading/trailing prose by extracting
    /// the first {...} block.
    static func parseBriefingJSON(_ raw: String) -> BriefingPayload? {
        // Pull the first JSON object out of the response
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"),
              start < end else { return nil }
        let slice = String(raw[start...end])
        guard let data = slice.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let grade = obj["grade"] as? String,
              let improvement = obj["improvement"] as? String,
              let spoken = obj["spoken"] as? String,
              !grade.isEmpty, !spoken.isEmpty else {
            return nil
        }
        return BriefingPayload(
            grade: grade,
            improvement: improvement,
            spoken: spoken
        )
    }

    // MARK: - Persistence (day index + state)

    private func saveIndex(_ entries: [BriefingEntry], kind: BriefingKind, dayDir: URL) {
        let indexURL = dayDir.appendingPathComponent("index.json")
        guard let data = try? JSONEncoder.briefingEncoder.encode(entries) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func loadDay(kind: BriefingKind, date: Date) -> [BriefingEntry] {
        let dayDir = Self.kindFolder(for: date, kind: kind)
        let indexURL = dayDir.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder.briefingDecoder.decode([BriefingEntry].self, from: data)
        else { return [] }
        return decoded
    }

    private struct PersistedState: Codable {
        var lastRunAt: [String: Date]
    }

    private func saveState() {
        let mapped = Dictionary(uniqueKeysWithValues:
            lastRunAt.map { ($0.key.rawValue, $0.value) }
        )
        let state = PersistedState(lastRunAt: mapped)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: Self.statePath, options: .atomic)
        }
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: Self.statePath),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data)
        else { return }
        var mapped: [BriefingKind: Date] = [:]
        for (k, v) in state.lastRunAt {
            if let kind = BriefingKind(rawValue: k) { mapped[kind] = v }
        }
        lastRunAt = mapped
    }

    // MARK: - Date helpers

    static func humanDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f.string(from: date)
    }

    // MARK: - Playback queue

    private func playCurrent() {
        guard playIndex < playQueue.count else {
            // Done — stop and return.
            stopPlayback()
            return
        }
        let entry = playQueue[playIndex]
        guard let url = entry.audioPath,
              let newPlayer = try? AVAudioPlayer(contentsOf: url) else {
            // Skip this one and try the next
            FlightRecorder.logEvent(
                category: "briefing", action: "play-skip",
                detail: "\(entry.agentId): audio unreadable"
            )
            playIndex += 1
            playCurrent()
            return
        }
        newPlayer.delegate = self
        newPlayer.prepareToPlay()
        self.player = newPlayer
        self.currentlyPlayingAgentId = entry.agentId
        newPlayer.play()
    }
}

// MARK: - AVAudioPlayerDelegate

extension BriefingService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playIndex += 1
            // Small gap between agents so it doesn't feel like one giant blob of audio.
            try? await Task.sleep(nanoseconds: 500_000_000)
            if self.isPlaying {
                self.playCurrent()
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            FlightRecorder.logEvent(
                category: "briefing", action: "play-decode-err",
                detail: error?.localizedDescription ?? "unknown"
            )
            self.playIndex += 1
            if self.isPlaying { self.playCurrent() }
        }
    }
}

// MARK: - Types

struct BriefingPayload {
    let grade: String
    let improvement: String
    let spoken: String
}

struct BriefingEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let agentId: String
    let agentName: String
    let kind: BriefingKind
    let date: Date
    let grade: String
    let improvement: String
    let spokenBriefing: String
    let textPath: URL
    let audioPath: URL?
    let rank: AgentRank
}

// MARK: - Encoder/decoder helpers

private extension JSONEncoder {
    static var briefingEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

private extension JSONDecoder {
    static var briefingDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
