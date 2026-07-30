import AppKit
import Foundation
import SwiftUI

// MARK: - Provider-neutral agent runtime contract

enum AgentProviderConnectionState: String, Codable {
    case unavailable
    case starting
    case authenticationRequired
    case ready
    case failed
}

struct ProviderAccount: Equatable {
    let authenticationMode: String
    let email: String?
    let planType: String?

    var displayName: String {
        switch authenticationMode {
        case "chatgpt":
            if let planType, !planType.isEmpty {
                return "ChatGPT \(planType.replacingOccurrences(of: "_", with: " ").capitalized)"
            }
            return "ChatGPT"
        case "apiKey":
            return "OpenAI API key"
        case "grok":
            return "Grok"
        case "claude":
            if let planType, !planType.isEmpty {
                return "Claude \(planType.capitalized)"
            }
            return "Claude"
        default:
            return authenticationMode
        }
    }
}

struct ProviderStatus: Equatable {
    let providerID: String
    let state: AgentProviderConnectionState
    let executablePath: String?
    let version: String?
    let account: ProviderAccount?
    let detail: String

    static func unavailable(providerID: String, detail: String) -> ProviderStatus {
        ProviderStatus(
            providerID: providerID,
            state: .unavailable,
            executablePath: nil,
            version: nil,
            account: nil,
            detail: detail
        )
    }
}

struct AuthInstructions: Equatable {
    let providerID: String
    let title: String
    let command: String
    let detail: String
}

struct ModelDescriptor: Identifiable, Equatable {
    struct ReasoningOption: Identifiable, Equatable {
        let reasoningEffort: String
        let description: String
        var id: String { reasoningEffort }
    }

    struct ServiceTier: Identifiable, Equatable {
        let id: String
        let name: String
        let description: String
    }

    let id: String
    let model: String
    let displayName: String
    let description: String
    let isDefault: Bool
    let hidden: Bool
    let defaultReasoningEffort: String
    let supportedReasoningEfforts: [ReasoningOption]
    let serviceTiers: [ServiceTier]
    let defaultServiceTier: String?
    let inputModalities: [String]
}

enum AgentRuntimeApprovalPolicy: String, Codable {
    case untrusted
    case onRequest = "on-request"
    case never
}

enum AgentRuntimeSandbox: String, Codable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case fullOperation = "danger-full-access"
}

struct AgentSessionOptions {
    let sessionKey: String
    let agentID: String
    let provider: ProviderBackend
    let cwd: URL
    let developerInstructions: String?
    let model: String?
    let reasoningEffort: String?
    let serviceTier: String?
    let approvalPolicy: AgentRuntimeApprovalPolicy
    let sandbox: AgentRuntimeSandbox

    init(
        sessionKey: String,
        agentID: String,
        provider: ProviderBackend = .codex,
        cwd: URL = ThrawnPaths.appSupportDir.appendingPathComponent("workspace"),
        developerInstructions: String? = nil,
        model: String? = nil,
        reasoningEffort: String? = nil,
        serviceTier: String? = nil,
        approvalPolicy: AgentRuntimeApprovalPolicy = .onRequest,
        sandbox: AgentRuntimeSandbox = .fullOperation
    ) {
        self.sessionKey = sessionKey
        self.agentID = agentID
        self.provider = provider
        self.cwd = cwd
        self.developerInstructions = developerInstructions
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.serviceTier = serviceTier
        self.approvalPolicy = approvalPolicy
        self.sandbox = sandbox
    }
}

struct AgentSessionDescriptor: Equatable {
    let providerID: String
    let sessionKey: String
    let providerSessionID: String
    let model: String
}

struct AgentToolCall: Equatable {
    let id: String
    let kind: String
    let title: String
    let detail: String?
    let status: String
}

struct AgentFileChange: Equatable {
    let id: String
    let paths: [String]
    let status: String
    let diff: String?
}

struct AgentUsageSnapshot: Equatable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
}

enum AgentApprovalKind: String, Codable {
    case command
    case fileChange
    case permissions
    case userInput
    case unknown
}

struct AgentApprovalRequest: Identifiable, Equatable {
    let id: String
    let providerID: String
    let kind: AgentApprovalKind
    let threadID: String
    let turnID: String?
    let itemID: String?
    let title: String
    let detail: String
    let cwd: String?
    let availableDecisions: [String]
    let createdAt: Date
}

