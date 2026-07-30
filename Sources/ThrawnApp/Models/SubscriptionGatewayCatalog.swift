import Foundation

struct SubscriptionGatewayDescriptor: Identifiable, Equatable {
    let id: String
    let displayName: String
    let subtitle: String
    let executableNames: [String]
    let authCommand: String
    let backend: ProviderBackend?

    var detectedExecutablePath: String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let fixedCandidates: [String]
        switch id {
        case "openai":
            fixedCandidates = [
                "/Applications/ChatGPT.app/Contents/Resources/codex",
                "\(home)/.local/bin/codex",
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
            ]
        case "grok":
            fixedCandidates = [
                "\(home)/.grok/bin/grok",
                "\(home)/.local/bin/grok",
                "/opt/homebrew/bin/grok",
                "/usr/local/bin/grok",
            ]
        case "claude":
            fixedCandidates = [
                "\(home)/.local/bin/claude",
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude",
            ]
        case "cursor":
            fixedCandidates = [
                "\(home)/.local/bin/cursor-agent",
                "/opt/homebrew/bin/cursor-agent",
                "/usr/local/bin/cursor-agent",
            ]
        case "opencode":
            fixedCandidates = [
                "\(home)/.opencode/bin/opencode",
                "\(home)/.local/bin/opencode",
                "/opt/homebrew/bin/opencode",
                "/usr/local/bin/opencode",
            ]
        default:
            fixedCandidates = []
        }

        if let match = fixedCandidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return match
        }
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for directory in pathEntries {
            for executable in executableNames {
                let candidate = URL(fileURLWithPath: directory)
                    .appendingPathComponent(executable).path
                if fm.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    var isInstalled: Bool { detectedExecutablePath != nil }
}

enum SubscriptionGatewayCatalog {
    static let all: [SubscriptionGatewayDescriptor] = [
        SubscriptionGatewayDescriptor(
            id: "openai",
            displayName: "OpenAI / ChatGPT",
            subtitle: "Codex app-server · provider-owned ChatGPT login",
            executableNames: ["codex"],
            authCommand: "codex login",
            backend: .codex
        ),
        SubscriptionGatewayDescriptor(
            id: "grok",
            displayName: "Grok / xAI",
            subtitle: "Grok CLI · provider-owned OAuth login",
            executableNames: ["grok"],
            authCommand: "grok --oauth",
            backend: .grok
        ),
        SubscriptionGatewayDescriptor(
            id: "claude",
            displayName: "Claude",
            subtitle: "Claude Code subscription gateway",
            executableNames: ["claude"],
            authCommand: "claude auth login --claudeai",
            backend: .claude
        ),
        SubscriptionGatewayDescriptor(
            id: "cursor",
            displayName: "Cursor",
            subtitle: "Cursor Agent subscription gateway",
            executableNames: ["cursor-agent"],
            authCommand: "cursor-agent",
            backend: nil
        ),
        SubscriptionGatewayDescriptor(
            id: "opencode",
            displayName: "OpenCode",
            subtitle: "OpenCode provider gateway",
            executableNames: ["opencode"],
            authCommand: "opencode auth login",
            backend: nil
        ),
    ]
}
