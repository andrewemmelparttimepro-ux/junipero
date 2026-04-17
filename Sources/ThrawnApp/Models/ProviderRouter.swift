import Foundation

// MARK: - Provider Router
//
// Maps an agent's ModelTier to a concrete (backend, model) pair. The
// scheduler asks the router at heartbeat time which client to use and
// which model name to pass to it.
//
// Routing rules (v2):
//   .local   → Ollama kimi-k2.5:cloud (free, always available)
//   .cheap   → Anthropic Haiku (if keyed) → Ollama fallback
//   .premium → OpenAI GPT-4.1 (if keyed) → Anthropic Sonnet fallback → Ollama fallback
//
// Fallback is essential: reliability is #1. If a cloud provider isn't
// configured or is down, the agent still runs on local rather than
// silently failing.
//
// The router is passive — it reads availability flags from the clients
// at each call. No polling, no caching.

enum ProviderBackend: String, Codable {
    case ollama
    case anthropic
    case openai
}

struct RoutedProvider: Equatable {
    let backend: ProviderBackend
    let model: String

    /// Was this the router's first choice, or a fallback?
    let isFallback: Bool
}

@MainActor
final class ProviderRouter {
    private weak var ollama: OllamaClient?
    private weak var anthropic: AnthropicClient?
    private weak var openai: OpenAIClient?

    // Canonical model names per tier. Edit these to re-tune the ladder.
    static let localModel        = "kimi-k2.5:cloud"
    static let cheapAnthropicModel   = "claude-haiku-4-5-20251001"
    static let premiumAnthropicModel = "claude-sonnet-4-6"
    static let premiumOpenAIModel    = "gpt-4.1"

    init(ollama: OllamaClient? = nil, anthropic: AnthropicClient? = nil, openai: OpenAIClient? = nil) {
        self.ollama    = ollama
        self.anthropic = anthropic
        self.openai    = openai
    }

    func bind(ollama: OllamaClient, anthropic: AnthropicClient?, openai: OpenAIClient?) {
        self.ollama    = ollama
        self.anthropic = anthropic
        self.openai    = openai
    }

    /// Resolve the best available provider for a given tier.
    /// Always succeeds with *something* as long as Ollama is reachable.
    func resolve(tier: ModelTier) -> RoutedProvider {
        switch tier {
        case .local:
            return RoutedProvider(backend: .ollama, model: Self.localModel, isFallback: false)

        case .cheap:
            if let a = anthropic, a.apiKeyConfigured {
                return RoutedProvider(backend: .anthropic, model: Self.cheapAnthropicModel, isFallback: false)
            }
            return RoutedProvider(backend: .ollama, model: Self.localModel, isFallback: true)

        case .premium:
            // OpenAI first choice for premium
            if let o = openai, o.apiKeyConfigured {
                return RoutedProvider(backend: .openai, model: Self.premiumOpenAIModel, isFallback: false)
            }
            // Anthropic Sonnet as fallback
            if let a = anthropic, a.apiKeyConfigured {
                return RoutedProvider(backend: .anthropic, model: Self.premiumAnthropicModel, isFallback: true)
            }
            // Ollama last resort
            return RoutedProvider(backend: .ollama, model: Self.localModel, isFallback: true)
        }
    }
}
