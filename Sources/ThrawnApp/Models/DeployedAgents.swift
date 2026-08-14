import Foundation
import Security
import SwiftUI

// MARK: - Deployed Agents
//
// The stable's second wing. Samwell, Davos, and Steven are staff officers —
// Thrawn-side personas that advise ABOUT a business. A deployed agent is a
// field operator: he lives INSIDE the business's app, works its live org data
// under its guardrails, and its coworkers talk to him every day.
//
// @ARI in Thrawn reaches the REAL Ari — the same brain, memory, and audit
// trail the SPAS 360 sales floor uses. Nothing is cloned into Thrawn. Thrawn
// authenticates as a genuine org user (thrawn@ndai.pro, created through the
// app's own invite flow), so RLS scopes every tool call and Citadel records
// Thrawn honestly as the requester.
//
// Design doc: docs/DEPLOYED-INTELLIGENCE.md

// MARK: - Registry

/// Everything Thrawn needs to reach one deployed agent. Static for Phase 1 —
/// ARI is the pilot. When Hit Zero / UNISS / OMP agents come online this
/// becomes a loaded registry; the shape is already what their entries need.
struct DeployedAgentConfig: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    /// The business whose app the agent lives in.
    let appName: String
    /// The @token that summons this agent in the main chat ("ari" → @ari).
    let mention: String
    /// The deployed app origin, e.g. https://spas360solo.vercel.app
    let baseURL: URL
    /// Supabase auth origin for the password grant.
    let supabaseURL: URL
    /// The anon key is public by design — it ships in the app's own web bundle.
    let supabaseAnonKey: String
    /// Service identity credentials. The password lives in the login Keychain
    /// under `keychainService` / `email`, never in a file.
    let email: String
    let keychainService: String

    static let ari = DeployedAgentConfig(
        id: "ari-spas360",
        name: "ARI",
        appName: "SPAS 360",
        mention: "ari",
        baseURL: URL(string: "https://spas360solo.vercel.app")!,
        supabaseURL: URL(string: "https://kxyqgkimcdxvfkceoixs.supabase.co")!,
        supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt4eXFna2ltY2R4dmZrY2VvaXhzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIyNjc2NjAsImV4cCI6MjA5Nzg0MzY2MH0.8eebai7kVHLPTw5IHrHEvxeLpeY89GCJnAlemvYEFR0",
        email: "thrawn@ndai.pro",
        keychainService: "thrawn-deployed-ari-spas360"
    )
}

// MARK: - Registry
//
// Deployed agents are CONFIG, not code. The registry ships in OpsBundle and
// can be overridden per machine in Application Support — so a spawn (or a
// future deployment wave) changes its fleet by editing JSON. The built-in
// fallback means a missing or mangled registry can never empty the stable.

enum DeployedAgentRegistry {

    private struct RegistryFile: Codable {
        let version: Int
        let agents: [DeployedAgentConfig]
    }

    static func load() -> [DeployedAgentConfig] {
        for url in candidateURLs() {
            guard let data = try? Data(contentsOf: url) else { continue }
            do {
                let file = try JSONDecoder().decode(RegistryFile.self, from: data)
                if !file.agents.isEmpty { return file.agents }
            } catch {
                // A broken registry is a loud problem, not a silent empty rail.
                NSLog("[Thrawn] deployed-agents.json at %@ is malformed: %@",
                      url.path, error.localizedDescription)
            }
        }
        return [.ari]
    }

    private static func candidateURLs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var urls: [URL] = [
            // Per-machine override wins.
            ThrawnPaths.appSupportDir.appendingPathComponent("deployed-agents.json"),
        ]
        // Release build: OpsBundle inside the app.
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("OpsBundle/deployed-agents.json") {
            urls.append(bundled)
        }
        // Dev tree.
        urls.append(home.appendingPathComponent("Documents/thrawn-console/OpsBundle/deployed-agents.json"))
        return urls
    }
}

