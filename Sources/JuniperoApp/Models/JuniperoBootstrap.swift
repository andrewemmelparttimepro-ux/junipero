import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - App Store Compliant Bootstrap
//
// No ShellCommand, no Process(), no external dependencies.
// Setup = enter API key. Health = check API reachability.
// Cognee = optional HTTP connection (not required).

@MainActor
final class ThrawnBootstrap: ObservableObject {
    enum SetupMode: String, CaseIterable, Identifiable {
        case managed = "Managed"
        case bringYourOwn = "Custom API Key"

        var id: String { rawValue }
    }

    struct SetupState: Codable {
        var completed: Bool
        var setupDate: Date
    }

    enum SetupStep: String, CaseIterable, Identifiable {
        case migrate = "Migrate Config"
        case runtime = "Connect API"
        case fallback = "Agent System"
        case save = "Save Settings"
        case verify = "Verify Runtime"

        var id: String { rawValue }
    }

    enum StepState {
        case pending
        case running
        case done
        case failed
    }

    struct CogneeStatusSnapshot {
        var launchAgentLoaded: Bool = false
        var apiReachable: Bool = false
        var adapterReachable: Bool = false
        var datasetName: String = "ndai"
        var datasetID: String?
        var indexedFiles: Int = 0
        var workspaceFiles: Int = 0
        var newFiles: Int = 0
        var changedFiles: Int = 0
        var lastError: String?

        var pendingFiles: Int { newFiles + changedFiles }

        var isHealthy: Bool {
            apiReachable && adapterReachable
        }
    }

    // MARK: - Published Properties (UI-facing)

    @Published var setupMode: SetupMode = .bringYourOwn
    @Published var providerToken: String = ""
    @Published var providerModel: String = AnthropicConfig.defaultModel
    @Published var preferLocalFirst: Bool = false
    @Published var alwaysRouteNative: Bool = false
    @Published var unlockLocalOllamaOptions: Bool = false {
        didSet {
            guard !unlockLocalOllamaOptions else { return }
            enableOllamaFallback = false
            preferLocalFirst = false
            autoInstallKimi = false
        }
    }
    @Published var enableOllamaFallback: Bool = false {
        didSet {
            if enableOllamaFallback {
                unlockLocalOllamaOptions = true
            } else {
                preferLocalFirst = false
                autoInstallKimi = false
            }
        }
    }
    @Published var autoInstallKimi: Bool = false
    @Published var selectedOllamaModel: String = "qwen2.5-coder:7b"
    @Published var showSetup: Bool = false
    @Published var isWorking: Bool = false
    @Published var statusText: String = "Checking AI runtime…"
    @Published var errorText: String?
    @Published var apiHealthy: Bool = false
    @Published var ollamaHealthy: Bool = false
    @Published var cogneeHealthy: Bool = false
    @Published var cogneeStatusText: String = "Memory not connected"
    @Published var cogneeIndexedFiles: Int = 0
    @Published var cogneeWorkspaceFiles: Int = 0
    @Published var cogneePendingFiles: Int = 0
    @Published var diagnosticsSummary: String = "Diagnostics not run yet."
    @Published var missingOllamaModel: Bool = false
    @Published var lastSupportBundlePath: String?
    @Published private(set) var stepStates: [SetupStep: StepState] = [:]
    @Published var liabilityMode: LiabilityMode = .idiot
    @Published var probationInteractionCount: Int = 0
    @Published var probationStatusText: String = "Probation active"

    private let thrawnDir: URL
    private let configURL: URL
    private let setupURL: URL
    private var didStart = false
    private var monitorTask: Task<Void, Never>?
    private var preferencesObserver: NSObjectProtocol?

    // Reference to the native API client for health checks
    private weak var anthropicClient: AnthropicClient?

    var cogneeBadgeText: String {
        if cogneeHealthy {
            if cogneeWorkspaceFiles > 0 {
                return "Memory \(cogneeIndexedFiles)/\(cogneeWorkspaceFiles)"
            }
            return "Memory ready"
        }
        return cogneeStatusText
    }

