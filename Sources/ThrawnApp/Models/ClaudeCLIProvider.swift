import Foundation

// MARK: - Claude subscription-backed provider
//
// Claude owns OAuth credentials, account state, and conversation transcripts.
// CLAUDE_CONFIG_DIR gives every Thrawn agent an isolated provider profile while
// Thrawn stores only the provider session id needed to resume that context.

@MainActor
final class ClaudeCLIProvider: AgentProvider {
    let id: String
    var accountUpdatedHandler: (@MainActor () -> Void)?

    private let profileID: String
    private let stateDirectory: URL
    private var executablePath: String?
    private var newSessionIDs: Set<String> = []
    private var activeProcesses: [String: Process] = [:]
    private var authProcess: Process?

    init(profileID: String = "thrawn", stateDirectory: URL? = nil) {
        self.profileID = profileID
        self.id = "claude:\(profileID)"
        self.stateDirectory = stateDirectory
            ?? ThrawnPaths.appSupportDir
                .appendingPathComponent("subscription-profiles", isDirectory: true)
                .appendingPathComponent(profileID, isDirectory: true)
                .appendingPathComponent("claude", isDirectory: true)
    }

    func probe() async -> ProviderStatus {
        guard let executable = SubscriptionGatewayCatalog.all
            .first(where: { $0.id == "claude" })?
            .detectedExecutablePath else {
            executablePath = nil
            return .unavailable(
                providerID: id,
                detail: "Claude Code CLI is not installed."
            )
        }

        executablePath = executable
        let version = await Self.version(at: executable)
        let account = await accountStatus(executable: executable)
        guard let account else {
            return ProviderStatus(
                providerID: id,
                state: .authenticationRequired,
                executablePath: executable,
                version: version,
                account: nil,
                detail: "Claude is installed but this agent is signed out."
            )
        }

        return ProviderStatus(
            providerID: id,
            state: .ready,
            executablePath: executable,
            version: version,
            account: account,
            detail: "Claude Code is signed in with provider-owned OAuth."
        )
    }

    func authenticate() async -> AuthInstructions {
        AuthInstructions(
            providerID: id,
            title: "Sign in to Claude",
            command: "claude auth login --claudeai",
            detail: "Claude opens and owns the Anthropic OAuth flow. Thrawn never receives your password or tokens."
        )
    }

    func beginBrowserLogin() throws {
        if authProcess?.isRunning == true { return }
        guard let executable = executablePath
            ?? SubscriptionGatewayCatalog.all.first(where: { $0.id == "claude" })?.detectedExecutablePath else {
            throw AgentRuntimeError.executableNotFound("Claude Code CLI is not installed.")
        }
        try FileManager.default.createDirectory(
            at: stateDirectory,
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["auth", "login", "--claudeai"]
        // Login output is diagnostic gold — a failed or device-code login is
        // invisible when stdout goes to the null device. Drain both streams
        // and record them on termination.
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        let loginOutput = LockedBuffer()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            loginOutput.append(handle.availableData)
        }
        process.environment = providerEnvironment()
        process.terminationHandler = { [weak self] finished in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            let text = loginOutput.tailText(4_000)
            Task { @MainActor [weak self] in
                if finished.terminationStatus != 0 || !text.isEmpty {
                    FlightRecorder.logEvent(
                        category: "auth",
                        action: "claude-login-\(finished.terminationStatus == 0 ? "done" : "failed")",
                        detail: String(text.prefix(300))
                    )
                }
                self?.authProcess = nil
                self?.accountUpdatedHandler?()
            }
        }
        do {
            try process.run()
            authProcess = process
        } catch {
            throw AgentRuntimeError.processLaunchFailed(
                "Could not start Claude browser sign-in: \(error.localizedDescription)"
            )
        }
    }