// MARK: - Presence

enum DeployedAgentPresence: Equatable {
    case unknown
    case reachable(provider: String, model: String)
    case unreachable(String)

    var isUp: Bool {
        if case .reachable = self { return true }
        return false
    }

    /// Maps onto the roster's activity states so the rail can reuse the same
    /// dot colors the rest of the stable uses.
    var activityState: AgentActivityState {
        switch self {
        case .reachable:   return .idle
        case .unknown:     return .review
        case .unreachable: return .blocked
        }
    }

    var detailLine: String {
        switch self {
        case .reachable(let provider, let model): return "\(model) · \(provider)"
        case .unknown:                            return "Checking presence…"
        case .unreachable(let reason):            return reason
        }
    }
}

// MARK: - Client

protocol DeployedAgentCredentialStore {
    func password(for config: DeployedAgentConfig) -> String?
    func refreshToken(for config: DeployedAgentConfig) -> String?
    func saveRefreshToken(_ token: String, for config: DeployedAgentConfig) throws
    func clearRefreshToken(for config: DeployedAgentConfig)
}

final class DeployedAgentKeychainStore: DeployedAgentCredentialStore {
    private func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    private func refreshService(for config: DeployedAgentConfig) -> String {
        "\(config.keychainService).refresh-token"
    }

    func password(for config: DeployedAgentConfig) -> String? {
        read(service: config.keychainService, account: config.email)
    }

    func refreshToken(for config: DeployedAgentConfig) -> String? {
        read(service: refreshService(for: config), account: config.email)
    }

    func saveRefreshToken(_ token: String, for config: DeployedAgentConfig) throws {
        guard let data = token.data(using: .utf8), !token.isEmpty else { return }
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: refreshService(for: config),
            kSecAttrAccount as String: config.email,
        ]
        let status = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = key
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
            }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func clearRefreshToken(for config: DeployedAgentConfig) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: refreshService(for: config),
            kSecAttrAccount as String: config.email,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// HTTP client for one deployed agent. The first connection uses the existing
