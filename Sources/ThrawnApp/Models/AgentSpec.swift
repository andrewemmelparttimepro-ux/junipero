import Foundation

// MARK: - Agent Spec
//
// An AgentSpec is the full definition of an agent: who they are, what
// they're for, which tools are shown as metadata, which model tier they run on,
// how long they live, and where their memory is kept.
//
// Specs are loaded from ~/Library/Application Support/Thrawn/agent-specs.json
// at startup. If the file doesn't exist, we seed it with defaults that
// match the current dev-ops squad so behavior is identical to pre-spec days.
//
// INHERITANCE: tools and tier can be set to `.inherit`, which means the
// resolver pulls metadata from the StandardLoadout at read time. If the
// Standard Loadout changes, every spec that inherits follows automatically.

// MARK: Rank

enum AgentRank: String, Codable, CaseIterable {
    case s = "S"
    case a = "A"
    case b = "B"
    case c = "C"

    var displayName: String { rawValue }

    /// Sort order: S highest, C lowest.
    var sortOrder: Int {
        switch self {
        case .s: return 0
        case .a: return 1
        case .b: return 2
        case .c: return 3
        }
    }
}

// MARK: Model Tier
//
// Which pool of models an agent should use. The ProviderRouter maps tiers to
// authenticated provider agents. Durable production agents use the live Codex
// subscription catalog unless a spec pins an exact provider/model override.

enum ModelTier: String, Codable, CaseIterable {
    case local    // Legacy/developer local route.
    case cheap    // Budget tier; currently mapped to OpenClaw GPT.
    case premium  // Premium OpenClaw GPT subscription route.
}

// MARK: Model Override
//
// Most agents resolve through tier -> provider routing. Specialized durable
// agents can pin an exact provider/model/reasoning pair when the operator
// needs a contractual route, not a best-effort tier.

struct AgentModelOverride: Codable, Equatable {
    var provider: ProviderBackend
    var model: String
    var reasoningEffort: String?
    var allowFallback: Bool

    init(
        provider: ProviderBackend,
        model: String,
        reasoningEffort: String? = nil,
        allowFallback: Bool = true
    ) {
        self.provider = provider
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.allowFallback = allowFallback
    }
}

// MARK: Tools Binding
//
// An agent's displayed tool list is either inherited from the Standard Loadout
// or explicitly overridden. Inheritance is a reference, not a copy.

enum ToolsBinding: Codable, Equatable {
    case inherit
    case explicit([String])

    // Codable: encode as `{"mode":"inherit"}` or `{"mode":"explicit","tools":[...]}`
    private enum CodingKeys: String, CodingKey { case mode, tools }
    private enum Mode: String, Codable { case inherit, explicit }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try c.decode(Mode.self, forKey: .mode)
        switch mode {
        case .inherit:
            self = .inherit
        case .explicit:
            let tools = try c.decode([String].self, forKey: .tools)
            self = .explicit(tools)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inherit:
            try c.encode(Mode.inherit, forKey: .mode)
        case .explicit(let tools):
            try c.encode(Mode.explicit, forKey: .mode)
            try c.encode(tools, forKey: .tools)
        }
    }
}

// MARK: Lifecycle

enum AgentLifecycle: Codable, Equatable {
    /// Persistent agent — runs on heartbeat schedule indefinitely.
    case persistent
    /// Ephemeral agent — retires after `taskBudget` tasks completed, or
    /// when the associated objective is closed. Great for one-off personas.
    case ephemeral(taskBudget: Int)

    private enum CodingKeys: String, CodingKey { case kind, taskBudget }
    private enum Kind: String, Codable { case persistent, ephemeral }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .persistent:
            self = .persistent
        case .ephemeral:
            let budget = try c.decode(Int.self, forKey: .taskBudget)
            self = .ephemeral(taskBudget: budget)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .persistent:
            try c.encode(Kind.persistent, forKey: .kind)
        case .ephemeral(let budget):
            try c.encode(Kind.ephemeral, forKey: .kind)
            try c.encode(budget, forKey: .taskBudget)
        }
    }
}

// MARK: Grade Entry (SOD/EOD rolling history)
//
// One entry per briefing the agent self-issues. Kept on the spec so
// RankEvaluator can consume a rolling average when it scores ranks.
// Grades are letter strings ("A", "B+", "C-", "F") so the LLM can
// return them directly without a lookup table; the numeric mapping
// lives in a helper below.

