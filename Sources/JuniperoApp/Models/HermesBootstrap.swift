import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

@MainActor
final class HermesBootstrap: ObservableObject {

    enum SetupStep: String, CaseIterable, Identifiable {
        case checkInstall = "Check Hermes Install"
        case installHermes = "Install Hermes Agent"
        case startGateway = "Start Gateway"
        case verify = "Verify Connection"

        var id: String { rawValue }
    }

    enum StepState {
        case pending, running, done, failed
    }

    @Published var showSetup: Bool = false
    @Published var isWorking: Bool = false
    @Published var statusText: String = "Checking Hermes Agent..."
    @Published var errorText: String?
    @Published var hermesHealthy: Bool = false
    @Published var hermesInstalled: Bool = false
    @Published var ollamaHealthy: Bool = false
    @Published var diagnosticsSummary: String = "Not checked yet."
    @Published private(set) var stepStates: [SetupStep: StepState] = [:]
    @Published var liabilityMode: LiabilityMode = .idiot

    // Provider config
    @Published var providerModel: String = "hermes-agent"
    @Published var enableOllamaFallback: Bool = true

    private let hermesHome: URL
    private let juniperoDir: URL
    private let configURL: URL
    private let setupURL: URL
    private var didStart = false
    private var monitorTask: Task<Void, Never>?
    private var preferencesObserver: NSObjectProtocol?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.hermesHome = home.appendingPathComponent(".hermes", isDirectory: true)
        self.juniperoDir = home.appendingPathComponent(".junipero", isDirectory: true)
        self.configURL = juniperoDir.appendingPathComponent("config.json")
        self.setupURL = juniperoDir.appendingPathComponent("setup.json")
        self.stepStates = Dictionary(uniqueKeysWithValues: SetupStep.allCases.map { ($0, .pending) })
        syncPreferences()
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: JuniperoPreferencesStore.changedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.syncPreferences() }
        }
    }

    deinit {
        if let preferencesObserver {
            NotificationCenter.default.removeObserver(preferencesObserver)
        }
    }

    // MARK: - Lifecycle

    func startIfNeeded() async {
        guard !didStart else { return }
        didStart = true
        try? FileManager.default.createDirectory(at: juniperoDir, withIntermediateDirectories: true)
        resetStepStates()

        // Step 1: Check if Hermes is installed
        setStep(.checkInstall, .running)
        hermesInstalled = checkHermesInstalled()
        setStep(.checkInstall, hermesInstalled ? .done : .failed)

        if !hermesInstalled {
            statusText = "Hermes Agent not found"
            showSetup = true
            return
        }

        // Step 2: Skip install (already present)
        setStep(.installHermes, .done)

        // Step 3: Start gateway
        setStep(.startGateway, .running)
        await ensureGatewayRunning()
        setStep(.startGateway, hermesHealthy ? .done : .failed)

        // Step 4: Verify
        setStep(.verify, .running)
        await refreshStatus()
        setStep(.verify, hermesHealthy ? .done : .failed)

        if hermesHealthy {
            showSetup = false
            writeDefaultConfigIfNeeded()
        } else {
            showSetup = true
        }

        startMonitor()
    }

    // MARK: - One-Click Setup

    func completeSetup() async {
        guard !isWorking else { return }
        isWorking = true
        errorText = nil
        resetStepStates()

        // Check install
        setStep(.checkInstall, .running)
        hermesInstalled = checkHermesInstalled()
        setStep(.checkInstall, hermesInstalled ? .done : .failed)

        // Install if needed
        if !hermesInstalled {
            setStep(.installHermes, .running)
            statusText = "Installing Hermes Agent..."
            await installHermes()
            hermesInstalled = checkHermesInstalled()
            setStep(.installHermes, hermesInstalled ? .done : .failed)
            if !hermesInstalled {
                errorText = "Hermes Agent installation failed. Check your network and try again."
                statusText = "Installation failed"
                isWorking = false
                return
            }
        } else {
            setStep(.installHermes, .done)
        }

        // Start gateway
        setStep(.startGateway, .running)
        statusText = "Starting Hermes gateway..."
        await ensureGatewayRunning()
        setStep(.startGateway, hermesHealthy ? .done : .failed)

        // Verify
        setStep(.verify, .running)
        writeDefaultConfigIfNeeded()
        writeSetupCompleted()
        await refreshStatus()
        setStep(.verify, hermesHealthy ? .done : .failed)

        showSetup = !hermesHealthy
        isWorking = false

        if hermesHealthy {
            statusText = "Hermes Agent online"
        } else {
            statusText = "Gateway recovering..."
            errorText = "Setup completed but gateway is still starting. It should be ready in a moment."
        }
    }

    func deferSetup() {
        showSetup = false
        statusText = "Hermes not configured"
    }

    // MARK: - Install Hermes

    private func installHermes() async {
        let cmd = "curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- --skip-setup"
        let result = await ShellCommand.run(cmd)
        if result.exitCode != 0 {
            await ChatDiagnostics.shared.log("hermes-install-fail stderr=\(result.stderr)")
        } else {
            await ChatDiagnostics.shared.log("hermes-install-ok")
        }
    }

    // MARK: - Gateway Management

    private func ensureGatewayRunning() async {
        // First check if it's already healthy
        if await isGatewayHealthy() {
            hermesHealthy = true
            statusText = "Hermes Agent online"
            return
        }

        // Try starting gateway
        let hermesCmd = hermesHome
            .appendingPathComponent("hermes-agent", isDirectory: true)
            .appendingPathComponent("venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("hermes")
            .path

        // Try the installed hermes command
        let startCmd = "nohup '\(hermesCmd)' gateway > '\(hermesHome.path)/logs/junipero-gateway.log' 2>&1 &"
        let result = await ShellCommand.run(startCmd)
        if result.exitCode != 0 {
            // Try PATH-based hermes
            let fallback = await ShellCommand.run("nohup hermes gateway > /tmp/junipero-hermes-gateway.log 2>&1 &")
            if fallback.exitCode != 0 {
                await ChatDiagnostics.shared.log("gateway-start-fail stderr=\(result.stderr) fallback=\(fallback.stderr)")
            }
        }

        // Wait for gateway to come up
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if await isGatewayHealthy() {
                hermesHealthy = true
                statusText = "Hermes Agent online"
                return
            }
        }

        hermesHealthy = false
        statusText = "Gateway starting..."
    }

    private func isGatewayHealthy() async -> Bool {
        let config = HermesClient.resolveConfig()
        let endpoint = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/health"
        guard let url = URL(string: endpoint) else { return false }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 5
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    func refreshStatus() async {
        hermesHealthy = await isGatewayHealthy()

        if !hermesHealthy {
            await ChatDiagnostics.shared.log("monitor: gateway unhealthy, attempting restart")
            await ensureGatewayRunning()
        }

        if enableOllamaFallback {
            let ollama = await ShellCommand.run("ollama list >/dev/null 2>&1")
            ollamaHealthy = (ollama.exitCode == 0)
        }

        if hermesHealthy {
            statusText = enableOllamaFallback
                ? (ollamaHealthy ? "All systems healthy" : "Hermes online, Ollama recovering")
                : "Hermes Agent online"
        } else {
            statusText = "Hermes recovering..."
        }
    }

    // MARK: - Diagnostics

    func runDiagnostics() async {
        guard !isWorking else { return }
        isWorking = true
        statusText = "Running diagnostics..."

        var lines: [String] = []

        hermesInstalled = checkHermesInstalled()
        lines.append("Hermes installed: \(hermesInstalled ? "yes" : "no")")

        let healthy = await isGatewayHealthy()
        lines.append("Gateway: \(healthy ? "healthy" : "unreachable")")

        if enableOllamaFallback {
            let ollama = await ShellCommand.run("ollama --version")
            lines.append("Ollama: \(ollama.exitCode == 0 ? "installed" : "not found")")
        }

        diagnosticsSummary = lines.joined(separator: " | ")
        statusText = "Diagnostics complete"
        isWorking = false
    }

    func exportSupportBundle() async {
        guard !isWorking else { return }
        isWorking = true
        statusText = "Exporting support bundle..."

        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let archivePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("junipero-support-\(stamp).txt")

        var lines: [String] = [
            "Junipero v2 Support Bundle",
            "Generated: \(stamp)",
            "---",
            "Status: \(statusText)",
            "Hermes installed: \(hermesInstalled)",
            "Hermes healthy: \(hermesHealthy)",
            "Ollama healthy: \(ollamaHealthy)",
            "Diagnostics: \(diagnosticsSummary)",
            "---"
        ]

        let health = await ShellCommand.run("curl -s http://127.0.0.1:8642/health")
        lines.append("Health endpoint: \(health.stdout)")

        if let configData = try? String(contentsOf: configURL, encoding: .utf8) {
            lines.append("Config: \(configData)")
        }

        let output = lines.joined(separator: "\n")
        try? output.data(using: .utf8)?.write(to: archivePath, options: .atomic)

        statusText = "Support bundle exported to Desktop"
#if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([archivePath])
#endif
        isWorking = false
    }

    // MARK: - Preferences

    var canDisableGuardrails: Bool {
        JuniperoPreferencesStore.load().probationComplete
    }

    func setLiabilityMode(_ mode: LiabilityMode) {
        var prefs = JuniperoPreferencesStore.load()
        prefs.liabilityMode = prefs.probationComplete ? mode : .idiot
        JuniperoPreferencesStore.save(prefs)
    }

    func stateForStep(_ step: SetupStep) -> StepState {
        stepStates[step] ?? .pending
    }

    // MARK: - Private Helpers

    private func checkHermesInstalled() -> Bool {
        let agentDir = hermesHome.appendingPathComponent("hermes-agent", isDirectory: true)
        return FileManager.default.fileExists(atPath: agentDir.path)
    }

    private func writeDefaultConfigIfNeeded() {
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }
        let config = HermesConfig.default
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: configURL, options: .atomic)
        }
    }

    private func writeSetupCompleted() {
        struct SetupState: Codable { var completed: Bool; var setupDate: Date }
        let state = SetupState(completed: true, setupDate: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(state) {
            try? data.write(to: setupURL, options: .atomic)
        }
    }

    private func resetStepStates() {
        stepStates = Dictionary(uniqueKeysWithValues: SetupStep.allCases.map { ($0, .pending) })
    }

    private func setStep(_ step: SetupStep, _ state: StepState) {
        stepStates[step] = state
    }

    private func startMonitor() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
                await self.refreshStatus()
            }
        }
    }

    private func syncPreferences() {
        let prefs = JuniperoPreferencesStore.load()
        liabilityMode = prefs.effectiveLiabilityMode
    }
}