/// Keychain password once; every later renewal rotates a persisted Supabase
/// refresh token, so presence polling cannot manufacture sessions all day.
actor DeployedAgentClient {

    struct RunReply {
        let text: String
        let threadID: String
        let artifactTitle: String?
        let toolRounds: Int
    }

    enum ClientError: LocalizedError {
        case missingCredentials
        case authFailed(String)
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "No credentials in the Keychain for this deployed agent."
            case .authFailed(let detail):
                return "Could not sign in to the deployed app: \(detail)"
            case .requestFailed(let detail):
                return detail
            }
        }
    }

    private enum GrantError: Error {
        case rejected(String)
        case malformedResponse
    }

    private struct AuthTokens: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private let config: DeployedAgentConfig
    private let session: URLSession
    private let credentials: DeployedAgentCredentialStore
    private var accessToken: String?
    private var tokenExpiresAt: Date?
    private var authTask: Task<String, Error>?
    private let expiryHeadroom: TimeInterval = 5 * 60

    init(
        config: DeployedAgentConfig,
        session: URLSession = .shared,
        credentials: DeployedAgentCredentialStore = DeployedAgentKeychainStore()
    ) {
        self.config = config
        self.session = session
        self.credentials = credentials
    }

    // MARK: Auth

    private func cachedToken() -> String? {
        guard let accessToken, let tokenExpiresAt,
              tokenExpiresAt.timeIntervalSinceNow > expiryHeadroom
        else { return nil }
        return accessToken
    }

    private func accept(_ tokens: AuthTokens) throws -> String {
        accessToken = tokens.accessToken
        tokenExpiresAt = Date().addingTimeInterval(max(tokens.expiresIn ?? 3600, 600))
        if let refresh = tokens.refreshToken, !refresh.isEmpty {
            try credentials.saveRefreshToken(refresh, for: config)
        }
        return tokens.accessToken
    }

    /// Keep the refresh credential on a 401. The next attempt rotates that
    /// same session instead of creating a replacement session.
    private func dropAccessToken() {
        accessToken = nil
        tokenExpiresAt = nil
    }

    private func grant(kind: String, body: [String: String]) async throws -> AuthTokens {
        var request = URLRequest(
            url: config.supabaseURL.appendingPathComponent("auth/v1/token"),
            timeoutInterval: 15
        )
        request.url = URL(string: request.url!.absoluteString + "?grant_type=\(kind)")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 400 || code == 401 {
            let detail = String(data: data, encoding: .utf8)?.prefix(200) ?? "no detail"
            throw GrantError.rejected(String(detail))
        }
        guard code == 200 else { throw ClientError.authFailed("Auth endpoint returned HTTP \(code)") }
        guard let tokens = try? JSONDecoder().decode(AuthTokens.self, from: data),
              !tokens.accessToken.isEmpty
        else { throw GrantError.malformedResponse }
        return tokens
    }

    private func authenticate() async throws -> String {
        if let refreshToken = credentials.refreshToken(for: config) {
            do {
                return try accept(await grant(kind: "refresh_token", body: ["refresh_token": refreshToken]))
            } catch GrantError.rejected {
                // A revoked/rotated-away refresh credential is the sole reason
                // to fall back to password. Network and 5xx errors must not
                // create a new session as a side effect of an outage.
                credentials.clearRefreshToken(for: config)
            }
        }

        guard let password = credentials.password(for: config) else {
            throw ClientError.missingCredentials
        }
        do {
            return try accept(await grant(kind: "password", body: [
                "email": config.email,
                "password": password,
            ]))
        } catch GrantError.rejected(let detail) {
            throw ClientError.authFailed(detail)
        } catch GrantError.malformedResponse {
            throw ClientError.authFailed("Auth response was incomplete")
        }
    }

    private func validToken() async throws -> String {
        if let token = cachedToken() { return token }
        if let authTask { return try await authTask.value }

        let task = Task { try await self.authenticate() }
        authTask = task
        do {
            let token = try await task.value
            authTask = nil
            return token
        } catch {
            authTask = nil
            throw error
        }
    }

    // MARK: Endpoints

    struct StatusCard {
        let provider: String
        let model: String
        let capabilities: [String]
        /// Which providers the deployment holds keys for — drives picker
        /// availability, so a key added to the server lights options up here
        /// on the next poll.
        let providersAvailable: [String: Bool]
    }

    func status(retryAfterUnauthorized: Bool = true) async throws -> StatusCard {
        let token = try await validToken()
        var request = URLRequest(
            url: config.baseURL.appendingPathComponent("api/agent/status"),
            timeoutInterval: 15
        )
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 {
            guard retryAfterUnauthorized else {
                throw ClientError.authFailed("The deployed app rejected a refreshed session")
            }
            dropAccessToken()
            _ = try await validToken()
            return try await status(retryAfterUnauthorized: false)
        }
        guard code == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["ok"] as? Bool == true
        else {
            throw ClientError.requestFailed("Status endpoint returned HTTP \(code)")
        }
        return StatusCard(
            provider: json["provider"] as? String ?? "?",
            model: json["model"] as? String ?? "?",
            capabilities: json["capabilities"] as? [String] ?? [],
            providersAvailable: json["providers_available"] as? [String: Bool] ?? [:]
        )
    }

    // MARK: Control plane
    //
    // The org's agent_config row — which brain runs the agent, and whether he
    // is paused. Thrawn's identity is an owner_manager, so RLS lets it write.

    struct ConfigRow: Codable, Equatable {
        var org_id: String
        var enabled: Bool
        var provider: String?
        var model: String?
    }

    func fetchConfig(retryAfterUnauthorized: Bool = true) async throws -> ConfigRow? {
        let token = try await validToken()
        var request = URLRequest(
            url: config.supabaseURL.appendingPathComponent("rest/v1/agent_config"),
            timeoutInterval: 15
        )
        request.url = URL(string: request.url!.absoluteString + "?select=org_id,enabled,provider,model&limit=1")
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401, retryAfterUnauthorized {
            dropAccessToken()
            _ = try await validToken()
            return try await fetchConfig(retryAfterUnauthorized: false)
        }
        guard code == 200 else {
            throw ClientError.requestFailed("Config read failed")
        }
        return (try? JSONDecoder().decode([ConfigRow].self, from: data))?.first
    }

    func updateConfig(orgID: String, enabled: Bool?, provider: String?, model: String?, retryAfterUnauthorized: Bool = true) async throws {
        let token = try await validToken()
        var request = URLRequest(
            url: config.supabaseURL.appendingPathComponent("rest/v1/agent_config"),
            timeoutInterval: 15
        )
        request.url = URL(string: request.url!.absoluteString + "?org_id=eq.\(orgID)")
        request.httpMethod = "PATCH"
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        var body: [String: Any] = ["updated_at": ISO8601DateFormatter().string(from: Date())]
        if let enabled { body["enabled"] = enabled }
        if let provider { body["provider"] = provider }
        if let model { body["model"] = model }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401, retryAfterUnauthorized {
            dropAccessToken()
            _ = try await validToken()
            return try await updateConfig(
                orgID: orgID,
                enabled: enabled,
                provider: provider,
                model: model,
                retryAfterUnauthorized: false
            )
        }
        // PostgREST returns the changed rows; zero rows back means RLS
        // silently filtered the write — surface that, never pretend it landed.
        guard code == 200,
              let rows = try? JSONDecoder().decode([ConfigRow].self, from: data),
              !rows.isEmpty
        else {
            throw ClientError.requestFailed("The intelligence change was not accepted (HTTP \(code)).")
        }
    }

    func run(message: String, threadID: String?, retryAfterUnauthorized: Bool = true) async throws -> RunReply {
        let token = try await validToken()
        var request = URLRequest(
            url: config.baseURL.appendingPathComponent("api/agent/run"),
            // Generous: the deployed loop allows up to 6 model rounds.
            timeoutInterval: 180
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = ["message": message]
        if let threadID { body["thread_id"] = threadID }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 {
            guard retryAfterUnauthorized else {
                throw ClientError.authFailed("The deployed app rejected a refreshed session")
            }
            dropAccessToken()
            _ = try await validToken()
            return try await run(message: message, threadID: threadID, retryAfterUnauthorized: false)
        }
        guard code == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messageJSON = json["message"] as? [String: Any],
              let text = messageJSON["content"] as? String,
              let returnedThread = json["thread_id"] as? String
        else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? String }
            throw ClientError.requestFailed(detail ?? "Agent run returned HTTP \(code)")
        }

        let artifact = json["artifact"] as? [String: Any]
        return RunReply(
            text: text,
            threadID: returnedThread,
            artifactTitle: artifact?["title"] as? String,
            toolRounds: json["tool_rounds"] as? Int ?? 0
        )
    }
}

