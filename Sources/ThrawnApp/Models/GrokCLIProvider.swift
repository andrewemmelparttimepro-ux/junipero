import Foundation

// MARK: - Grok subscription-backed provider
//
// Grok owns OAuth credentials and refresh tokens under its own CLI support
// directory. Thrawn launches the provider in headless streaming mode and stores
// only the returned session id, mirroring the Codex app-server boundary.

@MainActor
final class GrokCLIProvider: AgentProvider {
    let id: String
    var accountUpdatedHandler: (@MainActor () -> Void)?

    private let profileID: String
    private let stateDirectory: URL
    private var executablePath: String?
    private var newSessionIDs: Set<String> = []
    private var activeProcesses: [String: Process] = [:]
    private var authProcess: Process?

    init(profileID: String = "steven", stateDirectory: URL? = nil) {
        self.profileID = profileID
        self.id = "grok:\(profileID)"
        self.stateDirectory = stateDirectory
            ?? ThrawnPaths.appSupportDir
                .appendingPathComponent("subscription-profiles", isDirectory: true)
                .appendingPathComponent(profileID, isDirectory: true)
                .appendingPathComponent("grok", isDirectory: true)
    }

    func probe() async -> ProviderStatus {
        guard let executable = SubscriptionGatewayCatalog.all
            .first(where: { $0.id == "grok" })?
            .detectedExecutablePath else {
            executablePath = nil
            return .unavailable(
                providerID: id,
                detail: "Grok CLI is not installed."
            )
        }

        executablePath = executable
        let version = await Self.version(at: executable)
        let account = localAccount()
        guard account != nil else {
            return ProviderStatus(
                providerID: id,
                state: .authenticationRequired,
                executablePath: executable,
                version: version,
                account: nil,
                detail: "Grok is installed but this agent is signed out."
            )
        }

        return ProviderStatus(
            providerID: id,
            state: .ready,
            executablePath: executable,
            version: version,
            account: account,
            detail: "Grok CLI is signed in with provider-owned OAuth."
        )
    }

    func authenticate() async -> AuthInstructions {
        AuthInstructions(
            providerID: id,
            title: "Sign in to Grok",
            command: "grok login --oauth",
            detail: "Grok opens and owns the xAI OAuth flow. Thrawn never receives your password or tokens."
        )
    }

