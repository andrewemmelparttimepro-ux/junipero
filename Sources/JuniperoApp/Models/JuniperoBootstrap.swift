import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

@MainActor
final class JuniperoBootstrap: ObservableObject {
    enum SetupMode: String, CaseIterable, Identifiable {
        case freeLocal = "Free Local"
        case bringYourOwn = "Bring Your Own Plan"

        var id: String { rawValue }
    }

    struct SetupState: Codable {
        var completed: Bool
        var setupDate: Date
    }

    enum SetupStep: String, CaseIterable, Identifiable {
        case migrate = "Migrate Config"
        case runtime = "Start OpenClaw"
        case fallback = "Prepare Fallback"
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

    @Published var setupMode: SetupMode = .freeLocal
    @Published var providerToken: String = ""
    @Published var providerModel: String = "anthropic/claude-sonnet-4-6"
    @Published var enableOllamaFallback: Bool = true
    @Published var autoInstallKimi: Bool = false
    @Published var selectedOllamaModel: String = "kimi-k2.5"
    @Published var showSetup: Bool = false
    @Published var isWorking: Bool = false
    @Published var statusText: String = "Checking AI runtime…"
    @Published var errorText: String?
    @Published var openClawHealthy: Bool = false
    @Published var ollamaHealthy: Bool = false
    @Published var diagnosticsSummary: String = "Diagnostics not run yet."
    @Published var missingOllamaModel: Bool = false
    @Published var lastSupportBundlePath: String?
    @Published private(set) var stepStates: [SetupStep: StepState] = [:]
    @Published var liabilityMode: LiabilityMode = .idiot
    @Published var probationInteractionCount: Int = 0
    @Published var probationStatusText: String = "Probation active"

    private let juniperoDir: URL
    private let configURL: URL
    private let setupURL: URL
    private var didStart = false
    private var monitorTask: Task<Void, Never>?
    private var preferencesObserver: NSObjectProtocol?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
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

    func startIfNeeded() async {
        guard !didStart else { return }
        didStart = true
        try? FileManager.default.createDirectory(at: juniperoDir, withIntermediateDirectories: true)
        resetStepStates()
        setStep(.migrate, .running)
        migrateConfigIfNeeded()
        setStep(.migrate, .done)

        if readSetupState()?.completed == true {
            setStep(.runtime, .running)
            await ensureRuntime(autoInstallModel: false)
            setStep(.runtime, openClawHealthy ? .done : .failed)
            setStep(.fallback, (!enableOllamaFallback || ollamaHealthy) ? .done : .failed)
            setStep(.verify, .running)
            await refreshRuntimeStatus()
            setStep(.verify, openClawHealthy ? .done : .failed)
            showSetup = false
        } else {
            statusText = "Setup required"
            showSetup = true
        }

        startRuntimeMonitor()
    }

    func completeOneClickSetup() async {
        guard !isWorking else { return }
        isWorking = true
        errorText = nil
        statusText = "Setting up Junipero runtime…"
        resetStepStates()
        setStep(.migrate, .running)
        migrateConfigIfNeeded()
        setStep(.migrate, .done)

        setStep(.runtime, .running)
        await ensureRuntime(autoInstallModel: autoInstallKimi)
        setStep(.runtime, openClawHealthy ? .done : .failed)
        setStep(.fallback, (!enableOllamaFallback || ollamaHealthy) ? .done : .failed)

        setStep(.save, .running)
        writeJuniperoConfig()
        writeSetupState(SetupState(completed: true, setupDate: Date()))
        setStep(.save, .done)

        setStep(.verify, .running)
        showSetup = false
        isWorking = false
        await refreshRuntimeStatus()
        setStep(.verify, openClawHealthy ? .done : .failed)
        if !openClawHealthy {
            errorText = "Setup completed with warnings. OpenClaw is still recovering."
        }
    }

    func deferSetup() {
        showSetup = false
        statusText = "Runtime not configured yet"
    }

    var canDisableGuardrails: Bool {
        JuniperoPreferencesStore.load().probationComplete
    }

    func setLiabilityMode(_ mode: LiabilityMode) {
        var prefs = JuniperoPreferencesStore.load()
        if !prefs.probationComplete {
            prefs.liabilityMode = .idiot
        } else {
            prefs.liabilityMode = mode
        }
        JuniperoPreferencesStore.save(prefs)
    }