enum BriefingKind: String, Codable {
    case sod  // Start of Day — today's plan
    case eod  // End of Day   — yesterday's review
}

struct GradeEntry: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    let date: Date
    let kind: BriefingKind
    let grade: String        // "A", "B+", "F", etc.
    let improvement: String  // one-sentence improvement pledge

    private enum CodingKeys: String, CodingKey {
        case id, date, kind, grade, improvement
    }

    init(date: Date, kind: BriefingKind, grade: String, improvement: String) {
        self.id = UUID()
        self.date = date
        self.kind = kind
        self.grade = grade
        self.improvement = improvement
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.date = try c.decode(Date.self, forKey: .date)
        self.kind = try c.decode(BriefingKind.self, forKey: .kind)
        self.grade = try c.decode(String.self, forKey: .grade)
        self.improvement = try c.decode(String.self, forKey: .improvement)
    }

    /// Convert a letter grade to a 0.0–4.0 GPA scale. Unknown grades
    /// return nil so the average skips them.
    var gpa: Double? {
        switch grade.uppercased() {
        case "A+": return 4.3
        case "A":  return 4.0
        case "A-": return 3.7
        case "B+": return 3.3
        case "B":  return 3.0
        case "B-": return 2.7
        case "C+": return 2.3
        case "C":  return 2.0
        case "C-": return 1.7
        case "D+": return 1.3
        case "D":  return 1.0
        case "D-": return 0.7
        case "F":  return 0.0
        default: return nil
        }
    }
}

// MARK: Spec

struct AgentSpec: Codable, Identifiable, Equatable {
    // Identity
    let id: String          // Stable ID used everywhere: "thrawn", "researcher", "jane-doe"
    var name: String        // Display name: "R2-D2", "Jane Doe"
    var role: String        // One-line role: "Dev", "Marketing Muse", ...

    // Persona + purpose — injected into the heartbeat prompt.
    // `persona` is the voice/identity fragment, `purpose` is the mission.
    var persona: String
    var purpose: String

    // Capability gating. `.inherit` follows the Standard Loadout live.
    var tools: ToolsBinding

    // Which model pool this agent runs on. `.inherit` follows Standard Loadout.
    var tier: ModelTierBinding

    // Optional exact provider/model route. When present, this wins over tier.
    var modelOverride: AgentModelOverride?

    // Current rank. Dev-ops squad is pinned at `.b`; future agents move via
    // scoring (Step 5). The `pinned` flag blocks auto-promotion/demotion.
    var rank: AgentRank
    var pinned: Bool

    // Lifecycle. Dev-ops squad is `.persistent`.
    var lifecycle: AgentLifecycle

    // Optional knowledge directory (relative to ops root). Nil = no memory.
    // Conventionally `workspace/agents/{id}/knowledge/`.
    var knowledgeDir: String?

    // Optional display art paths. Resource-backed avatars use the Swift
    // bundle, but these keep the workspace/spec source of truth explicit.
    var avatar: String?
    var avatarThumbnail: String?
    var avatarImage: String?

    // Tasks completed by this agent so far (drives ephemeral retirement).
    var tasksCompleted: Int

    // When the agent was created; used for sorting and for audit.
    var createdAt: Date

    // MARK: Voice (AVSpeechSynthesizer)
    //
    // Each agent can have their own system voice + prosody. When the
    // VoiceService fires an announcement, it uses these values to pick
    // the right AVSpeechSynthesisVoice and utterance parameters.
    //
    // `voiceIdentifier` is an AVSpeechSynthesisVoice.identifier — use
    // `AVSpeechSynthesisVoice(identifier:)` to resolve. Nil = system default.
    //
    // `speechRate` uses AVSpeechUtterance's normalized 0.0–1.0 scale
    // (default 0.5 ≈ natural). `speechPitch` is 0.5–2.0 (1.0 = natural).
    //
    // `voiceMuted` is a per-agent kill switch. Useful for R2 (no voice —
    // SFX bank instead) or for temporarily silencing a noisy agent.
    var voiceIdentifier: String?
    var speechRate: Float
    var speechPitch: Float
    var voiceMuted: Bool

    // MARK: Briefing grade history
    //
    // Rolling window of the agent's own SOD/EOD grades. Capped at 14
    // entries (≈ 7 days × 2 procedures) by the store on append. Older
    // entries drop off the front so the tail stays bounded forever.
    var gradeHistory: [GradeEntry]