enum AgentApprovalDecision: String {
    case accept
    case acceptForSession
    case decline
    case cancel
}

enum AgentEvent {
    case textDelta(String)
    case reasoningDelta(String)
    case toolCall(AgentToolCall)
    case fileChange(AgentFileChange)
    case approvalRequired(AgentApprovalRequest)
    case usage(AgentUsageSnapshot)
    case completed
    case error(String)
}

struct AgentRunResult {
    let text: String
    let model: String
    let providerSessionID: String
    let turnID: String?
}

enum AgentRuntimeError: LocalizedError {
    case executableNotFound(String)
    case processLaunchFailed(String)
    case processExited(String)
    case malformedResponse(String)
    case requestFailed(String)
    case requestTimedOut(String)
    case authenticationRequired(String)
    case sessionUnavailable(String)
    case turnFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let detail),
             .processLaunchFailed(let detail),
             .processExited(let detail),
             .malformedResponse(let detail),
             .requestFailed(let detail),
             .requestTimedOut(let detail),
             .authenticationRequired(let detail),
             .sessionUnavailable(let detail),
             .turnFailed(let detail):
            return detail
        }
    }
}

@MainActor
protocol AgentProvider: AnyObject {
    var id: String { get }
    func probe() async -> ProviderStatus
    func authenticate() async -> AuthInstructions
    func listModels() async throws -> [ModelDescriptor]
    func createSession(options: AgentSessionOptions) async throws -> AgentSessionDescriptor
    func resumeSession(
        providerSessionID: String,
        options: AgentSessionOptions
    ) async throws -> AgentSessionDescriptor
    func runTurn(
        session: AgentSessionDescriptor,
        prompt: String,
        options: AgentSessionOptions,
        onEvent: @escaping @MainActor (AgentEvent) -> Void
    ) async throws -> AgentRunResult
    func cancelSession(providerSessionID: String) async
    func resolveApproval(id: String, decision: AgentApprovalDecision) throws
}

// MARK: - Thrawn runtime orchestration

@MainActor
final class AgentRuntimeCoordinator: ObservableObject {
    @Published private(set) var codexStatus = ProviderStatus.unavailable(
        providerID: "codex",
        detail: "Codex runtime has not been checked."
    )
    @Published private(set) var codexModels: [ModelDescriptor] = []
    @Published private(set) var grokStatus = ProviderStatus.unavailable(
        providerID: "grok",
        detail: "Grok runtime has not been checked."
    )
    @Published private(set) var grokModels: [ModelDescriptor] = []
    @Published var selectedCodexModelID: String? {
        didSet {
            UserDefaults.standard.set(
                selectedCodexModelID,
                forKey: "thrawn.agentRuntime.codex.model"
            )
        }
    }
    @Published var selectedReasoningEffort: String? {
        didSet {
            UserDefaults.standard.set(
                selectedReasoningEffort,
                forKey: "thrawn.agentRuntime.codex.reasoning"
            )
        }
    }
    @Published private(set) var pendingApprovals: [AgentApprovalRequest] = []
    @Published private(set) var lastError: String?

    @Published private var statusesByProfile: [String: ProviderStatus] = [:]
    @Published private var modelsByProfile: [String: [ModelDescriptor]] = [:]

    private let profileStore: AgentProviderProfileStore
    private var codexProviders: [String: CodexAppServerProvider] = [:]
    private var grokProviders: [String: GrokCLIProvider] = [:]
    private var claudeProviders: [String: ClaudeCLIProvider] = [:]
    private let sessionStore = AgentRuntimeSessionStore()
    private var didStart = false

    init(profileStore: AgentProviderProfileStore = AgentProviderProfileStore()) {
        self.profileStore = profileStore
        self.selectedCodexModelID = UserDefaults.standard.string(
            forKey: "thrawn.agentRuntime.codex.model"
        )
        self.selectedReasoningEffort = UserDefaults.standard.string(
            forKey: "thrawn.agentRuntime.codex.reasoning"
        )
        for agentID in StableGatewayPolicy.stableAgentIDs {
            _ = codexProvider(for: agentID)
            _ = grokProvider(for: agentID)
            _ = claudeProvider(for: agentID)
        }
    }

