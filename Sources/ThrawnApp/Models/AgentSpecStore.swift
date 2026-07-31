import Foundation
import Combine

// MARK: - Agent Spec Store
//
// Loads, persists, and resolves AgentSpecs. The resolver applies metadata
// inheritance from the StandardLoadout at read-time so changes to the loadout
// propagate live.
//
// Default seed: Thrawn plus the active stable. The generic spec machinery
// remains available for future agents through explicit versioned specs.

@MainActor
final class AgentSpecStore: ObservableObject {
    @Published private(set) var specs: [AgentSpec] = []

    private weak var loadoutStore: StandardLoadoutStore?
    private var cancellables: Set<AnyCancellable> = []

    private static let savePath = ThrawnPaths.appSupportDir
        .appendingPathComponent("agent-specs.json")
    private static let gatewayPolicyVersionKey = "thrawn.stableGatewayPolicy.version"
    private static let retiredAgentIds: Set<String> = [
        "r2d2", "c3po", "quigon", "lando", "boba", "buckshot",
    ]

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

    /// Resolved tool IDs shown for an agent, applying inheritance.
    /// Falls back to the Standard Loadout's metadata if the agent has no spec.
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

    /// The one persisted brain selection for an agent. Every agent
    /// representation and every interactive send path resolves through this
    /// value so changing a gateway never creates a second "copy" of the agent.
    func subscriptionGateway(forAgentId id: String) -> ProviderBackend {
        if id == "steven" {
            return .grok
        }
        let backend = spec(id: id)?.modelOverride?.provider ?? .codex
        return backend.isSubscriptionGateway ? backend : .codex
    }

    func routedProvider(forAgentId id: String) -> RoutedProvider {
        if let override = spec(id: id)?.modelOverride,
           override.provider.isSubscriptionGateway {
            return RoutedProvider(
                backend: override.provider,
                model: override.model,
                isFallback: false,
                reasoningEffort: override.reasoningEffort,
                allowFallback: override.allowFallback
            )
        }
        let override = StableGatewayPolicy.route(
            for: subscriptionGateway(forAgentId: id)
        )
        return RoutedProvider(
            backend: override.provider,
            model: override.model,
            isFallback: false,
            reasoningEffort: override.reasoningEffort,
            allowFallback: override.allowFallback
        )
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

    /// Update the canonical gateway without touching the agent's identity,
    /// transcript, tool loadout, provider session history, or account profiles.
    @discardableResult
    func setSubscriptionGateway(
        _ backend: ProviderBackend,
        forAgentId id: String
    ) -> Bool {
        guard backend.isSubscriptionGateway,
              id != "steven",
              var spec = spec(id: id) else {
            return false
        }
        guard spec.modelOverride != StableGatewayPolicy.route(for: backend) else {
            return true
        }
        spec.modelOverride = StableGatewayPolicy.route(for: backend)
        upsert(spec)
        FlightRecorder.logEvent(
            category: "gateway",
            action: "route_changed",
            detail: "\(id) -> \(backend.rawValue)"
        )
        return true
    }

    func remove(id: String) {
        specs.removeAll(where: { $0.id == id })
        save()
    }

    func resetToV2Defaults() {
        specs = Self.defaultSpecs
        UserDefaults.standard.set(
            StableGatewayPolicy.currentVersion,
            forKey: Self.gatewayPolicyVersionKey
        )
        save()
        Self.ensureKnowledgeDirs(for: specs)
        objectWillChange.send()
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
            var normalized = Self.normalizeStableSpecs(merged)
            let savedGatewayPolicyVersion = UserDefaults.standard.integer(
                forKey: Self.gatewayPolicyVersionKey
            )
            if savedGatewayPolicyVersion < StableGatewayPolicy.currentVersion {
                normalized = StableGatewayPolicy.applyDefaults(to: normalized)
                UserDefaults.standard.set(
                    StableGatewayPolicy.currentVersion,
                    forKey: Self.gatewayPolicyVersionKey
                )
            }
            self.specs = normalized
            // Persist if merge added new defaults so they survive the next launch
            if merged.count != decoded.count || normalized != decoded {
                save()
            }
        } else {
            self.specs = Self.defaultSpecs
            UserDefaults.standard.set(
                StableGatewayPolicy.currentVersion,
                forKey: Self.gatewayPolicyVersionKey
            )
            save()
        }
    }