    func runGuidedDiagnostics() async {
        guard !isWorking else { return }
        isWorking = true
        errorText = nil
        statusText = "Running diagnostics…"

        let openclawVersion = await ShellCommand.run("openclaw --version")
        let gatewayHealth = await ShellCommand.run("openclaw gateway health")
        let ollamaVersion = await ShellCommand.run("ollama --version")
        let ollamaList = await ShellCommand.run("ollama list")

        var lines: [String] = []
        if openclawVersion.exitCode == 0 {
            lines.append("OpenClaw CLI: installed")
        } else {
            lines.append("OpenClaw CLI: missing or broken")
        }
        lines.append("OpenClaw gateway: \(gatewayHealth.exitCode == 0 ? "healthy" : "unhealthy")")
        lines.append("Ollama: \(ollamaVersion.exitCode == 0 ? "installed" : "not installed")")
        if ollamaList.exitCode == 0 {
            if let preferred = preferredModel(from: ollamaList.stdout) {
                lines.append("Fallback model: \(preferred)")
                missingOllamaModel = false
            } else {
                lines.append("Fallback model: missing")
                missingOllamaModel = true
            }
        } else {
            lines.append("Fallback model: unavailable")
            missingOllamaModel = true
        }

        diagnosticsSummary = lines.joined(separator: " | ")
        statusText = "Diagnostics complete"
        isWorking = false
    }

    func runFullHealthTest() async {
        guard !isWorking else { return }
        isWorking = true
        errorText = nil
        statusText = "Running full health test…"

        var passes = 0
        var fails = 0
        var report: [String] = []

        let openclawVersion = await ShellCommand.run("openclaw --version")
        if openclawVersion.exitCode == 0 { passes += 1; report.append("CLI PASS") } else { fails += 1; report.append("CLI FAIL") }

        let gatewayHealth = await ShellCommand.run("openclaw gateway health >/dev/null 2>&1")
        if gatewayHealth.exitCode == 0 { passes += 1; report.append("Gateway PASS") } else { fails += 1; report.append("Gateway FAIL") }

        let writeTestURL = juniperoDir.appendingPathComponent(".smoke-write-test")
        do {
            try "ok".data(using: .utf8)?.write(to: writeTestURL, options: .atomic)
            _ = try String(contentsOf: writeTestURL, encoding: .utf8)
            try? FileManager.default.removeItem(at: writeTestURL)
            passes += 1
            report.append("Storage PASS")
        } catch {
            fails += 1
            report.append("Storage FAIL")
        }

        if enableOllamaFallback {
            let ollama = await ShellCommand.run("ollama list")
            if ollama.exitCode == 0 {
                passes += 1
                report.append("Ollama PASS")
                if preferredModel(from: ollama.stdout) == nil {
                    fails += 1
                    missingOllamaModel = true
                    report.append("Model FAIL")
                } else {
                    passes += 1
                    missingOllamaModel = false
                    report.append("Model PASS")
                }
            } else {
                fails += 2
                report.append("Ollama FAIL")
                report.append("Model FAIL")
                missingOllamaModel = true
            }
        }

        diagnosticsSummary = "Full Test \(passes) pass / \(fails) fail: " + report.joined(separator: ", ")
        statusText = fails == 0 ? "Full health test passed" : "Full health test found issues"
        isWorking = false
    }

    func installMissingFallbackModel() async {
        guard !isWorking else { return }
        guard enableOllamaFallback else { return }
        isWorking = true
        statusText = "Installing fallback model…"

        let pull = await ShellCommand.run("ollama pull \(selectedOllamaModel)")
        if pull.exitCode == 0 {
            missingOllamaModel = false
            statusText = "Fallback model installed"
        } else {
            errorText = "Could not install \(selectedOllamaModel). Check Ollama and network."
            statusText = "Fallback install failed"
            await ChatDiagnostics.shared.log("bootstrap fallback install failed stderr=\(pull.stderr)")
        }
        isWorking = false
    }

    func exportSupportBundle() async {
        guard !isWorking else { return }
        isWorking = true
        statusText = "Exporting support bundle…"
        errorText = nil

        let stamp = isoStamp()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("junipero-support-\(stamp)", isDirectory: true)
        let archivePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("junipero-support-\(stamp).zip")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try await writeBundleFiles(into: tempDir)
            let cmd = "cd '\(tempDir.deletingLastPathComponent().path)' && /usr/bin/zip -r '\(archivePath.path)' '\(tempDir.lastPathComponent)' >/dev/null"
            let zip = await ShellCommand.run(cmd)
            if zip.exitCode != 0 {
                throw NSError(domain: "JuniperoBundle", code: 2, userInfo: [NSLocalizedDescriptionKey: "zip command failed"])
            }
            lastSupportBundlePath = archivePath.path
            statusText = "Support bundle exported"
#if os(macOS)
            NSWorkspace.shared.activateFileViewerSelecting([archivePath])
#endif
        } catch {
            errorText = "Support bundle export failed."
            statusText = "Export failed"
            await ChatDiagnostics.shared.log("support bundle export failed error=\(error.localizedDescription)")
        }

        try? FileManager.default.removeItem(at: tempDir)
        isWorking = false
    }