    // Memberwise init — provides defaults for the voice fields so all
    // existing construction sites keep compiling without having to pass
    // voice args. Seeded specs override these.
    init(
        id: String,
        name: String,
        role: String,
        persona: String,
        purpose: String,
        tools: ToolsBinding,
        tier: ModelTierBinding,
        modelOverride: AgentModelOverride? = nil,
        rank: AgentRank,
        pinned: Bool,
        lifecycle: AgentLifecycle,
        knowledgeDir: String? = nil,
        avatar: String? = nil,
        avatarThumbnail: String? = nil,
        avatarImage: String? = nil,
        tasksCompleted: Int = 0,
        createdAt: Date = Date(),
        voiceIdentifier: String? = nil,
        speechRate: Float = 0.50,
        speechPitch: Float = 1.0,
        voiceMuted: Bool = false,
        gradeHistory: [GradeEntry] = []
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.persona = persona
        self.purpose = purpose
        self.tools = tools
        self.tier = tier
        self.modelOverride = modelOverride
        self.rank = rank
        self.pinned = pinned
        self.lifecycle = lifecycle
        self.knowledgeDir = knowledgeDir
        self.avatar = avatar
        self.avatarThumbnail = avatarThumbnail
        self.avatarImage = avatarImage
        self.tasksCompleted = tasksCompleted
        self.createdAt = createdAt
        self.voiceIdentifier = voiceIdentifier
        self.speechRate = speechRate
        self.speechPitch = speechPitch
        self.voiceMuted = voiceMuted
        self.gradeHistory = gradeHistory
    }

    // MARK: Codable
    //
    // Custom init(from:) lets old persisted specs (without voice fields)
    // decode cleanly — any missing voice key falls back to a default.
    // encode(to:) stays synthesized.
    private enum CodingKeys: String, CodingKey {
        case id, name, role, persona, purpose
        case tools, tier, modelOverride, rank, pinned, lifecycle
        case knowledgeDir, avatar, avatarThumbnail, avatarImage
        case tasksCompleted, createdAt
        case voiceIdentifier, speechRate, speechPitch, voiceMuted
        case gradeHistory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        role = try c.decode(String.self, forKey: .role)
        persona = try c.decode(String.self, forKey: .persona)
        purpose = try c.decode(String.self, forKey: .purpose)
        tools = try c.decode(ToolsBinding.self, forKey: .tools)
        tier = try c.decode(ModelTierBinding.self, forKey: .tier)
        modelOverride = try c.decodeIfPresent(AgentModelOverride.self, forKey: .modelOverride)
        rank = try c.decode(AgentRank.self, forKey: .rank)
        pinned = try c.decode(Bool.self, forKey: .pinned)
        lifecycle = try c.decode(AgentLifecycle.self, forKey: .lifecycle)
        knowledgeDir = try c.decodeIfPresent(String.self, forKey: .knowledgeDir)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        avatarThumbnail = try c.decodeIfPresent(String.self, forKey: .avatarThumbnail)
        avatarImage = try c.decodeIfPresent(String.self, forKey: .avatarImage)
        tasksCompleted = try c.decodeIfPresent(Int.self, forKey: .tasksCompleted) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        voiceIdentifier = try c.decodeIfPresent(String.self, forKey: .voiceIdentifier)
        speechRate = try c.decodeIfPresent(Float.self, forKey: .speechRate) ?? 0.50
        speechPitch = try c.decodeIfPresent(Float.self, forKey: .speechPitch) ?? 1.0
        voiceMuted = try c.decodeIfPresent(Bool.self, forKey: .voiceMuted) ?? false
        gradeHistory = try c.decodeIfPresent([GradeEntry].self, forKey: .gradeHistory) ?? []
    }
}

// MARK: ModelTierBinding
//
// Symmetric with ToolsBinding — lets a spec say "use whatever the standard
// loadout says" or override with an explicit tier.

enum ModelTierBinding: Codable, Equatable {
    case inherit
    case explicit(ModelTier)

    private enum CodingKeys: String, CodingKey { case mode, tier }
    private enum Mode: String, Codable { case inherit, explicit }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try c.decode(Mode.self, forKey: .mode)
        switch mode {
        case .inherit:
            self = .inherit
        case .explicit:
            let tier = try c.decode(ModelTier.self, forKey: .tier)
            self = .explicit(tier)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inherit:
            try c.encode(Mode.inherit, forKey: .mode)
        case .explicit(let tier):
            try c.encode(Mode.explicit, forKey: .mode)
            try c.encode(tier, forKey: .tier)
        }
    }
}
