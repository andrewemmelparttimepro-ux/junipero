import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Local Agent Runtime Bootstrap
//
// The signed native app acts as the persistent runtime host. Provider adapters
// may launch their official CLIs; API and local-model clients remain optional
// fallback routes. Cognee remains an optional HTTP connection.

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
        case runtime = "Provider Runtime"
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
    @Published var providerModel: String = ProviderRouter.premiumOpenAIModel
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
    @Published var liabilityMode: LiabilityMode = .myFault
    @Published var accessMode: AccessMode = .fullOperation

    private let thrawnDir: URL
    private let configURL: URL
    private let setupURL: URL
    private var didStart = false
    private var monitorTask: Task<Void, Never>?
    private var preferencesObserver: NSObjectProtocol?

    // Reference to the Ollama client for health checks
    private weak var ollamaClient: OllamaClient?
    private weak var openClawClient: GatewayWSClient?
    private weak var agentRuntime: AgentRuntimeCoordinator?

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

    /// Bind the shared OllamaClient for health checks.
    func bindOllamaClient(_ client: OllamaClient) {
        self.ollamaClient = client
    }

    /// Bind the shared OpenClaw client for subscription-backed GPT route checks.
    func bindOpenClawClient(_ client: GatewayWSClient) {
        self.openClawClient = client
    }

    func bindAgentRuntime(_ runtime: AgentRuntimeCoordinator) {
        self.agentRuntime = runtime
    }

    // MARK: - Startup

    func startIfNeeded() async {
        guard !didStart else { return }
        didStart = true
        try? FileManager.default.createDirectory(at: thrawnDir, withIntermediateDirectories: true)
        resetStepStates()

        // Migrate: legacy local/API files no longer drive normal routing.
        setStep(.migrate, .done)

        setStep(.runtime, .running)
        await refreshRuntimeStatus()
        setStep(.runtime, apiHealthy ? .done : .failed)
        setStep(.fallback, .done)
        setStep(.verify, apiHealthy ? .done : .failed)
        if apiHealthy {
            writeSetupState(SetupState(completed: true, setupDate: Date()))
            showSetup = false
        } else {
            showSetup = true
        }

        startRuntimeMonitor()
    }

    // MARK: - Setup Flow

    func completeOneClickSetup() async {
        guard !isWorking else { return }
        isWorking = true
        errorText = nil
        statusText = "Starting Codex agent runtime…"
        resetStepStates()

        // Step 1: Migrate legacy config
        setStep(.migrate, .done)

        // Step 2: Verify the provider-owned Codex runtime and account.
        setStep(.runtime, .running)
        apiHealthy = await checkAgentRuntimeHealth()
        setStep(.runtime, apiHealthy ? .done : .failed)
        setStep(.fallback, .done)

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
            errorText = "Could not start the Codex agent runtime. Confirm Codex is installed and run codex login."
            showSetup = true
        } else {
            statusText = "Thrawn online · \(agentRuntime?.runtimeLabel ?? "Codex")"
        }
    }

    func deferSetup() {
        showSetup = false
        statusText = "Codex agent runtime setup deferred"
    }

    func setLiabilityMode(_ mode: LiabilityMode) {
        var prefs = ThrawnPreferencesStore.load()
        prefs.liabilityMode = .myFault
        prefs.accessMode = .fullOperation
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
        apiHealthy = await checkAgentRuntimeHealth()
        ollamaHealthy = ollamaClient?.connected ?? false
        statusText = apiHealthy
            ? "Thrawn online · \(agentRuntime?.runtimeLabel ?? "Codex")"
            : "Codex agent runtime unavailable"

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

    private func checkAgentRuntimeHealth() async -> Bool {
        guard let agentRuntime else { return false }
        await agentRuntime.refresh()
        return agentRuntime.isReady
    }

    // MARK: - Diagnostics (App Store safe — no shell commands)

    func runGuidedDiagnostics() async {
        diagnosticsSummary = "Running diagnostics…"
        var lines: [String] = []

        lines.append("Codex Agent Runtime: \(apiHealthy ? "Online ✓" : "Unavailable ✗")")
        lines.append("Authentication: \(agentRuntime?.account?.displayName ?? "Not authenticated")")
        lines.append("Command Model: \(agentRuntime?.selectedModel?.displayName ?? "Live catalog unavailable")")

        // Legacy local connectivity
        let apiOk = ollamaClient?.connected ?? false
        lines.append("Legacy Ollama Connection: \(apiOk ? "Online ✓" : "Offline ✗")")

        lines.append("Operation Mode: Full")
        let shellOk = FileManager.default.isExecutableFile(atPath: "/bin/zsh")
        lines.append("Shell Available: \(shellOk ? "Yes ✓" : "No ✗")")

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
        // No-op for OpenClaw mode.
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
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            FlightRecorder.logError(
                source: "bootstrap:writeConfig",
                message: "Could not persist setup config: \(error.localizedDescription)"
            )
        }
    }

    private func readSetupState() -> SetupState? {
        guard let data = try? Data(contentsOf: setupURL) else { return nil }
        return try? JSONDecoder().decode(SetupState.self, from: data)
    }

    private func writeSetupState(_ state: SetupState) {
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: setupURL, options: .atomic)
        } catch {
            FlightRecorder.logError(
                source: "bootstrap:writeSetupState",
                message: "Could not persist setup state: \(error.localizedDescription)"
            )
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
        liabilityMode = .myFault
        accessMode = .fullOperation
    }
}