    var ollamaFallbackActive: Bool {
        unlockLocalOllamaOptions && enableOllamaFallback
    }

    var canDisableGuardrails: Bool {
        ThrawnPreferencesStore.load().probationComplete
    }

    init() {
        self.thrawnDir = ThrawnPaths.appSupportDir
        self.configURL = thrawnDir.appendingPathComponent("config.json")
        self.setupURL = thrawnDir.appendingPathComponent("setup.json")
        self.stepStates = Dictionary(uniqueKeysWithValues: SetupStep.allCases.map { ($0, .pending) })
        syncPreferences()
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: ThrawnPreferencesStore.changedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncPreferences()
            }
        }
    }

    deinit {
        if let preferencesObserver {
            NotificationCenter.default.removeObserver(preferencesObserver)
        }
    }

    /// Bind the shared AnthropicClient for health checks.
    func bindAnthropicClient(_ client: AnthropicClient) {
        self.anthropicClient = client
    }

    // MARK: - Startup

    func startIfNeeded() async {
        guard !didStart else { return }
        didStart = true
        try? FileManager.default.createDirectory(at: thrawnDir, withIntermediateDirectories: true)
        resetStepStates()

        // Migrate: check for existing API key
        setStep(.migrate, .running)
        migrateConfigIfNeeded()
        setStep(.migrate, .done)

        if readSetupState()?.completed == true {
            // Already set up — verify API connectivity
            setStep(.runtime, .running)
            await refreshRuntimeStatus()
            setStep(.runtime, apiHealthy ? .done : .failed)
            setStep(.fallback, .done)
            setStep(.verify, apiHealthy ? .done : .failed)
            showSetup = false
        } else {
            // Check if API key exists from prior migration
            let config = AnthropicConfig.load()
            if config.isConfigured {
                // Key exists, auto-complete setup
                writeSetupState(SetupState(completed: true, setupDate: Date()))
                await refreshRuntimeStatus()
                showSetup = false
            } else {
                statusText = "Setup required — enter your API key"
                showSetup = true
            }
        }

        startRuntimeMonitor()
    }

    // MARK: - Setup Flow

    func completeOneClickSetup() async {
        guard !isWorking else { return }
        isWorking = true
        errorText = nil
        statusText = "Connecting to Anthropic API…"
        resetStepStates()

        // Step 1: Migrate
        setStep(.migrate, .running)
        migrateConfigIfNeeded()
        setStep(.migrate, .done)

        // Step 2: Save API key & verify connection
        setStep(.runtime, .running)

        // If user entered a provider token, save it as the Anthropic API key
        let trimmedToken = providerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty {
            anthropicClient?.setAPIKey(trimmedToken)
        }

        // Set model if specified
        let trimmedModel = providerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            let cleanModel = trimmedModel.replacingOccurrences(of: "anthropic/", with: "")
            anthropicClient?.setModel(cleanModel)
        }

        // Verify connectivity
        anthropicClient?.refreshNow()
        // Wait up to 6 seconds for connection check
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if anthropicClient?.connected == true { break }
        }

        apiHealthy = anthropicClient?.connected ?? false
        setStep(.runtime, apiHealthy ? .done : .failed)
        setStep(.fallback, .done) // No fallback needed with native API

        // Step 3: Save config
        setStep(.save, .running)
        writeThrawnConfig()
        writeSetupState(SetupState(completed: true, setupDate: Date()))
        setStep(.save, .done)

        // Step 4: Verify
        setStep(.verify, .running)
        await refreshRuntimeStatus()
        setStep(.verify, apiHealthy ? .done : .failed)

        showSetup = false
        isWorking = false

        if !apiHealthy {
            errorText = "Could not connect to Anthropic API. Check your API key."
        } else {
            statusText = "Thrawn online"
        }
    }

    func deferSetup() {
        showSetup = false
        statusText = "No API key — limited functionality"
    }

    func setLiabilityMode(_ mode: LiabilityMode) {
        var prefs = ThrawnPreferencesStore.load()
        if !prefs.probationComplete {
            prefs.liabilityMode = .idiot
        } else {
            prefs.liabilityMode = mode
        }
        ThrawnPreferencesStore.save(prefs)
    }

    // MARK: - Health Monitoring

    private func startRuntimeMonitor() {
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000)  // 25 seconds
                await self?.refreshRuntimeStatus()
            }
        }
    }

    func refreshRuntimeStatus() async {
        // Check Anthropic API health
        let apiConnected = anthropicClient?.connected ?? false
        apiHealthy = apiConnected

        if apiConnected {
            statusText = "Thrawn online"
        } else if anthropicClient?.apiKeyConfigured == true {
            statusText = "API unreachable — retrying"
        } else {
            statusText = "No API key configured"
        }

        // Check Cognee (optional — HTTP health check only)
        await refreshCogneeHealth()
    }

    // MARK: - Cognee (Optional Memory Server)

    private func refreshCogneeHealth() async {
        // Cognee is optional. Check if the user has a running Cognee instance.
        // We check two endpoints:
        // 1. Cognee API: http://127.0.0.1:8000/openapi.json
        // 2. Cognee adapter: http://127.0.0.1:18790/health

        let apiOk = await checkHTTPHealth(url: "http://127.0.0.1:8000/openapi.json", timeoutSeconds: 3)
        let adapterOk = await checkHTTPHealth(url: "http://127.0.0.1:18790/health", timeoutSeconds: 3)

        cogneeHealthy = apiOk && adapterOk

        if cogneeHealthy {
            cogneeStatusText = "Memory connected"
            // Try to get status from Cognee API
            await refreshCogneeIndexStatus()
        } else if apiOk {
            cogneeStatusText = "Memory API online, adapter offline"
        } else {
            cogneeStatusText = "Memory not connected"
            cogneeIndexedFiles = 0
            cogneeWorkspaceFiles = 0
            cogneePendingFiles = 0
        }
    }

    private func refreshCogneeIndexStatus() async {
        // Try to query Cognee's dataset status
        guard let url = URL(string: "http://127.0.0.1:8000/api/v1/datasets") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            // Parse minimal dataset info
            if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = json.first {
                cogneeIndexedFiles = (first["indexed_files"] as? Int) ?? 0
                cogneeWorkspaceFiles = (first["total_files"] as? Int) ?? 0
                cogneePendingFiles = max(0, cogneeWorkspaceFiles - cogneeIndexedFiles)
            }
        } catch {
            // Silently fail — Cognee is optional
        }
    }

    private func checkHTTPHealth(url urlString: String, timeoutSeconds: TimeInterval) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutSeconds
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode >= 200 && http.statusCode < 400
        } catch {
            return false
        }
    }

    // MARK: - Diagnostics (App Store safe — no shell commands)

    func runGuidedDiagnostics() async {
        diagnosticsSummary = "Running diagnostics…"
        var lines: [String] = []

        // API key
        let config = AnthropicConfig.load()
        lines.append("API Key: \(config.isConfigured ? "Configured ✓" : "MISSING ✗")")
        lines.append("Model: \(config.model)")

        // API connectivity
        let apiOk = anthropicClient?.connected ?? false
        lines.append("API Connection: \(apiOk ? "Online ✓" : "Offline ✗")")

        // Cognee
        lines.append("Cognee API: \(cogneeHealthy ? "Connected ✓" : "Not connected")")

        // Agent scheduler
        lines.append("Agent Scheduler: Active")

        diagnosticsSummary = lines.joined(separator: "\n")
    }

    func runFullHealthTest() async {
        await runGuidedDiagnostics()
    }

    func installMissingFallbackModel() async {
        // No-op in App Store mode (no Ollama)
        diagnosticsSummary = "Local models are not available in this version."
    }

    func reindexCogneeMemory() async {
        guard cogneeHealthy else {
            diagnosticsSummary = "Cognee is not connected. Start Cognee externally to use memory."
            return
        }
        // Trigger reindex via HTTP
        guard let url = URL(string: "http://127.0.0.1:8000/api/v1/index") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 200, http.statusCode < 300 {
                diagnosticsSummary = "Cognee reindex triggered successfully."
            } else {
                diagnosticsSummary = "Cognee reindex request failed."
            }
        } catch {
            diagnosticsSummary = "Could not reach Cognee for reindex."
        }
    }

    func exportSupportBundle() async {
        // Collect diagnostic info as a text file (no shell commands)
        await runGuidedDiagnostics()
        let content = """
        Thrawn Support Bundle
        Generated: \(ISO8601DateFormatter().string(from: Date()))

        \(diagnosticsSummary)

        App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
        Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")
        """
        let tempDir = FileManager.default.temporaryDirectory
        let bundlePath = tempDir.appendingPathComponent("thrawn-support-\(Int(Date().timeIntervalSince1970)).txt")
        try? content.write(to: bundlePath, atomically: true, encoding: .utf8)
        lastSupportBundlePath = bundlePath.path
    }

    // MARK: - Config Persistence

    private func migrateConfigIfNeeded() {
        // Check for old OpenClaw token and migrate to Anthropic keychain
        let home = FileManager.default.homeDirectoryForCurrentUser
        let authPath = home.appendingPathComponent(".openclaw/auth.json")
        guard let data = try? Data(contentsOf: authPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = json["profiles"] as? [String: [String: Any]] else { return }

        for (_, profile) in profiles {
            if let token = profile["token"] as? String, !token.isEmpty {
                // Check if we already have an API key
                let existing = KeychainHelper.read(service: "com.thrawn.anthropic", account: "api-key")
                if existing == nil || existing?.isEmpty == true {
                    // Looks like an Anthropic key?
                    if token.hasPrefix("sk-ant-") {
                        KeychainHelper.save(service: "com.thrawn.anthropic", account: "api-key", value: token)
                        anthropicClient?.reloadConfig()
                    }
                }
                break
            }
        }
    }

    private struct ThrawnConfig: Codable {
        var model: String
        var cogneeEnabled: Bool
        var setupDate: Date
    }

    private func writeThrawnConfig() {
        let config = ThrawnConfig(
            model: providerModel,
            cogneeEnabled: cogneeHealthy,
            setupDate: Date()
        )
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configURL, options: .atomic)
        }
    }

    private func readSetupState() -> SetupState? {
        guard let data = try? Data(contentsOf: setupURL) else { return nil }
        return try? JSONDecoder().decode(SetupState.self, from: data)
    }

    private func writeSetupState(_ state: SetupState) {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: setupURL, options: .atomic)
        }
    }

    // MARK: - Step State Helpers

    func stateForStep(_ step: SetupStep) -> StepState {
        stepStates[step] ?? .pending
    }

    private func resetStepStates() {
        stepStates = Dictionary(uniqueKeysWithValues: SetupStep.allCases.map { ($0, .pending) })
    }

    private func setStep(_ step: SetupStep, _ state: StepState) {
        stepStates[step] = state
    }

    // MARK: - Preferences Sync

    private func syncPreferences() {
        let prefs = ThrawnPreferencesStore.load()
        liabilityMode = prefs.effectiveLiabilityMode
        probationInteractionCount = prefs.interactionCount
        if prefs.probationComplete {
            probationStatusText = "Probation complete. Advanced mode unlocked."
        } else {
            let remainingInteractions = max(0, 8 - prefs.interactionCount)
            let remainingSeconds = max(0, Int(21_600 - Date().timeIntervalSince(prefs.probationStartedAt)))
            let remainingHours = max(0, (remainingSeconds + 3599) / 3600)
            probationStatusText = "Probation: \(remainingInteractions) more chats or ~\(remainingHours)h of use."
        }
    }
}