// MARK: - Chat transcript model (dedicated surface)

struct DeployedChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable { case user, agent, notice }
    let id: UUID
    let role: Role
    var text: String
    let date: Date
    var artifactTitle: String?

    init(role: Role, text: String, artifactTitle: String? = nil) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.date = Date()
        self.artifactTitle = artifactTitle
    }
}

// MARK: - Hub

/// One store for the whole deployed fleet. Every piece of per-agent state is
/// keyed by agent id, so the registry alone decides how many colleagues live
/// here — code never has to know their names.
///
/// A singleton rather than an environment object because ThreadStore — which
/// routes @mentions — is constructed before the SwiftUI environment exists,
/// and reachability is app-global state anyway.
@MainActor
final class DeployedAgentHub: ObservableObject {

    static let shared = DeployedAgentHub()
    static let ariAgentID = DeployedAgentConfig.ari.id

    /// The fleet, from OpsBundle's deployed-agents.json. Adding an agent is a
    /// registry entry plus a Keychain credential — rail, presence, mentions,
    /// chat, and control all iterate this.
    let agents: [DeployedAgentConfig]

    @Published var presenceByAgent: [String: DeployedAgentPresence] = [:]
    /// Per-deployment provider availability (key presence on their server),
    /// straight from each agent's status card.
    @Published var providersByAgent: [String: [String: Bool]] = [:]
    @Published private(set) var controlByAgent: [String: DeployedAgentClient.ConfigRow] = [:]
    @Published private(set) var configErrorByAgent: [String: String] = [:]
    @Published private(set) var conversationsByAgent: [String: [DeployedChatMessage]] = [:]
    @Published private(set) var thinkingAgents: Set<String> = []

