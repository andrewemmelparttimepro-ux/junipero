import Foundation

/// Creates a browser-like provider profile for every agent.
///
/// Credentials and provider sessions remain inside the provider-owned home
/// directory. Thrawn only chooses which isolated home a provider process uses.
final class AgentProviderProfileStore {
    private let rootDirectory: URL
    private let homeDirectory: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL = ThrawnPaths.appSupportDir
            .appendingPathComponent("subscription-profiles", isDirectory: true),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    func profileDirectory(agentID: String, backend: ProviderBackend) -> URL {
        rootDirectory
            .appendingPathComponent(safeComponent(agentID), isDirectory: true)
            .appendingPathComponent(providerDirectoryName(backend), isDirectory: true)
    }

    /// Prepares both provider homes for every stable agent and, once only,
    /// seeds the user's current account into the requested starting route.
    func prepareStableProfiles() {
        for agentID in StableGatewayPolicy.stableAgentIDs {
            prepareProfile(agentID: agentID, backend: .codex)
            prepareProfile(agentID: agentID, backend: .grok)
            prepareProfile(agentID: agentID, backend: .claude)
        }

        for agentID in StableGatewayPolicy.openAIAgentIDs {
            seedCurrentAccountOnce(agentID: agentID, backend: .codex)
        }
        seedCurrentAccountOnce(agentID: "steven", backend: .grok)
    }

    func prepareProfile(agentID: String, backend: ProviderBackend) {
        let directory = profileDirectory(agentID: agentID, backend: backend)
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            if backend == .codex {
                try ensureCodexConfig(in: directory)
            }
        } catch {
            FlightRecorder.logError(
                source: "provider-profile:\(agentID)",
                message: "Could not prepare \(backend.rawValue) profile: \(error.localizedDescription)"
            )
        }
    }

    func seedCurrentAccountOnce(agentID: String, backend: ProviderBackend) {
        let directory = profileDirectory(agentID: agentID, backend: backend)
        prepareProfile(agentID: agentID, backend: backend)

        // Vacuum-fill only. A copied token is a shared grant — two copies
        // refreshing the same grant rotate each other dead (the Aug 2026
        // fleet outage). So: never overwrite an existing auth.json (a real
        // per-profile login always wins), but do fill an empty profile so a
        // fresh install boots. The old once-ever marker made a deleted or
        // dead credential unhealable; it is intentionally ignored now.
        let destination = directory.appendingPathComponent("auth.json")
        let source = sourceAuthFile(for: backend)
        do {
            if fileManager.fileExists(atPath: source.path),
               !fileManager.fileExists(atPath: destination.path) {
                try fileManager.copyItem(at: source, to: destination)
                try fileManager.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: destination.path
                )
                FlightRecorder.logEvent(
                    category: "auth",
                    action: "seed-shared-grant",
                    detail: "\(agentID)/\(backend.rawValue) seeded from the shared CLI login — run a real per-profile sign-in to make this agent independent."
                )
            }
        } catch {
            FlightRecorder.logError(
                source: "provider-profile:\(agentID)",
                message: "Could not seed \(backend.rawValue) account: \(error.localizedDescription)"
            )
        }
    }

    private func sourceAuthFile(for backend: ProviderBackend) -> URL {
        switch backend {
        case .grok:
            return homeDirectory.appendingPathComponent(".grok/auth.json")
        case .claude:
            return homeDirectory.appendingPathComponent(".claude/.credentials.json")
        case .codex, .ollama, .openai, .openclaw, .xai:
            return homeDirectory.appendingPathComponent(".codex/auth.json")
        }
    }

    private func ensureCodexConfig(in directory: URL) throws {
        let config = directory.appendingPathComponent("config.toml")
        guard !fileManager.fileExists(atPath: config.path) else { return }
        let contents = """
        cli_auth_credentials_store = "file"

        [history]
        persistence = "save-all"
        """
        try Data(contents.utf8).write(to: config, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: config.path
        )
    }

    private func providerDirectoryName(_ backend: ProviderBackend) -> String {
        switch backend {
        case .grok: return "grok"
        case .claude: return "claude"
        case .codex, .ollama, .openai, .openclaw, .xai: return "codex"
        }
    }

    private func safeComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = raw.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let value = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return value.isEmpty ? "agent" : value.lowercased()
    }
}