    var isReady: Bool {
        codexStatus.state == .ready
    }

    var account: ProviderAccount? {
        codexStatus.account
    }

    func status(for backend: ProviderBackend) -> ProviderStatus {
        let representativeAgent = backend == .grok ? "steven" : "thrawn"
        return status(for: backend, agentID: representativeAgent)
    }

    func status(for backend: ProviderBackend, agentID: String) -> ProviderStatus {
        if let status = statusesByProfile[profileKey(agentID: agentID, backend: backend)] {
            return status
        }
        switch backend {
        case .codex:
            return .unavailable(
                providerID: "codex:\(agentID)",
                detail: "This agent's OpenAI account profile has not been checked."
            )
        case .grok:
            return .unavailable(
                providerID: "grok:\(agentID)",
                detail: "This agent's Grok account profile has not been checked."
            )
        case .claude:
            return .unavailable(
                providerID: "claude:\(agentID)",
                detail: "This agent's Claude account profile has not been checked."
            )
        case .ollama, .openai, .openclaw, .xai:
            return .unavailable(
                providerID: "\(backend.rawValue):\(agentID)",
                detail: "\(backend.gatewayDisplayName) is not a subscription-agent runtime."
            )
        }
    }

    func isReady(_ backend: ProviderBackend) -> Bool {
        status(for: backend).state == .ready
    }

    func isReady(_ backend: ProviderBackend, agentID: String) -> Bool {
        status(for: backend, agentID: agentID).state == .ready
    }

    var selectedModel: ModelDescriptor? {
        if let selectedCodexModelID,
           let selected = codexModels.first(where: { $0.id == selectedCodexModelID || $0.model == selectedCodexModelID }) {
            return selected
        }
        return codexModels.first(where: \.isDefault) ?? codexModels.first
    }

    var runtimeLabel: String {
        guard let model = selectedModel else { return "Codex CLI" }
        return "Codex · \(model.displayName)"
    }

    func start() async {
        if didStart, isReady { return }
        didStart = true
        profileStore.prepareStableProfiles()
        await refresh()
    }

    func refresh() async {
        for agentID in StableGatewayPolicy.stableAgentIDs {
            let backend: ProviderBackend = agentID == "steven" ? .grok : .codex
            await refresh(agentID: agentID, backend: backend)
        }
        await refresh(agentID: "thrawn", backend: .claude)
    }

    func refresh(agentID: String, backend: ProviderBackend) async {
        guard backend.isSubscriptionGateway else { return }
        profileStore.prepareProfile(agentID: agentID, backend: backend)
        let oldStatus = status(for: backend, agentID: agentID)
        setStatus(
            ProviderStatus(
                providerID: "\(backend.rawValue):\(agentID)",
                state: .starting,
                executablePath: oldStatus.executablePath,
                version: oldStatus.version,
                account: oldStatus.account,
                detail: {
                    switch backend {
                    case .codex: return "Checking this agent's OpenAI account…"
                    case .grok: return "Checking this agent's Grok account…"
                    case .claude: return "Checking this agent's Claude account…"
                    case .ollama, .openai, .openclaw, .xai:
                        return "Checking this agent's provider account…"
                    }
                }()
            ),
            agentID: agentID,
            backend: backend
        )

        let provider = provider(for: backend, agentID: agentID)
        let probe = await provider.probe()
        setStatus(probe, agentID: agentID, backend: backend)

        guard probe.state == .ready else {
            setModels([], agentID: agentID, backend: backend)
            if agentID == "thrawn" && backend == .codex {
                lastError = probe.detail
            }
            return
        }

        do {
            let models = try await provider.listModels()
            setModels(models, agentID: agentID, backend: backend)
            if backend == .codex,
               selectedCodexModelID == nil || !models.contains(where: {
                   $0.id == selectedCodexModelID || $0.model == selectedCodexModelID
               }) {
                selectedCodexModelID = models.first(where: \.isDefault)?.id ?? models.first?.id
            }
            if backend == .codex, selectedReasoningEffort == nil {
                selectedReasoningEffort = selectedModel(for: agentID)?.defaultReasoningEffort
            }
            lastError = nil
        } catch {
            setModels([], agentID: agentID, backend: backend)
            lastError = error.localizedDescription
        }
    }