    private func ensureRuntime(autoInstallModel: Bool) async {
        await ensureOpenClawService()
        if enableOllamaFallback {
            await ensureOllamaService(autoInstallModel: autoInstallModel)
        }
    }

    private func migrateConfigIfNeeded() {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return }
        do {
            let data = try Data(contentsOf: configURL)
            var config = try JSONDecoder().decode(OpenClawConfig.self, from: data)
            var changed = false

            if let token = config.token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
                _ = KeychainStore.saveProviderToken(token)
                config.token = nil
                changed = true
            }
            if config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                config.model = OpenClawConfig.default.model
                changed = true
            }
            if config.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                config.ollamaModel = OpenClawConfig.default.ollamaModel
                changed = true
            }
            if changed {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let fresh = try encoder.encode(config)
                try fresh.write(to: configURL, options: .atomic)
                diagnosticsSummary = "Config migrated to latest format."
            }
        } catch {
            let broken = juniperoDir.appendingPathComponent("config-corrupt-\(isoStamp()).json")
            try? FileManager.default.moveItem(at: configURL, to: broken)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let fresh = try? encoder.encode(OpenClawConfig.default) {
                try? fresh.write(to: configURL, options: .atomic)
            }
            errorText = "Recovered from invalid config and reset defaults."
            diagnosticsSummary = "Migration recovered from corrupt config."
            showSetup = true
        }
    }

    private func ensureOpenClawService() async {
        statusText = "Ensuring OpenClaw service…"
        let install = await ShellCommand.run("openclaw gateway install")
        if install.exitCode != 0 {
            await ChatDiagnostics.shared.log("bootstrap gateway install stderr=\(install.stderr)")
        }

        let start = await ShellCommand.run("openclaw gateway start")
        if start.exitCode != 0 {
            let force = await ShellCommand.run("openclaw gateway run --force >/tmp/junipero-openclaw.log 2>&1 &")
            if force.exitCode != 0 {
                errorText = "OpenClaw could not start automatically. Install/update OpenClaw CLI and retry setup."
                statusText = "OpenClaw start failed"
                await ChatDiagnostics.shared.log("bootstrap gateway start failed stderr=\(start.stderr) forceErr=\(force.stderr)")
                return
            }
        }

        statusText = "OpenClaw online"
        openClawHealthy = true
    }

    private func ensureOllamaService(autoInstallModel: Bool) async {
        statusText = "Checking Ollama fallback…"
        let list = await ShellCommand.run("ollama list")

        if list.exitCode != 0 {
            let start = await ShellCommand.run("nohup ollama serve >/tmp/junipero-ollama.log 2>&1 &")
            if start.exitCode != 0 {
                await ChatDiagnostics.shared.log("bootstrap ollama start failed stderr=\(start.stderr)")
                statusText = "Ollama unavailable (fallback disabled)"
                enableOllamaFallback = false
                ollamaHealthy = false
                return
            }
        }

        let refresh = await ShellCommand.run("ollama list")
        if refresh.exitCode == 0 {
            if let model = preferredModel(from: refresh.stdout) {
                selectedOllamaModel = model
            } else if autoInstallModel {
                statusText = "Downloading \(selectedOllamaModel) for fallback…"
                let pull = await ShellCommand.run("ollama pull \(selectedOllamaModel)")
                if pull.exitCode != 0 {
                    await ChatDiagnostics.shared.log("bootstrap ollama pull failed stderr=\(pull.stderr)")
                    statusText = "Ollama started, model download failed"
                } else {
                    statusText = "Ollama fallback ready"
                }
                ollamaHealthy = true
            } else {
                statusText = "Ollama running (no model found yet)"
                ollamaHealthy = true
            }
        } else {
            ollamaHealthy = false
        }
    }

    private func preferredModel(from ollamaListOutput: String) -> String? {
        let lines = ollamaListOutput.split(separator: "\n").map(String.init)
        guard lines.count > 1 else { return nil }
        let names = lines.dropFirst().compactMap { line -> String? in
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard let first = parts.first else { return nil }
            return String(first)
        }

        let preferred = ["kimi-k2.5", "qwen2.5-coder:7b", "llama3.1:8b"]
        for item in preferred where names.contains(item) {
            return item
        }
        return names.first
    }

    private func writeJuniperoConfig() {
        let token = providerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if setupMode == .bringYourOwn {
            _ = KeychainStore.saveProviderToken(token)
        } else {
            _ = KeychainStore.deleteProviderToken()
        }

        let config = OpenClawConfig(
            baseURL: "http://127.0.0.1:18789",
            model: providerModel,
            token: nil,
            timeoutSeconds: 45,
            ollamaFallbackEnabled: enableOllamaFallback,
            ollamaBaseURL: "http://127.0.0.1:11434",
            ollamaModel: selectedOllamaModel
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: configURL, options: .atomic)
        }
    }

    private func readSetupState() -> SetupState? {
        guard let data = try? Data(contentsOf: setupURL) else { return nil }
        return try? JSONDecoder().decode(SetupState.self, from: data)
    }

    private func writeSetupState(_ state: SetupState) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(state) {
            try? data.write(to: setupURL, options: .atomic)
        }
    }

    private func startRuntimeMonitor() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshRuntimeStatus()
                try? await Task.sleep(nanoseconds: 25_000_000_000)
            }
        }
    }

    func refreshRuntimeStatus() async {
        let gateway = await ShellCommand.run("openclaw gateway health >/dev/null 2>&1")
        openClawHealthy = (gateway.exitCode == 0)

        if !openClawHealthy {
            await ChatDiagnostics.shared.log("monitor: gateway unhealthy, attempting heal")
            let heal = await ShellCommand.run("openclaw gateway start")
            if heal.exitCode != 0 {
                _ = await ShellCommand.run("openclaw gateway run --force >/tmp/junipero-openclaw.log 2>&1 &")
            }
            let verify = await ShellCommand.run("openclaw gateway health >/dev/null 2>&1")
            openClawHealthy = (verify.exitCode == 0)
        }

        if enableOllamaFallback {
            let ollama = await ShellCommand.run("ollama list >/dev/null 2>&1")
            ollamaHealthy = (ollama.exitCode == 0)
            if !ollamaHealthy {
                _ = await ShellCommand.run("nohup ollama serve >/tmp/junipero-ollama.log 2>&1 &")
                let verifyOllama = await ShellCommand.run("ollama list >/dev/null 2>&1")
                ollamaHealthy = (verifyOllama.exitCode == 0)
            }
            if ollamaHealthy {
                let list = await ShellCommand.run("ollama list")
                missingOllamaModel = (preferredModel(from: list.stdout) == nil)
            } else {
                missingOllamaModel = true
            }
        } else {
            ollamaHealthy = false
            missingOllamaModel = false
        }

        if openClawHealthy {
            statusText = enableOllamaFallback
                ? (ollamaHealthy ? "Runtime healthy" : "OpenClaw healthy, Ollama recovering")
                : "OpenClaw healthy"
        } else {
            statusText = "Runtime recovering"
            errorText = "OpenClaw runtime is restarting in the background."
        }
    }

    private func writeBundleFiles(into dir: URL) async throws {
        let fm = FileManager.default
        let diag = [
            "statusText: \(statusText)",
            "openClawHealthy: \(openClawHealthy)",
            "ollamaHealthy: \(ollamaHealthy)",
            "missingOllamaModel: \(missingOllamaModel)",
            "diagnosticsSummary: \(diagnosticsSummary)"
        ].joined(separator: "\n")
        try diag.data(using: .utf8)?.write(to: dir.appendingPathComponent("runtime.txt"), options: .atomic)

        if fm.fileExists(atPath: configURL.path) {
            let redactedURL = dir.appendingPathComponent("config.redacted.json")
            if var configText = try? String(contentsOf: configURL, encoding: .utf8) {
                configText = configText.replacingOccurrences(of: "\"token\"\\s*:\\s*\"[^\"]*\"", with: "\"token\":\"<redacted>\"", options: .regularExpression)
                try configText.data(using: .utf8)?.write(to: redactedURL, options: .atomic)
            }
        }

        let juniperoLog = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".junipero", isDirectory: true)
            .appendingPathComponent("chat.log")
        if fm.fileExists(atPath: juniperoLog.path) {
            try? fm.copyItem(at: juniperoLog, to: dir.appendingPathComponent("chat.log"))
        }

        let health = await ShellCommand.run("openclaw gateway health")
        try health.stdout.data(using: .utf8)?.write(to: dir.appendingPathComponent("gateway-health.txt"), options: .atomic)
        let status = await ShellCommand.run("openclaw gateway status")
        try status.stdout.data(using: .utf8)?.write(to: dir.appendingPathComponent("gateway-status.txt"), options: .atomic)
        let ollama = await ShellCommand.run("ollama list")
        try ollama.stdout.data(using: .utf8)?.write(to: dir.appendingPathComponent("ollama-list.txt"), options: .atomic)
    }

    private func isoStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    func stateForStep(_ step: SetupStep) -> StepState {
        stepStates[step] ?? .pending
    }

    private func resetStepStates() {
        stepStates = Dictionary(uniqueKeysWithValues: SetupStep.allCases.map { ($0, .pending) })
    }

    private func setStep(_ step: SetupStep, _ state: StepState) {
        stepStates[step] = state
    }

    private func syncPreferences() {
        let prefs = JuniperoPreferencesStore.load()
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