    /// Grok owns this OAuth flow and opens the browser itself.
    func beginBrowserLogin() throws {
        if authProcess?.isRunning == true { return }
        guard let executable = executablePath
            ?? SubscriptionGatewayCatalog.all.first(where: { $0.id == "grok" })?.detectedExecutablePath else {
            throw AgentRuntimeError.executableNotFound("Grok CLI is not installed.")
        }
        try FileManager.default.createDirectory(
            at: stateDirectory,
            withIntermediateDirectories: true
        )

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["login", "--oauth"]
        process.standardOutput = output
        process.standardError = output
        process.environment = providerEnvironment()
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.authProcess = nil
                self?.accountUpdatedHandler?()
            }
        }
        do {
            try process.run()
            authProcess = process
        } catch {
            throw AgentRuntimeError.processLaunchFailed(
                "Could not start Grok browser sign-in: \(error.localizedDescription)"
            )
        }
    }

    func logout() async throws {
        guard let executable = executablePath
            ?? SubscriptionGatewayCatalog.all.first(where: { $0.id == "grok" })?.detectedExecutablePath else {
            throw AgentRuntimeError.executableNotFound("Grok CLI is not installed.")
        }
        if authProcess?.isRunning == true {
            authProcess?.terminate()
        }
        authProcess = nil
        let environment = providerEnvironment()
        let result = await Task.detached(priority: .userInitiated) { () -> (Int32, String) in
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["logout"]
            process.standardOutput = output
            process.standardError = output
            process.environment = environment
            do {
                try process.run()
                process.waitUntilExit()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                return (
                    process.terminationStatus,
                    String(data: data, encoding: .utf8) ?? ""
                )
            } catch {
                return (-1, error.localizedDescription)
            }
        }.value
        guard result.0 == 0 else {
            let detail = result.1.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AgentRuntimeError.requestFailed(
                detail.isEmpty ? "Grok sign-out failed." : detail
            )
        }
        accountUpdatedHandler?()
    }

    func listModels() async throws -> [ModelDescriptor] {
        [
            ModelDescriptor(
                id: ProviderRouter.dynamicGrokModel,
                model: ProviderRouter.dynamicGrokModel,
                displayName: "Grok 4.5",
                description: "Live Grok subscription model exposed by the installed Grok CLI.",
                isDefault: true,
                hidden: false,
                defaultReasoningEffort: "high",
                supportedReasoningEfforts: [
                    .init(reasoningEffort: "low", description: "Fast"),
                    .init(reasoningEffort: "medium", description: "Balanced"),
                    .init(reasoningEffort: "high", description: "Deep"),
                ],
                serviceTiers: [],
                defaultServiceTier: nil,
                inputModalities: ["text"]
            ),
        ]
    }

    func createSession(options: AgentSessionOptions) async throws -> AgentSessionDescriptor {
        let sessionID = UUID().uuidString.lowercased()
        newSessionIDs.insert(sessionID)
        return AgentSessionDescriptor(
            providerID: id,
            sessionKey: options.sessionKey,
            providerSessionID: sessionID,
            model: options.model ?? ProviderRouter.dynamicGrokModel
        )
    }

    func resumeSession(
        providerSessionID: String,
        options: AgentSessionOptions
    ) async throws -> AgentSessionDescriptor {
        AgentSessionDescriptor(
            providerID: id,
            sessionKey: options.sessionKey,
            providerSessionID: providerSessionID,
            model: options.model ?? ProviderRouter.dynamicGrokModel
        )
    }

    func runTurn(
        session: AgentSessionDescriptor,
        prompt: String,
        options: AgentSessionOptions,
        onEvent: @escaping @MainActor (AgentEvent) -> Void
    ) async throws -> AgentRunResult {
        guard let executable = executablePath
            ?? SubscriptionGatewayCatalog.all.first(where: { $0.id == "grok" })?.detectedExecutablePath else {
            throw AgentRuntimeError.executableNotFound("Grok CLI is not installed.")
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.currentDirectoryURL = options.cwd
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = providerEnvironment()

        var arguments = [
            "--output-format", "streaming-json",
            "--permission-mode", AutonomyPolicy.grokPermissionMode(agentID: options.agentID),
            "--no-subagents",
            "--cwd", options.cwd.path,
        ]
        if let model = options.model, !model.isEmpty, model != "auto" {
            arguments += ["--model", model]
        }
        if let effort = options.reasoningEffort,
           !effort.isEmpty,
           effort != "auto" {
            arguments += ["--reasoning-effort", effort]
        }
        if let instructions = options.developerInstructions,
           !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += ["--system-prompt-override", instructions]
        }

        let isNewSession = newSessionIDs.remove(session.providerSessionID) != nil
        if !isNewSession {
            arguments += ["--resume", session.providerSessionID]
        }
        arguments += ["--single", prompt]
        process.arguments = arguments

        do {
            try FileManager.default.createDirectory(
                at: options.cwd,
                withIntermediateDirectories: true
            )
            try process.run()
        } catch {
            throw AgentRuntimeError.processLaunchFailed(
                "Could not launch Grok CLI: \(error.localizedDescription)"
            )
        }

        activeProcesses[session.providerSessionID] = process

        let outputTask = Task { @MainActor () throws -> GrokStreamSummary in
            var summary = GrokStreamSummary(
                text: "",
                model: session.model,
                providerSessionID: session.providerSessionID,
                turnID: nil
            )
            for try await line in outputPipe.fileHandleForReading.bytes.lines {
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = json["type"] as? String else {
                    continue
                }
                switch type {
                case "text":
                    if let delta = json["data"] as? String {
                        summary.text += delta
                        onEvent(.textDelta(delta))
                    }
                case "thought":
                    if let delta = json["data"] as? String {
                        onEvent(.reasoningDelta(delta))
                    }
                case "end":
                    if let sessionID = json["sessionId"] as? String {
                        summary.providerSessionID = sessionID
                    }
                    summary.turnID = json["requestId"] as? String
                    if let modelUsage = json["modelUsage"] as? [String: Any],
                       let model = modelUsage.keys.sorted().first {
                        summary.model = model
                    }
                    if let usage = json["usage"] as? [String: Any] {
                        onEvent(.usage(AgentUsageSnapshot(
                            inputTokens: Self.intValue(usage["input_tokens"]),
                            outputTokens: Self.intValue(usage["output_tokens"]),
                            totalTokens: Self.intValue(usage["total_tokens"])
                        )))
                    }
                case "error":
                    let detail = (json["data"] as? String)
                        ?? (json["message"] as? String)
                        ?? "Grok reported an unknown runtime error."
                    onEvent(.error(detail))
                default:
                    if type.localizedCaseInsensitiveContains("tool") {
                        let title = (json["name"] as? String)
                            ?? (json["toolName"] as? String)
                            ?? "Grok tool"
                        onEvent(.toolCall(AgentToolCall(
                            id: (json["id"] as? String) ?? UUID().uuidString,
                            kind: type,
                            title: title,
                            detail: json["data"] as? String,
                            status: (json["status"] as? String) ?? "running"
                        )))
                    }
                }
            }
            return summary
        }

        let errorTask = Task.detached(priority: .utility) { () -> String in
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        }
        let statusTask = Task.detached(priority: .utility) { () -> Int32 in
            process.waitUntilExit()
            return process.terminationStatus
        }

        let summary: GrokStreamSummary
        do {
            summary = try await outputTask.value
        } catch {
            process.terminate()
            activeProcesses.removeValue(forKey: session.providerSessionID)
            throw AgentRuntimeError.malformedResponse(
                "Could not read Grok's streamed response: \(error.localizedDescription)"
            )
        }
        let stderr = await errorTask.value
        let status = await statusTask.value
        activeProcesses.removeValue(forKey: session.providerSessionID)

        guard status == 0 else {
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AgentRuntimeError.turnFailed(
                detail.isEmpty
                    ? "Grok CLI exited with status \(status)."
                    : "Grok CLI failed: \(detail)"
            )
        }
        guard !summary.text.isEmpty else {
            throw AgentRuntimeError.turnFailed("Grok returned no response text.")
        }

        onEvent(.completed)
        return AgentRunResult(
            text: summary.text,
            model: summary.model,
            providerSessionID: summary.providerSessionID,
            turnID: summary.turnID
        )
    }

    func cancelSession(providerSessionID: String) async {
        guard let process = activeProcesses[providerSessionID] else { return }
        process.interrupt()
        activeProcesses.removeValue(forKey: providerSessionID)
    }

    func resolveApproval(id: String, decision: AgentApprovalDecision) throws {
        throw AgentRuntimeError.requestFailed(
            "Grok runs headlessly with provider-side non-interactive permissions; it has no pending Thrawn approval request."
        )
    }

    private static func version(at executable: String) async -> String? {
        await Task.detached(priority: .utility) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["--version"]
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }.value
    }

    private func localAccount() -> ProviderAccount? {
        let authURL = stateDirectory.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: authURL),
              !data.isEmpty,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let record = root.values.compactMap({ $0 as? [String: Any] }).first else {
            return nil
        }
        return ProviderAccount(
            authenticationMode: "grok",
            email: record["email"] as? String,
            planType: nil
        )
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private func providerEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["GROK_HOME"] = stateDirectory.standardizedFileURL.path
        return environment
    }
}

private struct GrokStreamSummary {
    var text: String
    var model: String
    var providerSessionID: String
    var turnID: String?
}