    func authInstructions() async -> AuthInstructions {
        await codexProvider(for: "thrawn").authenticate()
    }

    func beginSignIn(agentID: String, backend: ProviderBackend) async throws {
        guard backend.isSubscriptionGateway else {
            throw AgentRuntimeError.authenticationRequired(
                "\(backend.gatewayDisplayName) does not expose a subscription sign-in."
            )
        }
        profileStore.prepareProfile(agentID: agentID, backend: backend)
        let oldStatus = status(for: backend, agentID: agentID)
        setStatus(
            ProviderStatus(
                providerID: "\(backend.rawValue):\(agentID)",
                state: .starting,
                executablePath: oldStatus.executablePath,
                version: oldStatus.version,
                account: nil,
                detail: "Opening provider sign-in in your browser…"
            ),
            agentID: agentID,
            backend: backend
        )
        do {
            switch backend {
            case .codex:
                let url = try await codexProvider(for: agentID).beginBrowserLogin()
                guard NSWorkspace.shared.open(url) else {
                    throw AgentRuntimeError.processLaunchFailed(
                        "Could not open the ChatGPT sign-in page."
                    )
                }
            case .grok:
                try grokProvider(for: agentID).beginBrowserLogin()
            case .claude:
                try claudeProvider(for: agentID).beginBrowserLogin()
            case .ollama, .openai, .openclaw, .xai:
                break
            }
        } catch {
            lastError = error.localizedDescription
            await refresh(agentID: agentID, backend: backend)
            throw error
        }
    }

    func signOut(agentID: String, backend: ProviderBackend) async throws {
        switch backend {
        case .codex:
            try await codexProvider(for: agentID).logout()
        case .grok:
            try await grokProvider(for: agentID).logout()
        case .claude:
            try await claudeProvider(for: agentID).logout()
        case .ollama, .openai, .openclaw, .xai:
            throw AgentRuntimeError.requestFailed(
                "\(backend.gatewayDisplayName) does not expose a subscription sign-out."
            )
        }
        await refresh(agentID: agentID, backend: backend)
    }

    func run(
        prompt: String,
        options requestedOptions: AgentSessionOptions,
        onEvent: @escaping @MainActor (AgentEvent) -> Void = { _ in }
    ) async throws -> AgentRunResult {
        let provider = provider(
            for: requestedOptions.provider,
            agentID: requestedOptions.agentID
        )
        if status(
            for: requestedOptions.provider,
            agentID: requestedOptions.agentID
        ).state != .ready {
            await refresh(
                agentID: requestedOptions.agentID,
                backend: requestedOptions.provider
            )
        }
        let providerStatus = status(
            for: requestedOptions.provider,
            agentID: requestedOptions.agentID
        )
        guard providerStatus.state == .ready else {
            throw AgentRuntimeError.authenticationRequired(providerStatus.detail)
        }

        let chosenModel = normalizedModel(
            requestedOptions.model,
            backend: requestedOptions.provider,
            agentID: requestedOptions.agentID
        )
        let chosenEffort = normalizedEffort(
            requestedOptions.reasoningEffort,
            model: chosenModel,
            backend: requestedOptions.provider,
            agentID: requestedOptions.agentID
        )
        let options = AgentSessionOptions(
            sessionKey: requestedOptions.sessionKey,
            agentID: requestedOptions.agentID,
            provider: requestedOptions.provider,
            cwd: requestedOptions.cwd,
            developerInstructions: requestedOptions.developerInstructions,
            model: chosenModel,
            reasoningEffort: chosenEffort,
            serviceTier: requestedOptions.serviceTier
                ?? selectedModel(for: requestedOptions.agentID)?.defaultServiceTier,
            approvalPolicy: requestedOptions.approvalPolicy,
            sandbox: requestedOptions.sandbox
        )

        let session: AgentSessionDescriptor
        if let record = sessionStore.record(providerID: provider.id, sessionKey: options.sessionKey) {
            do {
                session = try await provider.resumeSession(
                    providerSessionID: record.providerSessionID,
                    options: options
                )
            } catch {
                sessionStore.remove(providerID: provider.id, sessionKey: options.sessionKey)
                session = try await provider.createSession(options: options)
            }
        } else {
            session = try await provider.createSession(options: options)
        }

        sessionStore.set(
            providerID: provider.id,
            sessionKey: options.sessionKey,
            providerSessionID: session.providerSessionID,
            model: session.model
        )
        do {
            let result = try await provider.runTurn(
                session: session,
                prompt: prompt,
                options: options,
                onEvent: onEvent
            )
            sessionStore.set(
                providerID: provider.id,
                sessionKey: options.sessionKey,
                providerSessionID: result.providerSessionID,
                model: result.model
            )
            return result
        } catch {
            if requestedOptions.provider == .grok
                || requestedOptions.provider == .claude {
                sessionStore.remove(
                    providerID: provider.id,
                    sessionKey: options.sessionKey
                )
            }
            lastError = error.localizedDescription
            throw error
        }
    }

