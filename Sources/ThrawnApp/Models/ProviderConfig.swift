import Foundation
import SwiftUI

// MARK: - AI Provider
//
// The case name is preserved for persisted-state compatibility. It now
// represents Codex CLI/app-server rather than a copied API credential.

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case chatgpt  // Codex CLI — provider-owned ChatGPT/API authentication

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chatgpt: return "Codex Agent Runtime"
        }
    }

    var shortName: String {
        switch self {
        case .chatgpt: return "Codex"
        }
    }

    var subtitle: String {
        switch self {
        case .chatgpt: return "Uses the models available to your signed-in Codex CLI"
        }
    }

    var brandColor: Color {
        switch self {
        case .chatgpt: return Color(red: 0.40, green: 0.85, blue: 0.60)
        }
    }

    var brandGradient: [Color] {
        switch self {
        case .chatgpt:
            return [Color(red: 0.40, green: 0.85, blue: 0.60), Color(red: 0.20, green: 0.70, blue: 0.55)]
        }
    }

    var icon: String {
        switch self {
        case .chatgpt: return "bubble.left.and.text.bubble.right"
        }
    }

    var authMethod: AuthMethod {
        switch self {
        case .chatgpt: return .providerCLI
        }
    }

    var keyPrefix: String? {
        switch self {
        case .chatgpt: return nil
        }
    }

    var getKeyURL: URL? {
        switch self {
        case .chatgpt: return nil
        }
    }

    var apiBaseURL: String {
        switch self {
        case .chatgpt: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .chatgpt: return ProviderRouter.dynamicCodexModel
        }
    }

    var availableModels: [String] {
        switch self {
        case .chatgpt: return [ProviderRouter.dynamicCodexModel]
        }
    }

    enum AuthMethod {
        case apiKey
        case providerCLI
    }

    /// Auto-detect provider from a pasted API key.
    static func detect(from key: String) -> AIProvider? {
        nil
    }
}

// MARK: - Provider Configuration (Persisted)

struct ProviderState: Codable {
    var activeProvider: AIProvider
    var connectedProviders: [AIProvider: ProviderCredential]

    static let `default` = ProviderState(
        activeProvider: .chatgpt,
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
    // For OpenAI Compatible Providers
    var customBaseURL: String?
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
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            FlightRecorder.logError(
                source: "providerconfig:save",
                message: "createDirectory failed: \(error.localizedDescription)"
            )
            return
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(state)
        } catch {
            FlightRecorder.logError(
                source: "providerconfig:save",
                message: "Encode failed: \(error.localizedDescription)"
            )
            return
        }
        do {
            try data.write(to: fileURL, options: .atomic)
            NotificationCenter.default.post(name: changedNotification, object: nil)
        } catch {
            FlightRecorder.logError(
                source: "providerconfig:save",
                message: "Write \(fileURL.lastPathComponent) failed: \(error.localizedDescription)"
            )
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
            state.activeProvider = state.connectedProviders.keys.first ?? .chatgpt
        }
        save(state)
    }
}
