import Foundation

// MARK: - Provider Router
//
// Maps an agent's ModelTier to a concrete (backend, model) pair. The
// scheduler asks the router at heartbeat time which client to use and
// which model name to pass to it.
//
// Routing rules:
//   .local   -> authenticated Codex CLI agent runtime
//   .cheap   -> authenticated Codex CLI agent runtime
//   .premium -> authenticated Codex CLI agent runtime
//
// API, Ollama, and OpenClaw clients remain available as explicit fallback
// adapters. Normal Thrawn and agent routes use Codex app-server and discover
// the account's current model catalog at runtime. No model slug is purchased
// through or constrained by an API aggregator.

enum ProviderBackend: String, Codable {
    case codex
    case grok
    case claude
    case ollama
    case openai
    case openclaw
    case xai
}

struct RoutedProvider: Equatable {
    let backend: ProviderBackend
    let model: String

    /// Was this the router's first choice, or a fallback?
    let isFallback: Bool

    /// Provider-specific reasoning effort, when the backend supports it.
    let reasoningEffort: String?

    /// Whether a failed cloud route may fall back to another provider.
    let allowFallback: Bool

    init(
        backend: ProviderBackend,
        model: String,
        isFallback: Bool,
        reasoningEffort: String? = nil,
        allowFallback: Bool = true
    ) {
        self.backend = backend
        self.model = model
        self.isFallback = isFallback
        self.reasoningEffort = reasoningEffort
        self.allowFallback = allowFallback
    }
}

@MainActor
final class ProviderRouter {
    private weak var ollama: OllamaClient?
    private weak var openai: OpenAIClient?

    // Canonical cloud model configuration.
    nonisolated static let glmModel = "glm-5.2"
    nonisolated static let glmBaseURL = "https://api.z.ai/api/paas/v4"
    nonisolated static let glmKeychainService = "com.thrawn.glm"
    nonisolated static let glmConfigFileName = "glm-config.json"
    nonisolated static let xaiModel = "grok-4.5"
    nonisolated static let xaiBaseURL = "https://api.x.ai/v1"
    nonisolated static let xaiKeychainService = "com.thrawn.xai"
    nonisolated static let xaiConfigFileName = "xai-config.json"

    // Subscription-backed Codex CLI route. "auto" is resolved by
    // AgentRuntimeCoordinator from model/list on the live authenticated account.
    nonisolated static let dynamicCodexModel = "auto"
    nonisolated static let dynamicCodexReasoningEffort = "auto"
    nonisolated static let codexLabel = "Codex subscription"
    nonisolated static let dynamicGrokModel = "grok-4.5"
    nonisolated static let dynamicGrokReasoningEffort = "auto"
    nonisolated static let grokLabel = "Grok subscription"
    nonisolated static let dynamicClaudeModel = "auto"
    nonisolated static let dynamicClaudeReasoningEffort = "high"
    nonisolated static let claudeLabel = "Claude subscription"

    // Subscription-backed GPT route exposed by OpenClaw.
    nonisolated static let localModel = "openai-codex/gpt-5.4"
    nonisolated static let premiumOpenAIModel = "glm-5.2"
    nonisolated static let premiumOpenAIReasoningEffort = "max"
    nonisolated static let premiumOpenAILabel = "GLM-5.2"
    nonisolated static let premiumOpenClawModel = "openai-codex/gpt-5.4"
    nonisolated static let premiumOpenClawThinkingLevel = "xhigh"
    nonisolated static let premiumOpenClawLabel = "GPT-5.4"
    nonisolated static let thrawnDegradedLabel = "Thrawn unavailable · OpenClaw GPT route failed"

    nonisolated static func thrawnCoreRoute(openAIConfigured: Bool) -> RoutedProvider {
        RoutedProvider(
            backend: .codex,
            model: Self.dynamicCodexModel,
            isFallback: false,
            reasoningEffort: Self.dynamicCodexReasoningEffort,
            allowFallback: false
        )
    }

    init(ollama: OllamaClient? = nil, openai: OpenAIClient? = nil) {
        self.ollama    = ollama
        self.openai    = openai
    }

    func bind(ollama: OllamaClient, openai: OpenAIClient?) {
        self.ollama    = ollama
        self.openai    = openai
    }

    /// Resolve the provider for a given tier.
    func resolve(tier: ModelTier) -> RoutedProvider {
        switch tier {
        case .local, .cheap, .premium:
            return RoutedProvider(
                backend: .codex,
                model: Self.dynamicCodexModel,
                isFallback: false,
                reasoningEffort: Self.dynamicCodexReasoningEffort,
                allowFallback: false
            )
        }
    }
}