    private var clients: [String: DeployedAgentClient] = [:]
    /// Deployed-side thread backing each dedicated chat — the agent's memory
    /// lives in HIS app's database; this is just the pointer to it.
    private var dedicatedThreadIDs: [String: String] = [:]
    /// (agent id | Thrawn thread uuid) → deployed thread id, so a second
    /// @mention in the same thread continues the same conversation.
    private var mentionThreadMap: [String: String] = [:]
    private var presenceTimer: Timer?

    func agent(withID id: String) -> DeployedAgentConfig? {
        agents.first { $0.id == id }
    }

    func presence(for agent: DeployedAgentConfig) -> DeployedAgentPresence {
        presenceByAgent[agent.id] ?? .unknown
    }

    func control(for agent: DeployedAgentConfig) -> DeployedAgentClient.ConfigRow? {
        controlByAgent[agent.id]
    }

    func configError(for agent: DeployedAgentConfig) -> String? {
        configErrorByAgent[agent.id]
    }

    func conversation(for agent: DeployedAgentConfig) -> [DeployedChatMessage] {
        conversationsByAgent[agent.id] ?? []
    }

    func isThinking(_ agent: DeployedAgentConfig) -> Bool {
        thinkingAgents.contains(agent.id)
    }

    private func client(for agent: DeployedAgentConfig) -> DeployedAgentClient {
        if let existing = clients[agent.id] { return existing }
        let fresh = DeployedAgentClient(config: agent)
        clients[agent.id] = fresh
        return fresh
    }

