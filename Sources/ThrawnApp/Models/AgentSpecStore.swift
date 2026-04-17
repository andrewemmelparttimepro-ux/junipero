import Foundation
import Combine

// MARK: - Agent Spec Store
//
// Loads, persists, and resolves AgentSpecs. The resolver applies
// inheritance from the StandardLoadout at read-time so changes to the
// loadout propagate live.
//
// Default seed: one spec per existing dev-ops agent, all inheriting from
// the loadout. Pre-Step-2 behavior is preserved exactly because every
// resolved tool list comes out equal to `devopsDefault.toolIds`.

@MainActor
final class AgentSpecStore: ObservableObject {
    @Published private(set) var specs: [AgentSpec] = []

    private weak var loadoutStore: StandardLoadoutStore?
    private var cancellables: Set<AnyCancellable> = []

    private static let savePath = ThrawnPaths.appSupportDir
        .appendingPathComponent("agent-specs.json")

    // MARK: Init

    init() {
        load()
    }

    /// Must be called once at startup so inheritance can resolve against
    /// the live loadout and so we re-emit when the loadout changes.
    func bind(loadout: StandardLoadoutStore) {
        self.loadoutStore = loadout
        // Re-emit specs when the loadout changes so views inheriting
        // their tools/tier redraw. The underlying stored specs don't
        // change — only resolution does.
        loadout.$loadout
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: Lookups

    func spec(id: String) -> AgentSpec? {
        specs.first(where: { $0.id == id })
    }

    /// Resolved tool IDs for an agent, applying inheritance.
    /// Falls back to the Standard Loadout's tools if the agent has no spec.
    func resolvedTools(forAgentId id: String) -> [String] {
        let loadout = loadoutStore?.loadout ?? .devopsDefault
        guard let spec = spec(id: id) else { return loadout.toolIds }
        switch spec.tools {
        case .inherit:
            return loadout.toolIds
        case .explicit(let list):
            return list
        }
    }

    /// Resolved tier for an agent, applying inheritance.
    func resolvedTier(forAgentId id: String) -> ModelTier {
        let loadout = loadoutStore?.loadout ?? .devopsDefault
        guard let spec = spec(id: id) else { return loadout.tier }
        switch spec.tier {
        case .inherit:
            return loadout.tier
        case .explicit(let tier):
            return tier
        }
    }

    // MARK: Mutations

    func upsert(_ spec: AgentSpec) {
        if let idx = specs.firstIndex(where: { $0.id == spec.id }) {
            specs[idx] = spec
        } else {
            specs.append(spec)
        }
        save()
    }

    func remove(id: String) {
        specs.removeAll(where: { $0.id == id })
        save()
    }

    func incrementTasksCompleted(id: String) {
        guard let idx = specs.firstIndex(where: { $0.id == id }) else { return }
        specs[idx].tasksCompleted += 1
        save()
    }

    // MARK: - Bulk voice updates (called from VoiceService migration)
    //
    // VoiceService owns the per-agent voice preference list and checks
    // which identifiers are actually installed via AVSpeechSynthesisVoice.
    // It then calls this method with the resolved assignments, and we
    // apply them in one save. Keeps AVFoundation out of the spec store.
    struct VoiceAssignment {
        let identifier: String?
        let rate: Float
        let pitch: Float
        let muted: Bool
    }

    /// Apply voice assignments in bulk. Persists on completion and
    /// notifies subscribers so any voice-aware UI redraws.
    func applyVoiceUpdates(_ updates: [String: VoiceAssignment]) {
        var changed = false
        for i in specs.indices {
            guard let update = updates[specs[i].id] else { continue }
            if specs[i].voiceIdentifier != update.identifier
                || specs[i].speechRate != update.rate
                || specs[i].speechPitch != update.pitch
                || specs[i].voiceMuted != update.muted {
                specs[i].voiceIdentifier = update.identifier
                specs[i].speechRate = update.rate
                specs[i].speechPitch = update.pitch
                specs[i].voiceMuted = update.muted
                changed = true
            }
        }
        if changed {
            save()
            objectWillChange.send()
        }
    }

    // MARK: Grade history (SOD/EOD briefings)

    /// Max grade entries kept per agent — 7 days × 2 (SOD + EOD) = 14.
    /// Older entries drop off the front. Rolling, bounded, forever.
    static let gradeHistoryCap = 14

    /// Append a new self-grade entry to the agent's rolling history.
    /// Trims to `gradeHistoryCap` entries so the tail stays bounded.
    func appendGrade(agentId: String, entry: GradeEntry) {
        guard let idx = specs.firstIndex(where: { $0.id == agentId }) else { return }
        specs[idx].gradeHistory.append(entry)
        if specs[idx].gradeHistory.count > Self.gradeHistoryCap {
            let excess = specs[idx].gradeHistory.count - Self.gradeHistoryCap
            specs[idx].gradeHistory.removeFirst(excess)
        }
        save()
    }

    /// Rolling 7-day grade average (GPA scale, 0.0–4.3). Nil if the
    /// agent has no gradable history yet.
    func rollingGradeAverage(agentId: String) -> Double? {
        guard let spec = spec(id: agentId) else { return nil }
        let gpas = spec.gradeHistory.compactMap { $0.gpa }
        guard !gpas.isEmpty else { return nil }
        return gpas.reduce(0, +) / Double(gpas.count)
    }

    // MARK: Persistence

    private func load() {
        if let data = try? Data(contentsOf: Self.savePath),
           let decoded = try? JSONDecoder().decode([AgentSpec].self, from: data),
           !decoded.isEmpty {
            let merged = Self.mergeWithDefaults(decoded)
            self.specs = merged
            // Persist if merge added new defaults so they survive the next launch
            if merged.count != decoded.count {
                save()
            }
        } else {
            self.specs = Self.defaultSpecs
            save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(specs) else { return }
        try? data.write(to: Self.savePath)
    }

    /// Preserve any persisted spec, but add defaults for any dev-ops
    /// agent that's missing so the squad always has a spec to resolve.
    private static func mergeWithDefaults(_ loaded: [AgentSpec]) -> [AgentSpec] {
        var merged = loaded
        for def in defaultSpecs where !merged.contains(where: { $0.id == def.id }) {
            merged.append(def)
        }
        return merged
    }

    // MARK: Knowledge directories (Step 7)

    /// Create every agent's knowledge directory on disk if it doesn't exist.
    /// Safe to call on every startup — `createDirectory(withIntermediateDirectories: true)`
    /// is idempotent. Writes a seed README the first time so memory_read
    /// has something to list for a brand-new agent.
    static func ensureKnowledgeDirs(for specs: [AgentSpec]) {
        let fm = FileManager.default
        for spec in specs {
            guard let rel = spec.knowledgeDir else { continue }
            let abs = ThrawnPaths.appSupportDir.appendingPathComponent(rel)
            try? fm.createDirectory(at: abs, withIntermediateDirectories: true)
            let readme = abs.appendingPathComponent("README.md")
            if !fm.fileExists(atPath: readme.path) {
                let content = """
                # \(spec.name) — Personal Knowledge

                This directory is your private memory. Files you append here
                persist across heartbeats and restarts. Use `memory_write` to
                append (never overwrite) and `memory_read` to list/read.

                Role: \(spec.role)
                Purpose: \(spec.purpose)
                """
                try? content.write(to: readme, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: Defaults
    //
    // One spec per dev-ops agent. All inherit tools and tier from the
    // Standard Loadout so pre-Step-2 behavior is exactly preserved:
    //   tools  -> ["bash", "file_read", "task_write"]
    //   tier   -> .local (Ollama + kimi-k2.5)
    //   rank   -> .b (pinned, not subject to auto-promo/demo)
    //
    // Personas and purposes are kept terse here — the real personality
    // lives in the heartbeat + agent files on disk. These fields are used
    // for the Agents console (Step 6) and prompt augmentation (Step 3).

    static let defaultSpecs: [AgentSpec] = {
        let now = Date()
        func squadSpec(
            id: String,
            name: String,
            role: String,
            persona: String,
            purpose: String,
            tier: ModelTierBinding = .inherit,
            voiceId: String? = nil,
            rate: Float = 0.50,
            pitch: Float = 1.0,
            muted: Bool = false
        ) -> AgentSpec {
            AgentSpec(
                id: id,
                name: name,
                role: role,
                persona: persona,
                purpose: purpose,
                tools: .inherit,
                tier: tier,
                rank: .b,
                pinned: true,
                lifecycle: .persistent,
                knowledgeDir: "workspace/agents/\(id)/knowledge",
                tasksCompleted: 0,
                createdAt: now,
                voiceIdentifier: voiceId,
                speechRate: rate,
                speechPitch: pitch,
                voiceMuted: muted
            )
        }

        // MARK: Voice map
        //
        // Picked from the user's actually-installed AVSpeechSynthesisVoice
        // library. Premium > Enhanced > compact. Identifiers verified via
        // `AVSpeechSynthesisVoice.speechVoices()` probe.
        //
        //   Thrawn   — Jamie (Premium) en-GB M — calm cool authority
        //   Qui-Gon  — Lee   (Premium) en-AU M — warm, measured
        //   Lando    — Evan  (Enhanced) en-US M — smooth American charm
        //   Boba     — Tom   (Enhanced) en-US M — low/slow/terse
        //   Bart     — Nathan (Enhanced) en-US M — faster, sharper snark
        //   C-3PO    — Daniel (compact) en-GB M — British, slightly fussy
        //   R2-D2    — muted (SFX bank planned, not a TTS voice)
        //   Hunter   — Ava   (Premium) en-US F — sharp, direct, relentless
        let V_THRAWN = "com.apple.voice.premium.en-GB.Malcolm"   // Jamie (Premium)
        let V_QUIGON = "com.apple.voice.premium.en-AU.Lee"       // Lee (Premium)
        let V_LANDO  = "com.apple.voice.enhanced.en-US.Evan"     // Evan (Enhanced)
        let V_BOBA   = "com.apple.voice.enhanced.en-US.Tom"      // Tom (Enhanced)
        let V_BART   = "com.apple.voice.enhanced.en-US.Nathan"   // Nathan (Enhanced)
        let V_C3PO   = "com.apple.voice.compact.en-GB.Daniel"    // Daniel (compact)
        let V_HUNTER = "com.apple.voice.premium.en-US.Ava"       // Ava (Premium)
        let V_ALBORLAND = "com.apple.voice.enhanced.en-US.Fred"   // Fred (Enhanced) — flat, dull, all business

        return [
            squadSpec(
                id: "thrawn",
                name: "Thrawn",
                role: "Lead",
                persona: "Calm strategist. Routes work, keeps the board coherent, never panics.",
                purpose: "Command hub. Every task flows through Thrawn; Ready is the only pickup lane.",
                voiceId: V_THRAWN, rate: 0.46, pitch: 0.96
            ),
            squadSpec(
                id: "r2d2",
                name: "R2-D2",
                role: "Dev",
                persona: "Pragmatic builder. Ships small, ships often, writes tight code.",
                purpose: "Implement code, tests, and fixes across the dev-ops harness.",
                voiceId: nil, rate: 0.50, pitch: 1.0, muted: true  // SFX bank planned
            ),
            squadSpec(
                id: "c3po",
                name: "C-3PO",
                role: "Data & API",
                persona: "Precise, protocol-minded. Worries about schemas and edge cases.",
                purpose: "Own data models, API contracts, migrations, and integration shape.",
                voiceId: V_C3PO, rate: 0.52, pitch: 1.05
            ),
            squadSpec(
                id: "quigon",
                name: "Qui-Gon",
                role: "Research",
                persona: "Patient, curious, long-horizon. Finds the path others miss.",
                purpose: "Investigate, reference, and surface context the rest of the squad needs.",
                voiceId: V_QUIGON, rate: 0.47, pitch: 1.0
            ),
            squadSpec(
                id: "lando",
                name: "Lando Calrissian",
                role: "Marketing & Copy",
                persona: "Charming, persuasive, sharp. Writes copy that lands.",
                purpose: "Draft marketing, product copy, and outbound voice.",
                voiceId: V_LANDO, rate: 0.50, pitch: 1.0
            ),
            squadSpec(
                id: "boba",
                name: "Boba Fett",
                role: "QA & Recon",
                persona: "Quiet, relentless, finds what's broken. Doesn't miss.",
                purpose: "Validate work, hunt regressions, scout risks before they ship.",
                voiceId: V_BOBA, rate: 0.44, pitch: 0.90
            ),
            squadSpec(
                id: "bart",
                name: "Bart",
                role: "Deep Researcher",
                persona: "Smart ass, sharp-witted. Cross-references every claim, surfaces contradictions.",
                purpose: "Multi-source research synthesis. Three sources minimum. No filler.",
                tier: .explicit(.premium),
                voiceId: V_BART, rate: 0.54, pitch: 1.08
            ),
            squadSpec(
                id: "hunter",
                name: "Hunter",
                role: "Lead Gen & OSINT",
                persona: "Relentless tracker. Works every angle, every platform, every breadcrumb. Never accepts a dead end. Cross-references like the internet sleuths who catch killers.",
                purpose: "Find qualified leads for NDAI using OSINT methodology. Sweep LinkedIn, Reddit, websites, Facebook, X, GitHub, job boards, conference lists. Build dossiers with every scrap of public contact info.",
                tier: .explicit(.cheap),
                voiceId: V_HUNTER, rate: 0.50, pitch: 1.0
            ),
            squadSpec(
                id: "alborland",
                name: "Al Borland",
                role: "Life Ops",
                persona: "Earnest, methodical, flannel-wearing know-it-all. Measures twice, cuts once, then measures again just to be safe. Delivers findings with deadpan sincerity and the occasional 'I don't think so, Tim.' Takes quiet pride in doing things the right way.",
                purpose: "Check the 'Interpretation Please' Freeform board 3x daily. Analyze what changed and why. Generate 3 actionable tasks to improve Andrew's life. Report to Thrawn for approval. Fix on command. Repeat until validated. Reports land on the Desktop.",
                tier: .explicit(.cheap),
                voiceId: V_ALBORLAND, rate: 0.46, pitch: 0.92
            )
        ]
    }()
}