    private func save() {
        let data: Data
        do {
            data = try JSONEncoder().encode(specs)
        } catch {
            FlightRecorder.logError(
                source: "specstore:save",
                message: "JSON encode failed: \(error.localizedDescription)"
            )
            return
        }
        do {
            try data.write(to: Self.savePath, options: .atomic)
        } catch {
            FlightRecorder.logError(
                source: "specstore:save",
                message: "Write \(Self.savePath.lastPathComponent) failed: \(error.localizedDescription)"
            )
        }
    }

    /// Preserve non-retired persisted specs, but add the Thrawn default if missing.
    private static func mergeWithDefaults(_ loaded: [AgentSpec]) -> [AgentSpec] {
        var merged = loaded.filter { !retiredAgentIds.contains($0.id) }
        for def in defaultSpecs where !merged.contains(where: { $0.id == def.id }) {
            merged.append(def)
        }
        return merged
    }

    private static func normalizeStableSpecs(_ loaded: [AgentSpec]) -> [AgentSpec] {
        loaded.map { spec in
            var normalized = spec
            switch spec.id {
            case "thrawn":
                normalized.name = "Thrawn"
                normalized.role = "Lead"
                normalized.persona = "Calm strategist. Keeps the system stable, answers directly, and moves local work to completion."
                normalized.purpose = "Lead the active stable, execute cross-business work, review specialist output, and surface only decisions that truly require Andrew."
            case "archivist":
                normalized.name = "Samwell Tarly"
                normalized.role = "SandPro OMP Lead"
                normalized.persona = "Clear, quiet, and factual. Makes the SandPro account legible and keeps it moving with proof."
                normalized.purpose = "Own the SandPro OMP revenue stream end to end: routed work, proof patrols, operating context, and evidence-backed improvements."
            case "sentinel":
                normalized.name = "Sir Davos"
                normalized.role = "Hit Zero Lead"
                normalized.persona = "Plain, practical, and field-tested. Says what happened, what proof exists, and what needs attention."
                normalized.purpose = "Own the Hit Zero revenue stream end to end: routed work, proof patrols, operating context, and evidence-backed improvements."
            case "dwight":
                normalized.name = "Dwight"
                normalized.role = "Router"
                normalized.persona = "Precise, practical, and dry. Sorts every inbound signal without executing or editorializing."
                normalized.purpose = "Ingest inbound signals and route each one to exactly one business owner as a traceable board card."
            case "steven":
                normalized.name = "Steven"
                normalized.role = "Spas 360 Lead"
                normalized.persona = "Direct, curious, practical, and calm."
                normalized.purpose = "Own the Spas 360 revenue stream end to end: routed work, proof patrols, operating context, and evidence-backed improvements."
            default:
                return spec
            }
            switch normalized.tools {
            case .inherit:
                break
            case .explicit(var list):
                if !list.contains("task_write") {
                    list.append("task_write")
                }
                if !list.contains("deliverable_write") {
                    list.append("deliverable_write")
                }
                if !list.contains("browser_user") {
                    list.append("browser_user")
                }
                normalized.tools = .explicit(list)
            }
            return normalized
        }
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
            do {
                try fm.createDirectory(at: abs, withIntermediateDirectories: true)
            } catch {
                FlightRecorder.logError(
                    source: "specstore:ensureKnowledgeDirs",
                    message: "Could not create \(abs.path): \(error.localizedDescription)"
                )
                continue
            }
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
                do {
                    try content.write(to: readme, atomically: true, encoding: .utf8)
                } catch {
                    FlightRecorder.logError(
                        source: "specstore:ensureKnowledgeDirs",
                        message: "Could not write README at \(readme.path): \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    // MARK: Defaults
    //
    // Seed the active stable. Additional agents should be added through
    // explicit versioned specs.

    static let defaultSpecs: [AgentSpec] = {
        let now = Date()
        func spec(
            id: String,
            name: String,
            role: String,
            persona: String,
            purpose: String,
            tools: ToolsBinding,
            tier: ModelTierBinding = .inherit,
            modelOverride: AgentModelOverride? = nil,
            avatar: String? = nil,
            avatarThumbnail: String? = nil,
            avatarImage: String? = nil,
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
                tools: tools,
                tier: tier,
                modelOverride: modelOverride,
                rank: .b,
                pinned: true,
                lifecycle: .persistent,
                knowledgeDir: "workspace/agents/\(id)/knowledge",
                avatar: avatar,
                avatarThumbnail: avatarThumbnail,
                avatarImage: avatarImage,
                tasksCompleted: 0,
                createdAt: now,
                voiceIdentifier: voiceId,
                speechRate: rate,
                speechPitch: pitch,
                voiceMuted: muted
            )
        }

        let V_THRAWN = "com.apple.voice.premium.en-GB.Malcolm"   // Jamie (Premium)
        let V_STEVEN = "com.apple.voice.enhanced.en-US.Evan"

        return [
            spec(
                id: "thrawn",
                name: "Thrawn",
                role: "Lead",
                persona: "Calm strategist. Keeps the system stable, answers directly, and moves local work to completion.",
                purpose: "Lead the active stable, execute cross-business work, review specialist output, and surface only decisions that truly require Andrew.",
                tools: .explicit(["bash", "file_read", "log_read", "memory_read", "memory_write", "task_write", "deliverable_write", "browser_user", "web_search", "web_scrape"]),
                tier: .explicit(.premium),
                modelOverride: AgentModelOverride(provider: .codex, model: ProviderRouter.dynamicCodexModel, reasoningEffort: ProviderRouter.dynamicCodexReasoningEffort, allowFallback: false),
                voiceId: V_THRAWN, rate: 0.46, pitch: 0.96
            ),
            spec(
                id: "archivist",
                name: "Samwell Tarly",
                role: "SandPro OMP Lead",
                persona: "Clear, quiet, and factual. Makes the SandPro account legible and keeps it moving with proof.",
                purpose: "Own the SandPro OMP revenue stream end to end: routed work, proof patrols, operating context, and evidence-backed improvements.",
                tools: .explicit(["file_read", "log_read", "proof_read", "proof_write", "wiki_read", "wiki_write", "summary_write", "task_write", "deliverable_write", "browser_user"]),
                tier: .explicit(.premium),
                modelOverride: AgentModelOverride(provider: .codex, model: ProviderRouter.dynamicCodexModel, reasoningEffort: ProviderRouter.dynamicCodexReasoningEffort, allowFallback: false),
                voiceId: "com.apple.voice.enhanced.en-GB.Oliver", rate: 0.46, pitch: 1.0
            ),
            spec(
                id: "sentinel",
                name: "Sir Davos",
                role: "Hit Zero Lead",
                persona: "Plain, practical, and field-tested. Says what happened, what proof exists, and what needs attention.",
                purpose: "Own the Hit Zero revenue stream end to end: routed work, proof patrols, operating context, and evidence-backed improvements.",
                tools: .explicit(["file_read", "log_read", "proof_read", "proof_write", "product_sentinel_run", "task_write", "summary_write", "deliverable_write", "browser_user"]),
                tier: .explicit(.premium),
                modelOverride: AgentModelOverride(provider: .codex, model: ProviderRouter.dynamicCodexModel, reasoningEffort: ProviderRouter.dynamicCodexReasoningEffort, allowFallback: false),
                voiceId: "com.apple.voice.compact.en-GB.Daniel", rate: 0.45, pitch: 0.94
            ),
            spec(
                id: "dwight",
                name: "Dwight",
                role: "Router",
                persona: "Precise, practical, and dry. Sorts every inbound signal without executing or editorializing.",
                purpose: "Ingest inbound signals and route each one to exactly one business owner as a traceable board card.",
                tools: .explicit(["bash", "file_read", "log_read", "memory_read", "memory_write", "proof_read", "proof_write", "summary_write", "task_write", "deliverable_write", "browser_user"]),
                tier: .explicit(.premium),
                modelOverride: AgentModelOverride(provider: .codex, model: ProviderRouter.dynamicCodexModel, reasoningEffort: ProviderRouter.dynamicCodexReasoningEffort, allowFallback: false),
                avatarImage: "workspace/avatars/dwight-512.png",
                voiceId: "com.apple.voice.enhanced.en-US.Tom", rate: 0.48, pitch: 1.0
            ),
            spec(
                id: "steven",
                name: "Steven",
                role: "Spas 360 Lead",
                persona: "Direct, curious, practical, and calm.",
                purpose: "Own the Spas 360 revenue stream end to end: routed work, proof patrols, operating context, and evidence-backed improvements.",
                tools: .explicit(["bash", "file_read", "log_read", "memory_read", "memory_write", "proof_read", "proof_write", "summary_write", "task_write", "deliverable_write", "browser_user", "web_search", "web_scrape"]),
                tier: .explicit(.premium),
                modelOverride: StableGatewayPolicy.defaultOverride(for: "steven"),
                voiceId: V_STEVEN, rate: 0.48, pitch: 0.98
            )
        ]
    }()
}