    func logout() async throws {
        guard let executable = executablePath
            ?? SubscriptionGatewayCatalog.all.first(where: { $0.id == "claude" })?.detectedExecutablePath else {
            throw AgentRuntimeError.executableNotFound("Claude Code CLI is not installed.")
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
            process.arguments = ["auth", "logout"]
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
                detail.isEmpty ? "Claude sign-out failed." : detail
            )
        }
        accountUpdatedHandler?()
    }

    func listModels() async throws -> [ModelDescriptor] {
        let efforts: [ModelDescriptor.ReasoningOption] = [
            .init(reasoningEffort: "low", description: "Fast"),
            .init(reasoningEffort: "medium", description: "Balanced"),
            .init(reasoningEffort: "high", description: "Deep"),
            .init(reasoningEffort: "xhigh", description: "Very deep"),
            .init(reasoningEffort: "max", description: "Maximum"),
        ]
        return [
            ModelDescriptor(
                id: ProviderRouter.dynamicClaudeModel,
                model: ProviderRouter.dynamicClaudeModel,
                displayName: "Claude account default",
                description: "Uses the current default model available to this Claude subscription.",
                isDefault: true,
                hidden: false,
                defaultReasoningEffort: "high",
                supportedReasoningEfforts: efforts,
                serviceTiers: [],
                defaultServiceTier: nil,
                inputModalities: ["text"]
            ),
            ModelDescriptor(
                id: "sonnet",
                model: "sonnet",
                displayName: "Claude Sonnet",
                description: "Claude Code's current Sonnet subscription alias.",
                isDefault: false,
                hidden: false,
                defaultReasoningEffort: "high",
                supportedReasoningEfforts: efforts,
                serviceTiers: [],
                defaultServiceTier: nil,
                inputModalities: ["text"]
            ),
            ModelDescriptor(
                id: "opus",
                model: "opus",
                displayName: "Claude Opus",
                description: "Claude Code's current Opus subscription alias.",
                isDefault: false,
                hidden: false,
                defaultReasoningEffort: "high",
                supportedReasoningEfforts: efforts,
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
            model: options.model ?? ProviderRouter.dynamicClaudeModel
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
            model: options.model ?? ProviderRouter.dynamicClaudeModel
        )
    }

    func runTurn(
        session: AgentSessionDescriptor,
        prompt: String,
        options: AgentSessionOptions,
        onEvent: @escaping @MainActor (AgentEvent) -> Void
    ) async throws -> AgentRunResult {
        guard let executable = executablePath
            ?? SubscriptionGatewayCatalog.all.first(where: { $0.id == "claude" })?.detectedExecutablePath else {
            throw AgentRuntimeError.executableNotFound("Claude Code CLI is not installed.")
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
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--permission-mode", permissionMode(for: options.approvalPolicy),
        ]
        if options.sandbox == .readOnly {
            arguments += ["--tools", "Read,Glob,Grep,WebFetch,WebSearch"]
        }
        if let model = options.model, !model.isEmpty, model != "auto" {
            arguments += ["--model", model]
        }
        if let effort = options.reasoningEffort,
           !effort.isEmpty,
           effort != "auto" {
            arguments += ["--effort", effort]
        }
        if let instructions = options.developerInstructions,
           !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += ["--append-system-prompt", instructions]
        }

        let isNewSession = newSessionIDs.remove(session.providerSessionID) != nil
        if isNewSession {
            arguments += ["--session-id", session.providerSessionID]
        } else {
            arguments += ["--resume", session.providerSessionID]
        }
        arguments.append(prompt)
        process.arguments = arguments

        do {
            try FileManager.default.createDirectory(
                at: options.cwd,
                withIntermediateDirectories: true
            )
            try process.run()
        } catch {
            throw AgentRuntimeError.processLaunchFailed(
                "Could not launch Claude Code: \(error.localizedDescription)"
            )
        }

        activeProcesses[session.providerSessionID] = process

        let outputTask = Task { @MainActor () throws -> ClaudeStreamSummary in
            var summary = ClaudeStreamSummary(
                text: "",
                model: session.model,
                providerSessionID: session.providerSessionID,
                turnID: nil,
                error: nil
            )
            for try await line in outputPipe.fileHandleForReading.bytes.lines {
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = json["type"] as? String else {
                    continue
                }

                switch type {
                case "system":
                    if let sessionID = json["session_id"] as? String {
                        summary.providerSessionID = sessionID
                    }
                    if let model = json["model"] as? String {
                        summary.model = model
                    }
                case "assistant":
                    guard let message = json["message"] as? [String: Any] else { continue }
                    if let model = message["model"] as? String {
                        summary.model = model
                    }
                    if let requestID = json["request_id"] as? String {
                        summary.turnID = requestID
                    }
                    if let usage = message["usage"] as? [String: Any] {
                        onEvent(.usage(Self.usageSnapshot(usage)))
                    }
                    guard let content = message["content"] as? [[String: Any]] else { continue }
                    for block in content {
                        switch block["type"] as? String {
                        case "text":
                            if let text = block["text"] as? String {
                                summary.text += text
                                onEvent(.textDelta(text))
                            }
                        case "thinking":
                            if let thinking = block["thinking"] as? String {
                                onEvent(.reasoningDelta(thinking))
                            }
                        case "tool_use":
                            let detail = Self.jsonString(block["input"])
                            onEvent(.toolCall(AgentToolCall(
                                id: (block["id"] as? String) ?? UUID().uuidString,
                                kind: "tool_use",
                                title: (block["name"] as? String) ?? "Claude tool",
                                detail: detail,
                                status: "running"
                            )))
                        default:
                            continue
                        }
                    }
                case "result":
                    if let sessionID = json["session_id"] as? String {
                        summary.providerSessionID = sessionID
                    }
                    if let result = json["result"] as? String, summary.text.isEmpty {
                        summary.text = result
                        onEvent(.textDelta(result))
                    }
                    if let usage = json["usage"] as? [String: Any] {
                        onEvent(.usage(Self.usageSnapshot(usage)))
                    }
                    if json["is_error"] as? Bool == true {
                        summary.error = (json["result"] as? String)
                            ?? (json["subtype"] as? String)
                            ?? "Claude reported an unknown runtime error."
                    }
                default:
                    continue
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

        let summary: ClaudeStreamSummary
        do {
            summary = try await outputTask.value
        } catch {
            process.terminate()
            activeProcesses.removeValue(forKey: session.providerSessionID)
            throw AgentRuntimeError.malformedResponse(
                "Could not read Claude's streamed response: \(error.localizedDescription)"
            )
        }
        let stderr = await errorTask.value
        let status = await statusTask.value
        activeProcesses.removeValue(forKey: session.providerSessionID)

        if let providerError = summary.error {
            onEvent(.error(providerError))
            throw AgentRuntimeError.turnFailed(providerError)
        }
        guard status == 0 else {
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AgentRuntimeError.turnFailed(
                detail.isEmpty
                    ? "Claude Code exited with status \(status)."
                    : "Claude Code failed: \(detail)"
            )
        }
        guard !summary.text.isEmpty else {
            throw AgentRuntimeError.turnFailed("Claude returned no response text.")
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
            "Claude Code runs headlessly with its provider permission mode; it has no pending Thrawn approval request."
        )
    }

    private func accountStatus(executable: String) async -> ProviderAccount? {
        let environment = providerEnvironment()
        return await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["auth", "status"]
            process.standardOutput = output
            process.standardError = output
            process.environment = environment
            do {
                try process.run()
                process.waitUntilExit()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      root["loggedIn"] as? Bool == true else {
                    return nil
                }
                return ProviderAccount(
                    authenticationMode: "claude",
                    email: root["email"] as? String,
                    planType: root["subscriptionType"] as? String
                )
            } catch {
                return nil
            }
        }.value
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

    private static func usageSnapshot(_ usage: [String: Any]) -> AgentUsageSnapshot {
        let input = intValue(usage["input_tokens"])
        let output = intValue(usage["output_tokens"])
        return AgentUsageSnapshot(
            inputTokens: input,
            outputTokens: output,
            totalTokens: {
                guard let input, let output else { return nil }
                return input + output
            }()
        )
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func jsonString(_ value: Any?) -> String? {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func permissionMode(
        for approvalPolicy: AgentRuntimeApprovalPolicy
    ) -> String {
        switch approvalPolicy {
        case .untrusted:
            return "manual"
        case .onRequest:
            return "acceptEdits"
        case .never:
            return "dontAsk"
        }
    }

    private func providerEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["CLAUDE_CONFIG_DIR"] = stateDirectory.standardizedFileURL.path
        return environment
    }
}

private struct ClaudeStreamSummary {
    var text: String
    var model: String
    var providerSessionID: String
    var turnID: String?
    var error: String?
}