    private init() {
        agents = DeployedAgentRegistry.load()
        load()
        refreshPresence()
        // Presence is a courtesy display, not a health monitor — a relaxed
        // cadence keeps the rail honest without hammering the deployed apps.
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPresence() }
        }
    }

    // MARK: Presence

    func refreshPresence() {
        for agent in agents {
            let agentClient = client(for: agent)
            Task { [weak self] in
                guard let self else { return }
                do {
                    let card = try await agentClient.status()
                    self.presenceByAgent[agent.id] = .reachable(provider: card.provider, model: card.model)
                    self.providersByAgent[agent.id] = card.providersAvailable
                    if let row = try? await agentClient.fetchConfig() {
                        self.controlByAgent[agent.id] = row
                    }
                } catch let error as DeployedAgentClient.ClientError {
                    self.presenceByAgent[agent.id] = .unreachable(self.shortReason(for: error))
                } catch {
                    self.presenceByAgent[agent.id] = .unreachable("Unreachable")
                }
            }
        }
    }

    // MARK: Intelligence control
    //
    // Writes the org's agent_config row — the same row that deployment reads
    // on every request — so a change here steers the agent within one
    // request, no redeploy. RLS gates the write to the org's owner tier;
    // Thrawn's identity qualifies in every fleet app.

    struct IntelligenceOption: Identifiable {
        let id: String
        let label: String
        let provider: String
        let model: String
        let available: Bool
        let note: String?
    }

    /// One shared brain catalog; availability comes from each deployment's
    /// own status card (key presence on their server), so an option lights up
    /// the moment its key exists — no Thrawn release. Unknown = unavailable,
    /// never a guess.
    func intelligenceOptions(for agent: DeployedAgentConfig) -> [IntelligenceOption] {
        let available = providersByAgent[agent.id] ?? [:]
        func option(_ id: String, _ label: String, _ provider: String, _ model: String, _ note: String) -> IntelligenceOption {
            let up = available[provider] ?? false
            return IntelligenceOption(
                id: id, label: label, provider: provider, model: model,
                available: up, note: up ? note : "awaiting API key on the server"
            )
        }
        return [
            option("grok", "Grok 4.5", "grok", "grok-4.5", "xAI — same brain as Steven"),
            option("thrawn-grok", "Grok 4.5 · via Thrawn", "thrawn", "grok-4.5",
                   "same brain, routed through this Mac — every conversation lands in the gateway log; falls back to direct automatically"),
            option("glm", "GLM 5.2", "glm", "glm-5.2", "Z.AI"),
            option("gemini", "Gemini 2.0 Flash", "gemini", "gemini-2.0-flash", "Google — fastest, lightest"),
            option("claude", "Claude Sonnet 5", "anthropic", "claude-sonnet-5", "Anthropic"),
        ]
    }

    func setIntelligence(for agent: DeployedAgentConfig, option: IntelligenceOption) {
        guard let orgID = controlByAgent[agent.id]?.org_id else {
            configErrorByAgent[agent.id] = "Config not loaded yet — try again in a moment."
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client(for: agent).updateConfig(
                    orgID: orgID, enabled: nil,
                    provider: option.provider, model: option.model
                )
                self.configErrorByAgent[agent.id] = nil
                self.refreshPresence()
            } catch {
                self.configErrorByAgent[agent.id] = error.localizedDescription
            }
        }
    }

    func setEnabled(for agent: DeployedAgentConfig, enabled: Bool) {
        guard let orgID = controlByAgent[agent.id]?.org_id else {
            configErrorByAgent[agent.id] = "Config not loaded yet — try again in a moment."
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client(for: agent).updateConfig(
                    orgID: orgID, enabled: enabled, provider: nil, model: nil
                )
                self.configErrorByAgent[agent.id] = nil
                self.refreshPresence()
            } catch {
                self.configErrorByAgent[agent.id] = error.localizedDescription
            }
        }
    }

    private func shortReason(for error: DeployedAgentClient.ClientError) -> String {
        switch error {
        case .missingCredentials: return "No Keychain credentials"
        case .authFailed:         return "Sign-in refused"
        case .requestFailed:      return "Unreachable"
        }
    }

    // MARK: Dedicated chat

    func send(to agent: DeployedAgentConfig, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !thinkingAgents.contains(agent.id) else { return }

        conversationsByAgent[agent.id, default: []].append(DeployedChatMessage(role: .user, text: trimmed))
        thinkingAgents.insert(agent.id)
        save()

        Task { [weak self] in
            guard let self else { return }
            do {
                let reply = try await self.client(for: agent).run(
                    message: trimmed,
                    threadID: self.dedicatedThreadIDs[agent.id]
                )
                self.dedicatedThreadIDs[agent.id] = reply.threadID
                self.conversationsByAgent[agent.id, default: []].append(DeployedChatMessage(
                    role: .agent,
                    text: reply.text,
                    artifactTitle: reply.artifactTitle
                ))
            } catch {
                // Never fail silently — the miss is part of the transcript.
                self.conversationsByAgent[agent.id, default: []].append(DeployedChatMessage(
                    role: .notice,
                    text: "\(agent.name) could not be reached: \(error.localizedDescription)"
                ))
                self.refreshPresence()
            }
            self.thinkingAgents.remove(agent.id)
            self.save()
        }
    }

    /// Start the dedicated conversation over. The agent's side keeps the old
    /// thread in his own app (his memory is his); Thrawn just opens fresh.
    func clearConversation(for agent: DeployedAgentConfig) {
        conversationsByAgent[agent.id] = []
        dedicatedThreadIDs[agent.id] = nil
        save()
    }

    // MARK: @mentions from the main chat

    /// The deployed agent a message summons, if any. Word-boundary so "@ari"
    /// and "@ARI" hit but emails and "@arizona" don't. Aliases come from the
    /// registry, so a new agent's @token needs no code.
    func mentionedAgent(in text: String) -> DeployedAgentConfig? {
        agents.first { agent in
            text.range(
                of: "(^|[\\s\\n])@\(NSRegularExpression.escapedPattern(for: agent.mention))\\b",
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        }
    }

    /// Strip an agent's mention token so they read a clean request.
    func stripMention(of agent: DeployedAgentConfig, from text: String) -> String {
        text.replacingOccurrences(
            of: "(^|[\\s\\n])@\(NSRegularExpression.escapedPattern(for: agent.mention))\\b",
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Run one @mention turn on behalf of a Thrawn main-chat thread. Returns
    /// the reply text plus a model label for the thread's footer.
    func runMention(agent: DeployedAgentConfig, threadID: UUID, text: String) async throws -> (reply: String, modelLabel: String) {
        let message = stripMention(of: agent, from: text)
        let mapKey = "\(agent.id)|\(threadID.uuidString)"
        let reply = try await client(for: agent).run(message: message, threadID: mentionThreadMap[mapKey])
        mentionThreadMap[mapKey] = reply.threadID
        save()

        var replyText = reply.text
        if let artifactTitle = reply.artifactTitle {
            replyText += "\n\n📄 \(artifactTitle) — saved in \(agent.appName)."
        }
        let modelLabel: String
        if case .reachable(_, let model) = presence(for: agent) {
            modelLabel = "\(agent.name) @ \(agent.appName) · \(model)"
        } else {
            modelLabel = "\(agent.name) @ \(agent.appName)"
        }
        return (replyText, modelLabel)
    }

    // MARK: Persistence
    //
    // v2 is keyed by agent id. v1 (single-ARI) files migrate on first load so
    // nobody loses a conversation to the fleet refactor.

    private struct PersistedStateV2: Codable {
        var version: Int
        var dedicatedThreadIDs: [String: String]
        var mentionThreadMap: [String: String]
        var conversations: [String: [DeployedChatMessage]]
    }

    private struct PersistedStateV1: Codable {
        var dedicatedThreadID: String?
        var threadMap: [UUID: String]
        var conversation: [DeployedChatMessage]
    }

    private static let savePath = ThrawnPaths.appSupportDir
        .appendingPathComponent("thrawn-deployed-agents.json")

    private func load() {
        guard let data = try? Data(contentsOf: Self.savePath) else { return }
        if let v2 = try? JSONDecoder().decode(PersistedStateV2.self, from: data), v2.version == 2 {
            dedicatedThreadIDs = v2.dedicatedThreadIDs
            mentionThreadMap = v2.mentionThreadMap
            conversationsByAgent = v2.conversations
            return
        }
        if let v1 = try? JSONDecoder().decode(PersistedStateV1.self, from: data) {
            let ari = Self.ariAgentID
            if let thread = v1.dedicatedThreadID { dedicatedThreadIDs[ari] = thread }
            for (uuid, deployed) in v1.threadMap {
                mentionThreadMap["\(ari)|\(uuid.uuidString)"] = deployed
            }
            conversationsByAgent[ari] = v1.conversation
            save()
        }
    }

    private func save() {
        let state = PersistedStateV2(
            version: 2,
            dedicatedThreadIDs: dedicatedThreadIDs,
            mentionThreadMap: mentionThreadMap,
            conversations: conversationsByAgent
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(
            at: Self.savePath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: Self.savePath, options: .atomic)
    }
}
