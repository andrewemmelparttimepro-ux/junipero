import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

@MainActor
final class ThrawnBootstrap: ObservableObject {
    enum SetupMode: String, CaseIterable, Identifiable {
        case openClawDirect = "OpenClaw Direct"
        case bringYourOwn = "Provider Override"

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
            guard launchAgentLoaded, apiReachable, adapterReachable else { return false }
            guard workspaceFiles > 0 else { return true }
            guard let datasetID, !datasetID.isEmpty else { return false }
            return pendingFiles == 0 && indexedFiles >= workspaceFiles
        }
    }

    private struct OpenClawAuthProfileFile: Decodable {
        var profiles: [String: OpenClawAuthProfile]
    }

    private struct OpenClawAuthProfile: Decodable {
        var type: String?
        var provider: String?
        var token: String?
    }

    @Published var setupMode: SetupMode = .openClawDirect
    @Published var providerToken: String = ""
    @Published var providerModel: String = OpenClawConfig.default.model
    @Published var preferLocalFirst: Bool = false
    @Published var alwaysRouteThroughOpenClaw: Bool = true
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
    @Published var openClawHealthy: Bool = false
    @Published var ollamaHealthy: Bool = false
    @Published var cogneeHealthy: Bool = false
    @Published var cogneeStatusText: String = "Memory pending"
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

    private let juniperoDir: URL
    private let configURL: URL
    private let setupURL: URL
    private var didStart = false
    private var monitorTask: Task<Void, Never>?
    private var preferencesObserver: NSObjectProtocol?
    private var lastCogneeIndexAttemptAt: Date?

    var cogneeBadgeText: String {
        if cogneeHealthy {
            if cogneeWorkspaceFiles > 0 {
                return "Memory \(cogneeIndexedFiles)/\(cogneeWorkspaceFiles)"
            }
            return "Memory ready"
        }
        return cogneeStatusText
    }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.juniperoDir = home.appendingPathComponent(".junipero", isDirectory: true)
        self.configURL = juniperoDir.appendingPathComponent("config.json")
        self.setupURL = juniperoDir.appendingPathComponent("setup.json")
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

    var ollamaFallbackActive: Bool {
        unlockLocalOllamaOptions && enableOllamaFallback
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
            await syncOpenClawConfigForFreshSetup()
            await syncMainSessionRouting()
            setStep(.runtime, openClawHealthy ? .done : .failed)
            setStep(.fallback, (!ollamaFallbackActive || ollamaHealthy) ? .done : .failed)
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
        statusText = "Setting up Thrawn runtime…"
        applySetupModeDefaults()
        resetStepStates()
        setStep(.migrate, .running)
        migrateConfigIfNeeded()
        setStep(.migrate, .done)

        setStep(.runtime, .running)
        await ensureRuntime(autoInstallModel: autoInstallKimi)
        await syncOpenClawConfigForFreshSetup()
        await syncMainSessionRouting()
        setStep(.runtime, openClawHealthy ? .done : .failed)
        setStep(.fallback, (!ollamaFallbackActive || ollamaHealthy) ? .done : .failed)

        setStep(.save, .running)
        writeThrawnConfig()
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
        ThrawnPreferencesStore.load().probationComplete
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

    func runGuidedDiagnostics() async {
        guard !isWorking else { return }
        isWorking = true
        errorText = nil
        statusText = "Running diagnostics…"

        let openclawVersion = await ShellCommand.run("openclaw --version")
        let gatewayHealthy = await isGatewayHealthy()
        let cognee = await fetchCogneeStatus()

        var lines: [String] = []
        if openclawVersion.exitCode == 0 {
            lines.append("OpenClaw CLI: installed")
        } else {
            lines.append("OpenClaw CLI: missing or broken")
        }
        lines.append("OpenClaw gateway: \(gatewayHealthy ? "healthy" : "unhealthy")")
        if cognee.isHealthy {
            lines.append("Cognee: indexed \(cognee.indexedFiles)/\(cognee.workspaceFiles)")
        } else if let lastError = cognee.lastError, !lastError.isEmpty {
            lines.append("Cognee: \(lastError)")
        } else if !cognee.launchAgentLoaded {
            lines.append("Cognee: launch agent unavailable")
        } else if !cognee.adapterReachable {
            lines.append("Cognee: OpenClaw gateway endpoint offline")
        } else if !cognee.apiReachable {
            lines.append("Cognee: API unreachable")
        } else {
            lines.append("Cognee: syncing \(cognee.pendingFiles) pending")
        }
        if ollamaFallbackActive {
            let ollamaVersion = await ShellCommand.run("ollama --version")
            let ollamaList = await ShellCommand.run("ollama list")
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
        } else {
            lines.append(unlockLocalOllamaOptions ? "Ollama fallback: unlocked but off" : "Ollama fallback: off")
            missingOllamaModel = false
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

        let gatewayHealthy = await isGatewayHealthy()
        if gatewayHealthy { passes += 1; report.append("Gateway PASS") } else { fails += 1; report.append("Gateway FAIL") }

        let cognee = await fetchCogneeStatus()
        if cognee.isHealthy {
            passes += 1
            report.append("Cognee PASS")
        } else {
            fails += 1
            report.append("Cognee FAIL")
        }

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

        if ollamaFallbackActive {
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
        } else {
            report.append("Ollama SKIP")
            missingOllamaModel = false
        }

        diagnosticsSummary = "Full Test \(passes) pass / \(fails) fail: " + report.joined(separator: ", ")
        statusText = fails == 0 ? "Full health test passed" : "Full health test found issues"
        isWorking = false
    }

    func installMissingFallbackModel() async {
        guard !isWorking else { return }
        guard ollamaFallbackActive else { return }
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

    func reindexCogneeMemory() async {
        guard !isWorking else { return }
        isWorking = true
        errorText = nil
        statusText = "Syncing Cognee memory…"
        await ensureCogneePluginConfig()
        await restartCogneeService(reason: "manual reindex")
        await refreshCogneeStatus(forceIndexIfNeeded: true, forceReindex: true)
        statusText = cogneeHealthy ? "Cognee memory ready" : cogneeStatusText
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
                throw NSError(domain: "ThrawnBundle", code: 2, userInfo: [NSLocalizedDescriptionKey: "zip command failed"])
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
        if ollamaFallbackActive {
            await ensureOllamaService(autoInstallModel: autoInstallModel)
        }
        await ensureCogneeService()
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
        if await isGatewayHealthy() {
            openClawHealthy = true
            statusText = "OpenClaw online"
            return
        }

        statusText = "Ensuring OpenClaw service…"
        if !openClawLaunchAgentInstalled() {
            let install = await ShellCommand.run("openclaw gateway install")
            if install.exitCode != 0 {
                await ChatDiagnostics.shared.log("bootstrap gateway install stderr=\(install.stderr)")
            }
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

        openClawHealthy = await isGatewayHealthy()
        statusText = openClawHealthy ? "OpenClaw online" : "OpenClaw recovering"
    }

    private func ensureOllamaService(autoInstallModel: Bool) async {
        statusText = "Checking Ollama fallback…"
        let list = await ShellCommand.run("ollama list")

        if list.exitCode != 0 {
            let start = await ShellCommand.run("nohup ollama serve >/tmp/junipero-ollama.log 2>&1 &")
            if start.exitCode != 0 {
                await ChatDiagnostics.shared.log("bootstrap ollama start failed stderr=\(start.stderr)")
                statusText = "Ollama unavailable"
                ollamaHealthy = false
                missingOllamaModel = true
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
                missingOllamaModel = true
            }
        } else {
            ollamaHealthy = false
            missingOllamaModel = true
        }
    }

    private func ensureCogneeService() async {
        await ensureCogneePluginConfig()
        await ensureCogneeAgent()

        let launchFilesChanged = ensureCogneeLaunchFiles()
        let launchAgentLoaded = await isCogneeLaunchAgentLoaded()
        let apiReachable = await isCogneeAPIReachable()
        let adapterReachable = await isCogneeGatewayReady()

        if launchFilesChanged || !launchAgentLoaded || !apiReachable || !adapterReachable {
            await restartCogneeService(reason: launchFilesChanged ? "config-updated" : "runtime-heal")
        }

        await refreshCogneeStatus(forceIndexIfNeeded: true)
    }

    private func refreshCogneeStatus(forceIndexIfNeeded: Bool, forceReindex: Bool = false) async {
        var snapshot = await fetchCogneeStatus()

        let shouldIndex = forceIndexIfNeeded
            && snapshot.apiReachable
            && snapshot.adapterReachable
            && (
                forceReindex
                || snapshot.pendingFiles > 0
                || (snapshot.workspaceFiles > 0 && (snapshot.datasetID == nil || snapshot.indexedFiles == 0))
            )

        if shouldIndex {
            _ = await runCogneeIndex(force: forceReindex)
            snapshot = await fetchCogneeStatus()
        }

        cogneeHealthy = snapshot.isHealthy
        cogneeStatusText = formatCogneeStatus(snapshot)
        cogneeIndexedFiles = snapshot.indexedFiles
        cogneeWorkspaceFiles = snapshot.workspaceFiles
        cogneePendingFiles = snapshot.pendingFiles
    }

    private func fetchCogneeStatus() async -> CogneeStatusSnapshot {
        var snapshot = CogneeStatusSnapshot()
        snapshot.launchAgentLoaded = await isCogneeLaunchAgentLoaded()
        snapshot.apiReachable = await isCogneeAPIReachable()
        snapshot.adapterReachable = await isCogneeGatewayReady()

        let status = await ShellCommand.run("openclaw cognee status")
        guard status.exitCode == 0 else {
            snapshot.lastError = "Memory status unavailable"
            return snapshot
        }

        for rawLine in status.stdout.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("Dataset:") {
                snapshot.datasetName = line.replacingOccurrences(of: "Dataset:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if line.hasPrefix("Dataset ID:") {
                let value = line.replacingOccurrences(of: "Dataset ID:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                snapshot.datasetID = value == "(not set)" ? nil : value
            } else if line.hasPrefix("Indexed files:") {
                snapshot.indexedFiles = firstInteger(in: line) ?? 0
            } else if line.hasPrefix("Workspace files:") {
                snapshot.workspaceFiles = firstInteger(in: line) ?? 0
            } else if line.hasPrefix("New (unindexed):") {
                snapshot.newFiles = firstInteger(in: line) ?? 0
            } else if line.hasPrefix("Changed (dirty):") {
                snapshot.changedFiles = firstInteger(in: line) ?? 0
            }
        }

        if !snapshot.launchAgentLoaded {
            snapshot.lastError = "Memory service offline"
        } else if !snapshot.adapterReachable {
            snapshot.lastError = "Memory gateway offline"
        } else if !snapshot.apiReachable {
            snapshot.lastError = "Memory API offline"
        }

        return snapshot
    }

    private func runCogneeIndex(force: Bool) async -> Bool {
        let now = Date()
        if !force,
           let lastAttempt = lastCogneeIndexAttemptAt,
           now.timeIntervalSince(lastAttempt) < 120
        {
            return false
        }

        lastCogneeIndexAttemptAt = now
        let index = await ShellCommand.run("openclaw cognee index")
        if index.exitCode != 0 {
            await ChatDiagnostics.shared.log("cognee: index failed stderr=\(index.stderr) stdout=\(index.stdout)")
            return false
        }

        await ChatDiagnostics.shared.log("cognee: index complete stdout=\(index.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
        return true
    }

    private func ensureCogneePluginConfig() async {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("openclaw.json")

        guard let data = try? Data(contentsOf: path),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return
        }

        var plugins = root["plugins"] as? [String: Any] ?? [:]
        var allow = plugins["allow"] as? [String] ?? []
        if !allow.contains("cognee-openclaw") {
            allow.append("cognee-openclaw")
        }
        plugins["allow"] = allow.sorted()

        var slots = plugins["slots"] as? [String: Any] ?? [:]
        slots["memory"] = "cognee-openclaw"
        plugins["slots"] = slots

        var entries = plugins["entries"] as? [String: Any] ?? [:]
        var cogneeEntry = entries["cognee-openclaw"] as? [String: Any] ?? [:]
        // Keep plugin registered but disable autoRecall to prevent chat blocking.
        // autoRecall intercepts every chat request and hangs if cognee is slow/down.
        if cogneeEntry["enabled"] == nil {
            cogneeEntry["enabled"] = true
        }
        var cogneeConfig = cogneeEntry["config"] as? [String: Any] ?? [:]
        cogneeConfig["baseUrl"] = "http://localhost:8000"
        cogneeConfig["datasetName"] = "ndai"
        cogneeConfig["deleteMode"] = "hard"
        cogneeConfig["searchType"] = "GRAPH_COMPLETION"
        cogneeConfig["maxResults"] = 8
        cogneeConfig["autoIndex"] = true
        cogneeConfig["autoRecall"] = false
        cogneeConfig["autoCognify"] = false
        cogneeEntry["config"] = cogneeConfig
        entries["cognee-openclaw"] = cogneeEntry
        plugins["entries"] = entries
        root["plugins"] = plugins

        var gateway = root["gateway"] as? [String: Any] ?? [:]
        var http = gateway["http"] as? [String: Any] ?? [:]
        var endpoints = http["endpoints"] as? [String: Any] ?? [:]
        var chatCompletions = endpoints["chatCompletions"] as? [String: Any] ?? [:]
        chatCompletions["enabled"] = true
        endpoints["chatCompletions"] = chatCompletions
        http["endpoints"] = endpoints
        gateway["http"] = http
        root["gateway"] = gateway

        guard let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }

        let current = (try? Data(contentsOf: path)) ?? Data()
        if current != out {
            try? out.write(to: path, options: .atomic)
        }
    }

    private func ensureCogneeLaunchFiles() -> Bool {
        let shimChanged = writeFileIfNeeded(
            at: cogneeLLMShimScriptURL(),
            contents: cogneeLLMShimScriptContents(),
            permissions: 0o755
        )
        let scriptChanged = writeFileIfNeeded(
            at: cogneeLauncherScriptURL(),
            contents: cogneeLauncherScriptContents(),
            permissions: 0o755
        )
        let plistChanged = writeFileIfNeeded(
            at: cogneeLaunchAgentURL(),
            contents: cogneeLaunchAgentContents(),
            permissions: 0o644
        )
        return shimChanged || scriptChanged || plistChanged
    }

    private func restartCogneeService(reason: String) async {
        let uid = await currentUserID()
        let plistPath = shellEscape(cogneeLaunchAgentURL().path)
        let label = cogneeLaunchAgentLabel()
        await ChatDiagnostics.shared.log("cognee: restart reason=\(reason)")
        let command = """
        launchctl bootout gui/\(uid) \(plistPath) >/dev/null 2>&1 || true
        launchctl bootstrap gui/\(uid) \(plistPath)
        launchctl kickstart -k gui/\(uid)/\(label) >/dev/null 2>&1 || true
        """
        _ = await ShellCommand.run(command)

        for _ in 0..<20 {
            let apiReady = await isCogneeAPIReachable()
            let adapterReady = await isCogneeGatewayReady()
            if apiReady && adapterReady {
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func isCogneeLaunchAgentLoaded() async -> Bool {
        let uid = await currentUserID()
        let result = await ShellCommand.run("launchctl print gui/\(uid)/\(cogneeLaunchAgentLabel()) >/dev/null 2>&1")
        return result.exitCode == 0
    }

    private func isCogneeAPIReachable() async -> Bool {
        let result = await ShellCommand.run("curl -fsS --max-time 2 http://127.0.0.1:8000/openapi.json >/dev/null 2>&1")
        return result.exitCode == 0
    }

    private func isCogneeGatewayReady() async -> Bool {
        let result = await ShellCommand.run("curl -fsS --max-time 2 http://127.0.0.1:18790/health >/dev/null 2>&1")
        return result.exitCode == 0
    }

    private func currentUserID() async -> String {
        let result = await ShellCommand.run("id -u")
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "501" : trimmed
    }

    private func formatCogneeStatus(_ snapshot: CogneeStatusSnapshot) -> String {
        if let lastError = snapshot.lastError, !lastError.isEmpty {
            return lastError
        }
        if snapshot.workspaceFiles == 0 {
            return "Memory ready"
        }
        if snapshot.pendingFiles > 0 {
            return "Memory syncing \(snapshot.pendingFiles)"
        }
        if snapshot.isHealthy {
            return "Memory indexed \(snapshot.indexedFiles)/\(snapshot.workspaceFiles)"
        }
        return "Memory preparing"
    }

    private func firstInteger(in text: String) -> Int? {
        let digits = text.split(whereSeparator: { !$0.isNumber })
        guard let first = digits.first else { return nil }
        return Int(first)
    }

    private func ensureCogneeAgent() async {
        let agentRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent(cogneeAgentID(), isDirectory: true)
        guard !FileManager.default.fileExists(atPath: agentRoot.path) else {
            return
        }

        let workspace = shellEscape(
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".openclaw", isDirectory: true)
                .appendingPathComponent("workspace", isDirectory: true)
                .path
        )
        let model = shellEscape(desiredRemotePrimaryRoute())
        let agentID = shellEscape(cogneeAgentID())
        let add = await ShellCommand.run(
            "openclaw agents add \(agentID) --workspace \(workspace) --non-interactive --model \(model) --json"
        )
        if add.exitCode != 0 {
            await ChatDiagnostics.shared.log("cognee: agent add failed stderr=\(add.stderr) stdout=\(add.stdout)")
        }
    }

    private func cogneeAgentID() -> String {
        "cognee"
    }

    private func cogneeGatewayBaseURL() -> String {
        "http://127.0.0.1:18789/v1"
    }

    private func cogneeGatewayModelID() -> String {
        "openclaw:cognee"
    }

    private func cogneeShimBaseURL() -> String {
        "http://127.0.0.1:18790/v1"
    }

    private func cogneeShimModelID() -> String {
        "gpt-4o-mini"
    }

    private func cogneeLaunchAgentLabel() -> String {
        "ai.ndai.cognee"
    }

    private func cogneeLaunchAgentURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(cogneeLaunchAgentLabel()).plist")
    }

    private func cogneeLauncherScriptURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("start-cognee-memory.sh")
    }

    private func cogneeLLMShimScriptURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("openclaw-cognee-llm-shim.py")
    }

    private func cogneeLauncherScriptContents() -> String {
        return """
        #!/bin/zsh
        set -euo pipefail

        export HOME="$HOME"
        export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        export ENABLE_BACKEND_ACCESS_CONTROL="false"
        export LLM_PROVIDER="openai"
        OPENCLAW_HOME="$HOME/.openclaw"
        LOG_DIR="$OPENCLAW_HOME/logs"
        SHIM="$OPENCLAW_HOME/bin/openclaw-cognee-llm-shim.py"
        PYTHON_BIN="$HOME/.openclaw/cognee-venv/bin/python"
        UVICORN_BIN="$HOME/.openclaw/cognee-venv/bin/uvicorn"

        mkdir -p "$LOG_DIR"

        GATEWAY_TOKEN=$(/usr/bin/python3 - <<'PY'
        import json
        import pathlib
        import sys

        path = pathlib.Path.home() / ".openclaw" / "openclaw.json"
        try:
            root = json.loads(path.read_text())
        except Exception:
            sys.exit(1)

        token = str(root.get("gateway", {}).get("auth", {}).get("token", "") or "").strip()
        if not token:
            sys.exit(1)
        sys.stdout.write(token)
        PY
        )

        if [[ -z "${GATEWAY_TOKEN}" ]]; then
          echo "Missing OpenClaw gateway token for Cognee." >&2
          exit 1
        fi

        export OPENCLAW_GATEWAY_TOKEN="$GATEWAY_TOKEN"
        export OPENCLAW_COGNEE_GATEWAY_URL="\(cogneeGatewayBaseURL())"
        export OPENCLAW_COGNEE_GATEWAY_MODEL="\(cogneeGatewayModelID())"
        export LLM_MODEL="\(cogneeShimModelID())"
        export LLM_ENDPOINT="\(cogneeShimBaseURL())"
        export LLM_API_KEY="openclaw-local"
        export EMBEDDING_PROVIDER="fastembed"
        export EMBEDDING_MODEL="BAAI/bge-small-en-v1.5"
        export EMBEDDING_DIMENSIONS="384"
        export PYTHONUNBUFFERED="1"

        cleanup() {
          local code=$?
          if [[ -n "${SHIM_PID:-}" ]]; then
            kill "$SHIM_PID" >/dev/null 2>&1 || true
          fi
          if [[ -n "${COGNEE_PID:-}" ]]; then
            kill "$COGNEE_PID" >/dev/null 2>&1 || true
          fi
          wait "${SHIM_PID:-}" >/dev/null 2>&1 || true
          wait "${COGNEE_PID:-}" >/dev/null 2>&1 || true
          exit "$code"
        }

        trap cleanup EXIT INT TERM

        "$PYTHON_BIN" "$SHIM" >>"$LOG_DIR/cognee-shim.log" 2>>"$LOG_DIR/cognee-shim.err" &
        SHIM_PID=$!

        "$UVICORN_BIN" cognee.api.client:app --host 127.0.0.1 --port 8000 >>"$LOG_DIR/cognee.log" 2>>"$LOG_DIR/cognee.err" &
        COGNEE_PID=$!

        while true; do
          if ! kill -0 "$SHIM_PID" >/dev/null 2>&1; then
            wait "$SHIM_PID"
            exit $?
          fi
          if ! kill -0 "$COGNEE_PID" >/dev/null 2>&1; then
            wait "$COGNEE_PID"
            exit $?
          fi
          sleep 1
        done
        """
    }

    private func cogneeLLMShimScriptContents() -> String {
        return """
        #!/usr/bin/env python3
        import json
        import os
        import re
        import sys
        import time
        import uuid
        import urllib.error
        import urllib.request
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

        HOST = "127.0.0.1"
        PORT = 18790
        DEFAULT_MODEL = "\(cogneeShimModelID())"
        DEFAULT_TIMEOUT_SECONDS = 180
        GATEWAY_URL = os.environ.get("OPENCLAW_COGNEE_GATEWAY_URL", "\(cogneeGatewayBaseURL())").rstrip("/") + "/chat/completions"
        GATEWAY_MODEL = os.environ.get("OPENCLAW_COGNEE_GATEWAY_MODEL", "\(cogneeGatewayModelID())")
        GATEWAY_TOKEN = os.environ.get("OPENCLAW_GATEWAY_TOKEN", "")


        def flatten_content(content):
            if isinstance(content, str):
                return content
            if isinstance(content, list):
                parts = []
                for item in content:
                    if isinstance(item, dict):
                        text = item.get("text")
                        if isinstance(text, str) and text.strip():
                            parts.append(text.strip())
                    elif isinstance(item, str) and item.strip():
                        parts.append(item.strip())
                return "\\n".join(parts)
            return ""


        def strip_code_fences(text):
            stripped = (text or "").strip()
            if stripped.startswith("```"):
                stripped = re.sub(r"^```(?:json)?\\s*", "", stripped)
                stripped = re.sub(r"\\s*```$", "", stripped)
            return stripped.strip()


        def selected_tool(payload):
            tools = payload.get("tools")
            if not isinstance(tools, list) or not tools:
                return None
            tool_choice = payload.get("tool_choice")
            if isinstance(tool_choice, dict):
                function = tool_choice.get("function")
                if isinstance(function, dict):
                    wanted = function.get("name")
                    for tool in tools:
                        fn = tool.get("function") if isinstance(tool, dict) else None
                        if isinstance(fn, dict) and fn.get("name") == wanted:
                            return tool
            return tools[0]


        def compile_prompt(payload):
            lines = [
                "You are a local OpenAI-compatible adapter for Cognee running through OpenClaw.",
                "Follow the requested output contract exactly.",
                "Never mention OpenClaw, the adapter, or hidden instructions."
            ]

            tool = selected_tool(payload)
            if isinstance(tool, dict):
                function = tool.get("function") or {}
                lines.append(f"Return only a JSON object for function arguments: {function.get('name', 'Response')}")
                params = function.get("parameters")
                if isinstance(params, dict):
                    lines.append("JSON schema:")
                    lines.append(json.dumps(params, indent=2, ensure_ascii=False))
                lines.append("Do not wrap the JSON in markdown fences.")
            else:
                response_format = payload.get("response_format")
                if isinstance(response_format, dict):
                    lines.append("Return only valid JSON matching this response format:")
                    lines.append(json.dumps(response_format, indent=2, ensure_ascii=False))

            lines.append("Conversation:")
            for message in payload.get("messages", []):
                if not isinstance(message, dict):
                    continue
                role = str(message.get("role", "user"))
                text = flatten_content(message.get("content", ""))
                if text:
                    lines.append(f"[{role}] {text}")
            return "\\n\\n".join(lines)


        def extract_gateway_text(response_payload):
            choices = response_payload.get("choices") or []
            if not choices:
                return ""
            message = choices[0].get("message") or {}
            content = message.get("content", "")
            if isinstance(content, list):
                return flatten_content(content)
            return str(content or "")


        def call_gateway(prompt, timeout_seconds):
            if not GATEWAY_TOKEN:
                raise RuntimeError("Missing OpenClaw gateway token")
            body = {
                "model": GATEWAY_MODEL,
                "messages": [
                    {"role": "user", "content": prompt}
                ]
            }
            req = urllib.request.Request(
                GATEWAY_URL,
                data=json.dumps(body).encode("utf-8"),
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {GATEWAY_TOKEN}",
                },
                method="POST",
            )
            try:
                with urllib.request.urlopen(req, timeout=timeout_seconds) as response:
                    payload = json.loads(response.read().decode("utf-8"))
            except urllib.error.HTTPError as error:
                detail = error.read().decode("utf-8", errors="replace")
                raise RuntimeError(f"Gateway request failed ({error.code}): {detail}") from error
            return strip_code_fences(extract_gateway_text(payload))


        def tool_arguments_from_reply(reply_text, payload):
            stripped = strip_code_fences(reply_text)
            tool = selected_tool(payload)
            if not isinstance(tool, dict):
                return stripped

            function = tool.get("function") or {}
            params = function.get("parameters") or {}
            properties = params.get("properties") if isinstance(params, dict) else {}
            if not isinstance(properties, dict):
                properties = {}

            parsed = None
            if stripped:
                try:
                    parsed = json.loads(stripped)
                except Exception:
                    parsed = None

            if isinstance(parsed, dict):
                return json.dumps(parsed, ensure_ascii=False)

            property_names = list(properties.keys())
            if len(property_names) == 1:
                return json.dumps({property_names[0]: parsed if parsed is not None else stripped}, ensure_ascii=False)

            return json.dumps({"content": stripped}, ensure_ascii=False)


        def build_choice(payload, reply_text):
            tool = selected_tool(payload)
            if isinstance(tool, dict):
                function = tool.get("function") or {}
                return {
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": "",
                        "tool_calls": [
                            {
                                "id": f"call_{uuid.uuid4().hex}",
                                "type": "function",
                                "function": {
                                    "name": str(function.get("name") or "Response"),
                                    "arguments": tool_arguments_from_reply(reply_text, payload),
                                },
                            }
                        ],
                    },
                    "finish_reason": "tool_calls",
                }

            return {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": reply_text,
                },
                "finish_reason": "stop",
            }


        class Handler(BaseHTTPRequestHandler):
            server_version = "OpenClawCogneeShim/2.0"

            def log_message(self, fmt, *args):
                sys.stderr.write("%s - - [%s] %s\\n" % (self.address_string(), self.log_date_time_string(), fmt % args))

            def respond(self, code, payload):
                data = json.dumps(payload).encode("utf-8")
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_GET(self):
                if self.path in ("/health", "/v1/health"):
                    self.respond(200, {"ok": True, "gatewayModel": GATEWAY_MODEL, "model": DEFAULT_MODEL})
                    return
                if self.path in ("/v1/models", "/models"):
                    self.respond(200, {"object": "list", "data": [{"id": DEFAULT_MODEL, "object": "model", "owned_by": "openclaw"}]})
                    return
                self.respond(404, {"error": {"message": "Not found", "type": "not_found_error"}})

            def do_POST(self):
                if self.path not in ("/v1/chat/completions", "/chat/completions"):
                    self.respond(404, {"error": {"message": "Not found", "type": "not_found_error"}})
                    return

                try:
                    content_length = int(self.headers.get("Content-Length", "0"))
                    payload = json.loads(self.rfile.read(content_length) or b"{}")
                    if not isinstance(payload, dict):
                        raise ValueError("Expected JSON object")
                    timeout_seconds = int(payload.get("timeout", DEFAULT_TIMEOUT_SECONDS) or DEFAULT_TIMEOUT_SECONDS)
                    prompt = compile_prompt(payload)
                    reply_text = call_gateway(prompt, timeout_seconds)
                    response = {
                        "id": f"chatcmpl-{uuid.uuid4().hex}",
                        "object": "chat.completion",
                        "created": int(time.time()),
                        "model": str(payload.get("model") or DEFAULT_MODEL),
                        "choices": [build_choice(payload, reply_text)],
                        "usage": {
                            "prompt_tokens": 0,
                            "completion_tokens": 0,
                            "total_tokens": 0
                        },
                    }
                    self.respond(200, response)
                except Exception as error:
                    self.respond(500, {"error": {"message": str(error), "type": "server_error"}})


        def main():
            server = ThreadingHTTPServer((HOST, PORT), Handler)
            server.serve_forever()


        if __name__ == "__main__":
            main()
        """
    }

    private func cogneeLaunchAgentContents() -> String {
        let scriptPath = cogneeLauncherScriptURL().path
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(cogneeLaunchAgentLabel())</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(scriptPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>WorkingDirectory</key>
            <string>\(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".openclaw", isDirectory: true).path)</string>
            <key>StandardOutPath</key>
            <string>\(logDir.appendingPathComponent("cognee.log").path)</string>
            <key>StandardErrorPath</key>
            <string>\(logDir.appendingPathComponent("cognee.err").path)</string>
        </dict>
        </plist>
        """
    }

    private func writeFileIfNeeded(at url: URL, contents: String, permissions: Int) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard existing != contents else {
            return false
        }
        try? contents.write(to: url, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        return true
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func preferredModel(from ollamaListOutput: String) -> String? {
        let lines = ollamaListOutput.split(separator: "\n").map(String.init)
        guard lines.count > 1 else { return nil }
        let names = lines.dropFirst().compactMap { line -> String? in
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard let first = parts.first else { return nil }
            return String(first)
        }

        let preferred = ["qwen2.5-coder:7b", "llama3.1:8b", "kimi-k2.5"]
        for item in preferred where names.contains(item) {
            return item
        }
        return names.first
    }

    private func writeThrawnConfig() {
        let token = providerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if setupMode == .bringYourOwn, !token.isEmpty {
            _ = KeychainStore.saveProviderToken(token)
        }

        let config = OpenClawConfig(
            baseURL: "http://127.0.0.1:18789",
            model: desiredRemotePrimaryRoute(),
            token: nil,
            timeoutSeconds: 45,
            preferLocalFirst: ollamaFallbackActive && preferLocalFirst,
            alwaysRouteThroughOpenClaw: true,
            ollamaFallbackEnabled: ollamaFallbackActive,
            ollamaBaseURL: "http://127.0.0.1:11434",
            ollamaModel: selectedOllamaModel
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: configURL, options: .atomic)
        }
    }

    private func applySetupModeDefaults() {
        alwaysRouteThroughOpenClaw = true
        if setupMode == .openClawDirect || providerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            providerModel = OpenClawConfig.default.model
        }
        if !ollamaFallbackActive {
            preferLocalFirst = false
            autoInstallKimi = false
        }
    }

    private func syncOpenClawConfigForFreshSetup() async {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("openclaw.json")

        guard let data = try? Data(contentsOf: path),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return
        }

        let localIDs: [String]
        if ollamaFallbackActive {
            let installed = await installedOllamaModelIDs()
            localIDs = installed.isEmpty ? [selectedOllamaModel] : installed
            if let preferred = localIDs.first(where: { $0 == selectedOllamaModel }) ?? localIDs.first {
                selectedOllamaModel = preferred
            }

            var env = root["env"] as? [String: Any] ?? [:]
            if (env["OLLAMA_API_KEY"] as? String)?.isEmpty != false {
                env["OLLAMA_API_KEY"] = "ollama-local"
            }
            root["env"] = env

            var models = root["models"] as? [String: Any] ?? [:]
            models["mode"] = (models["mode"] as? String) ?? "merge"
            var providers = models["providers"] as? [String: Any] ?? [:]
            var ollama = providers["ollama"] as? [String: Any] ?? [:]
            ollama["baseUrl"] = "http://127.0.0.1:11434"
            ollama["api"] = "ollama"
            ollama["apiKey"] = "ollama-local"
            ollama["models"] = localIDs.map { modelID in
                [
                    "id": modelID,
                    "name": modelID,
                    "reasoning": false,
                    "input": ["text"],
                    "cost": [
                        "input": 0,
                        "output": 0,
                        "cacheRead": 0,
                        "cacheWrite": 0
                    ],
                    "contextWindow": 32768,
                    "maxTokens": 32768
                ] as [String: Any]
            }
            providers["ollama"] = ollama
            models["providers"] = providers
            root["models"] = models
        } else {
            localIDs = []
        }

        var agents = root["agents"] as? [String: Any] ?? [:]
        var defaults = agents["defaults"] as? [String: Any] ?? [:]
        var model = defaults["model"] as? [String: Any] ?? [:]
        let localRoutes = localIDs.map { "ollama/\($0)" }
        let remotePrimary = desiredRemotePrimaryRoute()
        if ollamaFallbackActive && preferLocalFirst, let primary = localRoutes.first {
            model["primary"] = primary
            var fallbacks = [remotePrimary]
            for route in localRoutes.dropFirst() where !fallbacks.contains(route) {
                fallbacks.append(route)
            }
            model["fallbacks"] = fallbacks
        } else {
            model["primary"] = remotePrimary
            model["fallbacks"] = ollamaFallbackActive ? localRoutes : []
        }
        defaults["model"] = model
        agents["defaults"] = defaults
        root["agents"] = agents

        guard let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? out.write(to: path, options: .atomic)
    }

    private func installedOllamaModelIDs() async -> [String] {
        let list = await ShellCommand.run("ollama list")
        guard list.exitCode == 0 else { return [] }
        let rows = list.stdout.split(separator: "\n").map(String.init)
        guard rows.count > 1 else { return [] }
        return rows.dropFirst().compactMap { line in
            let columns = line.split(whereSeparator: \.isWhitespace)
            guard let id = columns.first else { return nil }
            let value = String(id).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
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
        openClawHealthy = await isGatewayHealthy()

        if !openClawHealthy {
            await ChatDiagnostics.shared.log("monitor: gateway unhealthy, attempting heal")
            let heal = await ShellCommand.run("openclaw gateway start")
            if heal.exitCode != 0 {
                _ = await ShellCommand.run("openclaw gateway run --force >/tmp/junipero-openclaw.log 2>&1 &")
            }
            openClawHealthy = await isGatewayHealthy()
        }

        if ollamaFallbackActive {
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

        let cogneeSnapshot = await fetchCogneeStatus()
        if !cogneeSnapshot.launchAgentLoaded || !cogneeSnapshot.apiReachable || !cogneeSnapshot.adapterReachable {
            await ChatDiagnostics.shared.log("monitor: cognee unhealthy, attempting heal")
            await ensureCogneeService()
        } else {
            await refreshCogneeStatus(forceIndexIfNeeded: true)
        }

        if openClawHealthy {
            if cogneeHealthy {
                statusText = ollamaFallbackActive
                    ? (ollamaHealthy ? "OpenClaw + Memory healthy" : "OpenClaw healthy, Ollama recovering")
                    : "OpenClaw + Memory healthy"
            } else {
                statusText = ollamaFallbackActive
                    ? (ollamaHealthy ? "OpenClaw healthy, Memory syncing" : "OpenClaw healthy, Memory syncing")
                    : "OpenClaw healthy, Memory syncing"
            }
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
            "cogneeHealthy: \(cogneeHealthy)",
            "cogneeStatusText: \(cogneeStatusText)",
            "cogneeIndexedFiles: \(cogneeIndexedFiles)",
            "cogneeWorkspaceFiles: \(cogneeWorkspaceFiles)",
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
        let cognee = await ShellCommand.run("openclaw cognee status")
        try cognee.stdout.data(using: .utf8)?.write(to: dir.appendingPathComponent("cognee-status.txt"), options: .atomic)
        let ollama = await ShellCommand.run("ollama list")
        try ollama.stdout.data(using: .utf8)?.write(to: dir.appendingPathComponent("ollama-list.txt"), options: .atomic)

        let cogneeLog = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("cognee.log")
        if fm.fileExists(atPath: cogneeLog.path) {
            try? fm.copyItem(at: cogneeLog, to: dir.appendingPathComponent("cognee.log"))
        }

        let cogneeErr = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("cognee.err")
        if fm.fileExists(atPath: cogneeErr.path) {
            try? fm.copyItem(at: cogneeErr, to: dir.appendingPathComponent("cognee.err"))
        }

        let cogneeShimLog = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("cognee-shim.log")
        if fm.fileExists(atPath: cogneeShimLog.path) {
            try? fm.copyItem(at: cogneeShimLog, to: dir.appendingPathComponent("cognee-shim.log"))
        }

        let cogneeShimErr = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("cognee-shim.err")
        if fm.fileExists(atPath: cogneeShimErr.path) {
            try? fm.copyItem(at: cogneeShimErr, to: dir.appendingPathComponent("cognee-shim.err"))
        }
    }

    private func isGatewayHealthy() async -> Bool {
        // Use HTTP health check — instant and reliable, no CLI overhead.
        let config = GatewayWSConfig.load()
        guard let url = URL(string: "\(config.baseURL)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ok = json["ok"] as? Bool {
                return ok
            }
            return true
        } catch {
            return false
        }
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

    private func desiredRemotePrimaryRoute() -> String {
        let trimmed = providerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("ollama/") {
            return OpenClawConfig.default.model
        }
        return trimmed
    }

    private func desiredMainSessionRoute() -> String {
        if ollamaFallbackActive && preferLocalFirst {
            let local = selectedOllamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !local.isEmpty {
                return "ollama/\(local)"
            }
        }
        return desiredRemotePrimaryRoute()
    }

    private func syncMainSessionRouting() async {
        guard openClawHealthy else { return }
        let payload: [String: Any] = [
            "key": "agent:main:main",
            "model": desiredMainSessionRoute()
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
            let json = String(data: data, encoding: .utf8)
        else {
            return
        }

        let escaped = json.replacingOccurrences(of: "'", with: "'\\''")
        let patch = await ShellCommand.run("openclaw gateway call sessions.patch --json --params '\(escaped)'")
        if patch.exitCode != 0 {
            await ChatDiagnostics.shared.log("bootstrap main session patch failed stderr=\(patch.stderr) stdout=\(patch.stdout)")
        }
    }

    private func openClawLaunchAgentInstalled() -> Bool {
        let launchAgent = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("ai.openclaw.gateway.plist")
        return FileManager.default.fileExists(atPath: launchAgent.path)
    }
}
