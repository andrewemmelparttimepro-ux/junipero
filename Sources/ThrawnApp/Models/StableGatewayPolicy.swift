import Foundation

// MARK: - Stable subscription gateway policy
//
// This is deliberately a one-time migration policy, not a launch-time lock.
// The requested starting routes are installed once; subsequent choices made in
// the Agents console remain durable.

enum StableGatewayPolicy {
    static let currentVersion = 1
    static let stableAgentIDs = ["thrawn", "archivist", "sentinel", "dwight", "steven"]
    static let openAIAgentIDs: Set<String> = ["thrawn", "archivist", "sentinel", "dwight"]

    static func defaultOverride(for agentID: String) -> AgentModelOverride? {
        if openAIAgentIDs.contains(agentID) {
            return AgentModelOverride(
                provider: .codex,
                model: ProviderRouter.dynamicCodexModel,
                reasoningEffort: ProviderRouter.dynamicCodexReasoningEffort,
                allowFallback: false
            )
        }
        if agentID == "steven" {
            return AgentModelOverride(
                provider: .grok,
                model: ProviderRouter.dynamicGrokModel,
                reasoningEffort: ProviderRouter.dynamicGrokReasoningEffort,
                allowFallback: false
            )
        }
        return nil
    }

    static func applyDefaults(to specs: [AgentSpec]) -> [AgentSpec] {
        specs.map { spec in
            guard let route = defaultOverride(for: spec.id) else { return spec }
            var updated = spec
            updated.modelOverride = route
            return updated
        }
    }

    static func route(for backend: ProviderBackend) -> AgentModelOverride {
        switch backend {
        case .grok:
            return AgentModelOverride(
                provider: .grok,
                model: ProviderRouter.dynamicGrokModel,
                reasoningEffort: ProviderRouter.dynamicGrokReasoningEffort,
                allowFallback: false
            )
        case .codex:
            return AgentModelOverride(
                provider: .codex,
                model: ProviderRouter.dynamicCodexModel,
                reasoningEffort: ProviderRouter.dynamicCodexReasoningEffort,
                allowFallback: false
            )
        case .claude:
            return AgentModelOverride(
                provider: .claude,
                model: ProviderRouter.dynamicClaudeModel,
                reasoningEffort: ProviderRouter.dynamicClaudeReasoningEffort,
                allowFallback: false
            )
        case .ollama, .openai, .openclaw, .xai:
            return AgentModelOverride(
                provider: backend,
                model: ProviderRouter.dynamicCodexModel,
                reasoningEffort: nil,
                allowFallback: false
            )
        }
    }
}

extension ProviderBackend {
    var gatewayDisplayName: String {
        switch self {
        case .codex: return "OpenAI · ChatGPT"
        case .grok: return "Grok · xAI"
        case .claude: return "Claude · Anthropic"
        case .ollama: return "Ollama"
        case .openai: return "OpenAI-compatible API"
        case .openclaw: return "OpenClaw"
        case .xai: return "xAI API key"
        }
    }

    var isSubscriptionGateway: Bool {
        self == .codex || self == .grok || self == .claude
    }
}