    func cancel(sessionKey: String) async {
        let providers: [any AgentProvider] = codexProviders.values.map { $0 as any AgentProvider }
            + grokProviders.values.map { $0 as any AgentProvider }
            + claudeProviders.values.map { $0 as any AgentProvider }
        for provider in providers {
            guard let record = sessionStore.record(
                providerID: provider.id,
                sessionKey: sessionKey
            ) else { continue }
            await provider.cancelSession(providerSessionID: record.providerSessionID)
        }
    }

    func resolveApproval(_ approval: AgentApprovalRequest, decision: AgentApprovalDecision) {
        do {
            guard let provider = codexProviders.values.first(where: {
                $0.id == approval.providerID
            }) else {
                throw AgentRuntimeError.requestFailed(
                    "The agent account that requested this approval is no longer active."
                )
            }
            try provider.resolveApproval(id: approval.id, decision: decision)
            pendingApprovals.removeAll(where: { $0.id == approval.id })
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func provider(
        for backend: ProviderBackend,
        agentID: String
    ) -> any AgentProvider {
        switch backend {
        case .codex:
            return codexProvider(for: agentID)
        case .grok:
            return grokProvider(for: agentID)
        case .claude:
            return claudeProvider(for: agentID)
        case .ollama, .openai, .openclaw, .xai:
            return codexProvider(for: agentID)
        }
    }

    private func normalizedModel(
        _ requested: String?,
        backend: ProviderBackend,
        agentID: String
    ) -> String? {
        let trimmed = requested?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty, trimmed != "auto" {
            return trimmed
        }
        switch backend {
        case .grok:
            let models = models(for: backend, agentID: agentID)
            return models.first(where: \.isDefault)?.model
                ?? models.first?.model
                ?? ProviderRouter.dynamicGrokModel
        case .claude:
            let models = models(for: backend, agentID: agentID)
            return models.first(where: \.isDefault)?.model
                ?? models.first?.model
                ?? ProviderRouter.dynamicClaudeModel
        case .codex:
            return selectedModel(for: agentID)?.model
        case .ollama, .openai, .openclaw, .xai:
            return trimmed
        }
    }

    private func normalizedEffort(
        _ requested: String?,
        model: String?,
        backend: ProviderBackend,
        agentID: String
    ) -> String? {
        if let requested, !requested.isEmpty, requested != "auto" {
            return requested
        }
        if backend == .grok || backend == .claude {
            return models(for: backend, agentID: agentID)
                .first(where: { $0.model == model || $0.id == model })?
                .defaultReasoningEffort
        }
        if let model,
           let descriptor = models(for: backend, agentID: agentID)
                .first(where: { $0.model == model || $0.id == model }) {
            if descriptor.supportedReasoningEfforts.contains(where: {
                $0.reasoningEffort == selectedReasoningEffort
            }) {
                return selectedReasoningEffort
            }
            return descriptor.defaultReasoningEffort
        }
        return selectedReasoningEffort
    }

    private func selectedModel(for agentID: String) -> ModelDescriptor? {
        let models = models(for: .codex, agentID: agentID)
        if let selectedCodexModelID,
           let selected = models.first(where: {
               $0.id == selectedCodexModelID || $0.model == selectedCodexModelID
           }) {
            return selected
        }
        return models.first(where: \.isDefault) ?? models.first
    }

    private func models(
        for backend: ProviderBackend,
        agentID: String
    ) -> [ModelDescriptor] {
        modelsByProfile[profileKey(agentID: agentID, backend: backend)] ?? []
    }

    private func setModels(
        _ models: [ModelDescriptor],
        agentID: String,
        backend: ProviderBackend
    ) {
        modelsByProfile[profileKey(agentID: agentID, backend: backend)] = models
        if backend == .codex, agentID == "thrawn" {
            codexModels = models
        }
        if backend == .grok, agentID == "steven" {
            grokModels = models
        }
    }

    private func setStatus(
        _ status: ProviderStatus,
        agentID: String,
        backend: ProviderBackend
    ) {
        statusesByProfile[profileKey(agentID: agentID, backend: backend)] = status
        if backend == .codex, agentID == "thrawn" {
            codexStatus = status
        }
        if backend == .grok, agentID == "steven" {
            grokStatus = status
        }
    }

    private func profileKey(agentID: String, backend: ProviderBackend) -> String {
        "\(agentID.lowercased())|\(backend.rawValue)"
    }

    private func codexProvider(for agentID: String) -> CodexAppServerProvider {
        if let provider = codexProviders[agentID] { return provider }
        let provider = CodexAppServerProvider(
            profileID: agentID,
            stateDirectory: profileStore.profileDirectory(
                agentID: agentID,
                backend: .codex
            )
        )
        provider.approvalHandler = { [weak self] approval in
            guard let self else { return }
            if !self.pendingApprovals.contains(where: { $0.id == approval.id }) {
                self.pendingApprovals.append(approval)
            }
        }
        provider.approvalResolvedHandler = { [weak self] approvalID in
            self?.pendingApprovals.removeAll(where: { $0.id == approvalID })
        }
        provider.accountUpdatedHandler = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh(agentID: agentID, backend: .codex)
            }
        }
        codexProviders[agentID] = provider
        return provider
    }

