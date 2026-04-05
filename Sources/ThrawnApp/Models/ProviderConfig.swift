import Foundation
import SwiftUI

// MARK: - AI Provider
//
// Multi-provider support. Gemini is primary (OAuth, free tier).
// Claude and ChatGPT available as alternatives (API key).
// Under the hood they're all the same: HTTP + SSE + JSON.

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case gemini   // Google — OAuth, free tier, subscription
    case claude   // Anthropic — API key
    case chatgpt  // OpenAI — API key

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini:  return "Google Gemini"
        case .claude:  return "Claude"
        case .chatgpt: return "ChatGPT"
        }
    }

    var shortName: String {
        switch self {
        case .gemini:  return "Gemini"
        case .claude:  return "Claude"
        case .chatgpt: return "ChatGPT"
        }
    }

    var subtitle: String {
        switch self {
        case .gemini:  return "Sign in with Google • Free tier included"
        case .claude:  return "Best for code & reasoning • API key"
        case .chatgpt: return "GPT-4o & reasoning models • API key"
        }
    }

    var brandColor: Color {
        switch self {
        case .gemini:  return Color(red: 0.26, green: 0.52, blue: 0.96)  // Google blue
        case .claude:  return Color(red: 0.82, green: 0.55, blue: 0.20)  // Anthropic tan/orange
        case .chatgpt: return Color(red: 0.40, green: 0.85, blue: 0.60)  // OpenAI green
        }
    }

    var brandGradient: [Color] {
        switch self {
        case .gemini:
            return [Color(red: 0.26, green: 0.52, blue: 0.96), Color(red: 0.55, green: 0.36, blue: 0.97)]
        case .claude:
            return [Color(red: 0.82, green: 0.55, blue: 0.20), Color(red: 0.75, green: 0.38, blue: 0.18)]
        case .chatgpt:
            return [Color(red: 0.40, green: 0.85, blue: 0.60), Color(red: 0.20, green: 0.70, blue: 0.55)]
        }
    }

    var icon: String {
        switch self {
        case .gemini:  return "sparkles"
        case .claude:  return "brain.head.profile"
        case .chatgpt: return "bubble.left.and.text.bubble.right"
        }
    }

    var authMethod: AuthMethod {
        switch self {
        case .gemini:  return .oauth
        case .claude:  return .apiKey
        case .chatgpt: return .apiKey
        }
    }

    var keyPrefix: String? {
        switch self {
        case .gemini:  return nil  // OAuth, no key
        case .claude:  return "sk-ant-"
        case .chatgpt: return "sk-"
        }
    }

    var getKeyURL: URL? {
        switch self {
        case .gemini:  return nil  // OAuth, no key needed
        case .claude:  return URL(string: "https://console.anthropic.com/settings/keys")
        case .chatgpt: return URL(string: "https://platform.openai.com/api-keys")
        }
    }

    var apiBaseURL: String {
        switch self {
        case .gemini:  return "https://generativelanguage.googleapis.com"
        case .claude:  return "https://api.anthropic.com"
        case .chatgpt: return "https://api.openai.com"
        }
    }

    var defaultModel: String {
        switch self {
        case .gemini:  return "gemini-2.5-flash"
        case .claude:  return "claude-sonnet-4-6"
        case .chatgpt: return "gpt-4o"
        }
    }

    var availableModels: [String] {
        switch self {
        case .gemini:  return ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"]
        case .claude:  return ["claude-sonnet-4-6", "claude-haiku-4-5-20251001", "claude-opus-4-20250514"]
        case .chatgpt: return ["gpt-4o", "gpt-4o-mini", "o3-mini"]
        }
    }

    enum AuthMethod {
        case oauth    // Gemini — browser-based sign-in
        case apiKey   // Claude, ChatGPT — paste key
    }

    /// Auto-detect provider from a pasted API key.
    static func detect(from key: String) -> AIProvider? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("sk-ant-") { return .claude }
        if trimmed.hasPrefix("sk-proj-") || trimmed.hasPrefix("sk-") { return .chatgpt }
        return nil
    }
}

// MARK: - Provider Configuration (Persisted)

struct ProviderState: Codable {
    var activeProvider: AIProvider
    var connectedProviders: [AIProvider: ProviderCredential]

    static let `default` = ProviderState(
        activeProvider: .gemini,
        connectedProviders: [:]
    )
}

struct ProviderCredential: Codable {
    var provider: AIProvider
    var model: String
    var isConnected: Bool
    var lastValidated: Date?
    // For API key providers
    var keychainService: String?
    // For OAuth providers
    var hasRefreshToken: Bool
    var userEmail: String?
}

// MARK: - Provider State Store

enum ProviderStateStore {
    static let changedNotification = Notification.Name("ProviderStateChanged")

    private static var fileURL: URL {
        ThrawnPaths.appSupportDir.appendingPathComponent("provider-state.json")
    }

    static func load() -> ProviderState {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(ProviderState.self, from: data) else {
            return .default
        }
        return decoded
    }

    static func save(_ state: ProviderState) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: fileURL, options: .atomic)
            NotificationCenter.default.post(name: changedNotification, object: nil)
        }
    }

    static func setActiveProvider(_ provider: AIProvider) {
        var state = load()
        state.activeProvider = provider
        save(state)
    }

    static func setConnected(_ credential: ProviderCredential) {
        var state = load()
        state.connectedProviders[credential.provider] = credential
        save(state)
    }

    static func disconnect(_ provider: AIProvider) {
        var state = load()
        state.connectedProviders.removeValue(forKey: provider)
        // If disconnecting active provider, fall back to any connected one
        if state.activeProvider == provider {
            state.activeProvider = state.connectedProviders.keys.first ?? .gemini
        }
        save(state)
    }
}