    private func grokProvider(for agentID: String) -> GrokCLIProvider {
        if let provider = grokProviders[agentID] { return provider }
        let provider = GrokCLIProvider(
            profileID: agentID,
            stateDirectory: profileStore.profileDirectory(
                agentID: agentID,
                backend: .grok
            )
        )
        provider.accountUpdatedHandler = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh(agentID: agentID, backend: .grok)
            }
        }
        grokProviders[agentID] = provider
        return provider
    }

    private func claudeProvider(for agentID: String) -> ClaudeCLIProvider {
        if let provider = claudeProviders[agentID] { return provider }
        let provider = ClaudeCLIProvider(
            profileID: agentID,
            stateDirectory: profileStore.profileDirectory(
                agentID: agentID,
                backend: .claude
            )
        )
        provider.accountUpdatedHandler = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh(agentID: agentID, backend: .claude)
            }
        }
        claudeProviders[agentID] = provider
        return provider
    }
}

// MARK: - Session metadata (never credentials)

private struct AgentRuntimeSessionRecord: Codable {
    let providerID: String
    let sessionKey: String
    let providerSessionID: String
    let model: String
    let updatedAt: Date
}

private final class AgentRuntimeSessionStore {
    private let fileURL = ThrawnPaths.appSupportDir
        .appendingPathComponent("agent-runtime-sessions.json")
    private var records: [AgentRuntimeSessionRecord] = []

    init() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([AgentRuntimeSessionRecord].self, from: data) else {
            return
        }
        records = decoded
    }

    func record(providerID: String, sessionKey: String) -> AgentRuntimeSessionRecord? {
        records.first(where: {
            $0.providerID == providerID && $0.sessionKey == sessionKey
        })
    }

    func set(
        providerID: String,
        sessionKey: String,
        providerSessionID: String,
        model: String
    ) {
        records.removeAll(where: {
            $0.providerID == providerID && $0.sessionKey == sessionKey
        })
        records.append(
            AgentRuntimeSessionRecord(
                providerID: providerID,
                sessionKey: sessionKey,
                providerSessionID: providerSessionID,
                model: model,
                updatedAt: Date()
            )
        )
        save()
    }

    func remove(providerID: String, sessionKey: String) {
        records.removeAll(where: {
            $0.providerID == providerID && $0.sessionKey == sessionKey
        })
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(records)
            try data.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            FlightRecorder.logError(
                source: "agent-runtime:sessions",
                message: "Could not persist session metadata: \(error.localizedDescription)"
            )
        }
    }
}
