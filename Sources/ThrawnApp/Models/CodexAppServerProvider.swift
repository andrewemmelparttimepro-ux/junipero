import Foundation

// MARK: - Codex CLI / app-server adapter

@MainActor
final class CodexAppServerProvider: AgentProvider {
    let id: String
    var approvalHandler: (@MainActor (AgentApprovalRequest) -> Void)?
    var approvalResolvedHandler: (@MainActor (String) -> Void)?
    var accountUpdatedHandler: (@MainActor () -> Void)?

    private let profileID: String
    private let stateDirectory: URL

    private struct PendingRequest {
        let method: String
        let completion: (Result<[String: Any], Error>) -> Void
    }

    private final class ActiveTurn {
        let threadID: String
        var turnID: String?
        var model: String
        let onEvent: @MainActor (AgentEvent) -> Void
        let completion: (Result<AgentRunResult, Error>) -> Void
        var finalText = ""
        var fallbackText = ""
        var itemPhases: [String: String] = [:]

        init(
            threadID: String,
            model: String,
            onEvent: @escaping @MainActor (AgentEvent) -> Void,
            completion: @escaping (Result<AgentRunResult, Error>) -> Void
        ) {
            self.threadID = threadID
            self.model = model
            self.onEvent = onEvent
            self.completion = completion
        }
    }

    private struct PendingApproval {
        let requestID: Any
        let request: AgentApprovalRequest
        let requestedPermissions: [String: Any]?
    }

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var requestSequence = 0
    private var pendingRequests: [Int: PendingRequest] = [:]
    private var requestTimeoutTasks: [Int: Task<Void, Never>] = [:]
    private var activeTurns: [String: ActiveTurn] = [:]
    private var pendingApprovals: [String: PendingApproval] = [:]
    private var cachedStatus: ProviderStatus
    private var initialized = false
    private var executablePath: String?
    private var version: String?

    init(profileID: String = "thrawn", stateDirectory: URL? = nil) {
        self.profileID = profileID
        self.id = "codex:\(profileID)"
        self.stateDirectory = stateDirectory
            ?? ThrawnPaths.appSupportDir
                .appendingPathComponent("subscription-profiles", isDirectory: true)
                .appendingPathComponent(profileID, isDirectory: true)
                .appendingPathComponent("codex", isDirectory: true)
        self.cachedStatus = ProviderStatus.unavailable(
            providerID: "codex:\(profileID)",
            detail: "Codex account profile has not been checked."
        )
    }

    deinit {
        process?.terminationHandler = nil
        process?.terminate()
    }

    func probe() async -> ProviderStatus {
        do {
            try await ensureStarted()
            let accountResult = try await request(
                method: "account/read",
                params: ["refreshToken": false]
            )
            let account = parseAccount(accountResult["account"])
            let requiresOpenAIAuth = accountResult["requiresOpenaiAuth"] as? Bool ?? true
            let state: AgentProviderConnectionState
            let detail: String
            if account != nil || !requiresOpenAIAuth {
                state = .ready
                detail = account.map { "Authenticated with \($0.displayName)." }
                    ?? "Codex app-server is ready."
            } else {
                state = .authenticationRequired
                detail = "Codex is installed but not authenticated. Run codex login."
            }

            cachedStatus = ProviderStatus(
                providerID: id,
                state: state,
                executablePath: executablePath,
                version: version,
                account: account,
                detail: detail
            )
        } catch {
            cachedStatus = ProviderStatus(
                providerID: id,
                state: .failed,
                executablePath: executablePath,
                version: version,
                account: nil,
                detail: error.localizedDescription
            )
        }
        return cachedStatus
    }

    func authenticate() async -> AuthInstructions {
        AuthInstructions(
            providerID: id,
            title: "Sign in to Codex",
            command: "codex login",
            detail: "Codex opens the provider-owned ChatGPT login flow and stores its own credentials locally. Thrawn never receives your password or tokens."
        )
    }

    /// Starts the provider-owned ChatGPT browser flow for this agent profile.
    func beginBrowserLogin() async throws -> URL {
        try await ensureStarted()
        let result = try await request(
            method: "account/login/start",
            params: [
                "type": "chatgpt",
                "useHostedLoginSuccessPage": true,
                "appBrand": "chatgpt"
            ],
            timeoutSeconds: 30
        )
        guard let rawURL = result["authUrl"] as? String,
              let url = URL(string: rawURL) else {
            throw AgentRuntimeError.malformedResponse(
                "Codex did not return a browser sign-in URL for \(profileID)."
            )
        }
        cachedStatus = ProviderStatus(
            providerID: id,
            state: .starting,
            executablePath: executablePath,
            version: version,
            account: nil,
            detail: "Waiting for ChatGPT sign-in in your browser…"
        )
        return url
    }

    /// Clears only this agent profile's provider credentials. Local threads and
    /// Thrawn conversation data remain in place for the next sign-in.
    func logout() async throws {
        try await ensureStarted()
        _ = try await request(method: "account/logout", params: [:])
        cachedStatus = ProviderStatus(
            providerID: id,
            state: .authenticationRequired,
            executablePath: executablePath,
            version: version,
            account: nil,
            detail: "Signed out. This agent's local context is retained."
        )
        accountUpdatedHandler?()
    }

    func listModels() async throws -> [ModelDescriptor] {
        try await ensureStarted()
        var models: [ModelDescriptor] = []
        var cursor: String?

        repeat {
            var params: [String: Any] = [
                "limit": 100,
                "includeHidden": false
            ]
            if let cursor {
                params["cursor"] = cursor
            }
            let result = try await request(method: "model/list", params: params)
            let rows = result["data"] as? [[String: Any]] ?? []
            models.append(contentsOf: rows.compactMap(parseModel))
            cursor = result["nextCursor"] as? String
        } while cursor != nil

        return models
    }

    func createSession(options: AgentSessionOptions) async throws -> AgentSessionDescriptor {
        try await ensureStarted()
        var params = threadConfiguration(options)
        params["serviceName"] = "thrawn"
        let result = try await request(method: "thread/start", params: params)
        return try parseSession(result: result, sessionKey: options.sessionKey)
    }

    func resumeSession(
        providerSessionID: String,
        options: AgentSessionOptions
    ) async throws -> AgentSessionDescriptor {
        try await ensureStarted()
        var params = threadConfiguration(options)
        params["threadId"] = providerSessionID
        let result = try await request(method: "thread/resume", params: params)
        return try parseSession(result: result, sessionKey: options.sessionKey)
    }

    func runTurn(
        session: AgentSessionDescriptor,
        prompt: String,
        options: AgentSessionOptions,
        onEvent: @escaping @MainActor (AgentEvent) -> Void
    ) async throws -> AgentRunResult {
        try await ensureStarted()
        guard activeTurns[session.providerSessionID] == nil else {
            throw AgentRuntimeError.turnFailed(
                "A Codex turn is already running for \(options.sessionKey)."
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            let turn = ActiveTurn(
                threadID: session.providerSessionID,
                model: session.model,
                onEvent: onEvent
            ) { result in
                continuation.resume(with: result)
            }
            activeTurns[session.providerSessionID] = turn

            Task { @MainActor [weak self, weak turn] in
                guard let self, let turn else { return }
                do {
                    var params: [String: Any] = [
                        "threadId": session.providerSessionID,
                        "input": [["type": "text", "text": prompt]],
                        "cwd": options.cwd.standardizedFileURL.path,
                        "approvalPolicy": options.approvalPolicy.rawValue
                    ]
                    if let model = options.model, !model.isEmpty {
                        params["model"] = model
                    }
                    if let effort = options.reasoningEffort, !effort.isEmpty {
                        params["effort"] = effort
                    }
                    if let serviceTier = options.serviceTier, !serviceTier.isEmpty {
                        params["serviceTier"] = serviceTier
                    }
                    let response = try await self.request(method: "turn/start", params: params)
                    if let turnObject = response["turn"] as? [String: Any] {
                        turn.turnID = turnObject["id"] as? String
                    }
                } catch {
                    self.finishTurn(
                        threadID: session.providerSessionID,
                        result: .failure(error)
                    )
                }
            }
        }
    }

    func cancelSession(providerSessionID: String) async {
        guard let active = activeTurns[providerSessionID],
              let turnID = active.turnID else {
            return
        }
        _ = try? await request(
            method: "turn/interrupt",
            params: ["threadId": providerSessionID, "turnId": turnID]
        )
    }

    func resolveApproval(id: String, decision: AgentApprovalDecision) throws {
        guard let pending = pendingApprovals.removeValue(forKey: id) else {
            throw AgentRuntimeError.requestFailed("This approval is no longer pending.")
        }
        let result: [String: Any]
        if pending.request.kind == .permissions {
            let approved = decision == .accept || decision == .acceptForSession
            result = [
                "permissions": approved ? (pending.requestedPermissions ?? [:]) : [:],
                "scope": decision == .acceptForSession ? "session" : "turn"
            ]
        } else {
            result = ["decision": decision.rawValue]
        }
        try send(["id": pending.requestID, "result": result])
    }

    // MARK: Process lifecycle

    private func ensureStarted() async throws {
        if initialized, let process, process.isRunning {
            return
        }

        let executable = try findExecutable()
        executablePath = executable.path
        version = readVersion(executable: executable)
        try FileManager.default.createDirectory(
            at: stateDirectory,
            withIntermediateDirectories: true
        )

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = stateDirectory.standardizedFileURL.path
        environment["CODEX_SQLITE_HOME"] = stateDirectory.standardizedFileURL.path
        process.environment = environment

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.consumeStdout(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.consumeStderr(data)
            }
        }
        process.terminationHandler = { [weak self] terminated in
            Task { @MainActor [weak self] in
                self?.handleTermination(status: terminated.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            throw AgentRuntimeError.processLaunchFailed(
                "Could not launch codex app-server: \(error.localizedDescription)"
            )
        }

        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting
        initialized = false

        _ = try await request(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "thrawn",
                    "title": "Thrawn",
                    "version": appVersion
                ],
                "capabilities": [
                    "experimentalApi": true
                ]
            ],
            timeoutSeconds: 15
        )
        try send(["method": "initialized", "params": [:]])
        initialized = true
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "2.1.0"
    }

    private func findExecutable() throws -> URL {
        var candidates: [String] = []
        if let override = ProcessInfo.processInfo.environment["THRAWN_CODEX_PATH"] {
            candidates.append(override)
        }
        candidates.append(contentsOf: [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ])

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                candidates.append("\(directory)/codex")
            }
        }

        for path in candidates {
            let standardized = URL(fileURLWithPath: path).standardizedFileURL
            if FileManager.default.isExecutableFile(atPath: standardized.path) {
                return standardized
            }
        }
        throw AgentRuntimeError.executableNotFound(
            "Codex CLI was not found. Install Codex or set THRAWN_CODEX_PATH."
        )
    }

    private func readVersion(executable: URL) -> String? {
        let versionProcess = Process()
        let output = Pipe()
        versionProcess.executableURL = executable
        versionProcess.arguments = ["--version"]
        versionProcess.standardOutput = output
        versionProcess.standardError = Pipe()
        do {
            try versionProcess.run()
            versionProcess.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func handleTermination(status: Int32) {
        initialized = false
        process = nil
        stdinHandle = nil
        let stderr = String(data: stderrBuffer.suffix(4_000), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = stderr.flatMap { $0.isEmpty ? nil : $0 }
            ?? "codex app-server exited with status \(status)."
        let error = AgentRuntimeError.processExited(detail)

        let pending = pendingRequests
        pendingRequests.removeAll()
        requestTimeoutTasks.values.forEach { $0.cancel() }
        requestTimeoutTasks.removeAll()
        for request in pending.values {
            request.completion(.failure(error))
        }
        for threadID in Array(activeTurns.keys) {
            finishTurn(threadID: threadID, result: .failure(error))
        }
        let approvalIDs = Array(pendingApprovals.keys)
        pendingApprovals.removeAll()
        for approvalID in approvalIDs {
            approvalResolvedHandler?(approvalID)
        }
    }

    // MARK: JSONL transport

    private func request(
        method: String,
        params: [String: Any],
        timeoutSeconds: UInt64 = 30
    ) async throws -> [String: Any] {
        requestSequence += 1
        let requestID = requestSequence

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestID] = PendingRequest(method: method) { result in
                continuation.resume(with: result)
            }
            requestTimeoutTasks[requestID] = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.failRequest(
                    id: requestID,
                    error: AgentRuntimeError.requestTimedOut(
                        "\(method) timed out after \(timeoutSeconds) seconds."
                    )
                )
            }
            do {
                try send(["method": method, "id": requestID, "params": params])
            } catch {
                failRequest(id: requestID, error: error)
            }
        }
    }

    private func send(_ object: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw AgentRuntimeError.malformedResponse("Could not encode Codex request.")
        }
        guard let stdinHandle else {
            throw AgentRuntimeError.processExited("Codex app-server is not running.")
        }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        do {
            try stdinHandle.write(contentsOf: data)
        } catch {
            throw AgentRuntimeError.processExited(
                "Could not write to Codex app-server: \(error.localizedDescription)"
            )
        }
    }

    private func consumeStdout(_ data: Data) {
        stdoutBuffer.append(data)
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer[..<newline]
            stdoutBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            do {
                let object = try JSONSerialization.jsonObject(with: Data(line))
                guard let message = object as? [String: Any] else { continue }
                handleMessage(message)
            } catch {
                FlightRecorder.logError(
                    source: "codex-app-server:decode",
                    message: "Invalid JSONL frame: \(error.localizedDescription)"
                )
            }
        }
    }

    private func consumeStderr(_ data: Data) {
        stderrBuffer.append(data)
        if stderrBuffer.count > 64_000 {
            stderrBuffer = Data(stderrBuffer.suffix(32_000))
        }
    }

    private func handleMessage(_ message: [String: Any]) {
        if let numericID = message["id"] as? Int,
           message["result"] != nil || message["error"] != nil {
            finishRequest(id: numericID, message: message)
            return
        }
        if message["id"] != nil, let method = message["method"] as? String {
            handleServerRequest(method: method, message: message)
            return
        }
        if let method = message["method"] as? String {
            handleNotification(method: method, params: message["params"] as? [String: Any] ?? [:])
        }
    }

    private func finishRequest(id: Int, message: [String: Any]) {
        guard let pending = pendingRequests.removeValue(forKey: id) else { return }
        requestTimeoutTasks.removeValue(forKey: id)?.cancel()
        if let result = message["result"] as? [String: Any] {
            pending.completion(.success(result))
            return
        }
        if message["result"] is NSNull {
            pending.completion(.success([:]))
            return
        }
        if let error = message["error"] as? [String: Any] {
            let detail = error["message"] as? String ?? "\(pending.method) failed."
            pending.completion(.failure(AgentRuntimeError.requestFailed(detail)))
            return
        }
        pending.completion(
            .failure(AgentRuntimeError.malformedResponse(
                "\(pending.method) returned an unexpected response."
            ))
        )
    }

    private func failRequest(id: Int, error: Error) {
        guard let pending = pendingRequests.removeValue(forKey: id) else { return }
        requestTimeoutTasks.removeValue(forKey: id)?.cancel()
        pending.completion(.failure(error))
    }

    // MARK: Protocol translation

    private func handleNotification(method: String, params: [String: Any]) {
        if method == "account/updated" || method == "account/login/completed" {
            accountUpdatedHandler?()
            return
        }
        if method == "serverRequest/resolved" {
            let resolvedID = params["requestId"].map { String(describing: $0) }
            let matches = pendingApprovals.filter { _, pending in
                resolvedID == String(describing: pending.requestID)
            }
            for (approvalID, _) in matches {
                pendingApprovals.removeValue(forKey: approvalID)
                approvalResolvedHandler?(approvalID)
            }
            return
        }

        let threadID = params["threadId"] as? String
            ?? (params["turn"] as? [String: Any])?["threadId"] as? String
        guard let threadID, let active = activeTurns[threadID] else {
            return
        }

        switch method {
        case "turn/started":
            if let turn = params["turn"] as? [String: Any] {
                active.turnID = turn["id"] as? String
            }

        case "item/started":
            guard let item = params["item"] as? [String: Any] else { return }
            handleItem(item, active: active, completed: false)

        case "item/completed":
            guard let item = params["item"] as? [String: Any] else { return }
            handleItem(item, active: active, completed: true)

        case "item/agentMessage/delta":
            let delta = params["delta"] as? String ?? ""
            let itemID = params["itemId"] as? String ?? ""
            let phase = active.itemPhases[itemID]
            if phase == "commentary" {
                active.onEvent(.reasoningDelta(delta))
            } else {
                active.finalText += delta
                active.onEvent(.textDelta(delta))
            }

        case "item/reasoning/summaryTextDelta", "item/reasoning/textDelta":
            if let delta = params["delta"] as? String {
                active.onEvent(.reasoningDelta(delta))
            }

        case "turn/diff/updated":
            let diff = params["diff"] as? String
            active.onEvent(
                .fileChange(AgentFileChange(
                    id: active.turnID ?? UUID().uuidString,
                    paths: [],
                    status: "inProgress",
                    diff: diff
                ))
            )

        case "thread/tokenUsage/updated":
            let usage = params["tokenUsage"] as? [String: Any]
                ?? params["usage"] as? [String: Any]
                ?? [:]
            active.onEvent(
                .usage(AgentUsageSnapshot(
                    inputTokens: integer(usage["inputTokens"]),
                    outputTokens: integer(usage["outputTokens"]),
                    totalTokens: integer(usage["totalTokens"])
                ))
            )

        case "model/rerouted":
            if let toModel = params["toModel"] as? String, !toModel.isEmpty {
                active.model = toModel
            }

        case "error":
            let errorObject = params["error"] as? [String: Any]
            let detail = errorObject?["message"] as? String ?? "Codex turn failed."
            active.onEvent(.error(detail))

        case "turn/completed":
            let turn = params["turn"] as? [String: Any] ?? [:]
            let status = turn["status"] as? String ?? "failed"
            clearApprovals(threadID: threadID)
            if status == "completed" {
                active.onEvent(.completed)
                let text = active.finalText.isEmpty ? active.fallbackText : active.finalText
                finishTurn(
                    threadID: threadID,
                    result: .success(AgentRunResult(
                        text: text,
                        model: active.model,
                        providerSessionID: threadID,
                        turnID: active.turnID
                    ))
                )
            } else if status == "interrupted" {
                finishTurn(
                    threadID: threadID,
                    result: .failure(AgentRuntimeError.turnFailed("Codex turn was canceled."))
                )
            } else {
                let errorObject = turn["error"] as? [String: Any]
                let detail = errorObject?["message"] as? String ?? "Codex turn failed."
                finishTurn(
                    threadID: threadID,
                    result: .failure(AgentRuntimeError.turnFailed(detail))
                )
            }

        default:
            break
        }
    }

    private func handleItem(
        _ item: [String: Any],
        active: ActiveTurn,
        completed: Bool
    ) {
        let type = item["type"] as? String ?? "unknown"
        let itemID = item["id"] as? String ?? UUID().uuidString
        let status = item["status"] as? String ?? (completed ? "completed" : "inProgress")

        switch type {
        case "agentMessage":
            let phase = item["phase"] as? String ?? "final_answer"
            active.itemPhases[itemID] = phase
            if completed, let text = item["text"] as? String, !text.isEmpty {
                if phase == "commentary" {
                    // Commentary remains visible as runtime activity, not the
                    // final answer Thrawn stores in its chat transcript.
                    if active.finalText.isEmpty {
                        active.fallbackText = text
                    }
                } else {
                    active.finalText = text
                }
            }

        case "commandExecution":
            let command = item["command"] as? String ?? "Command"
            let cwd = item["cwd"] as? String
            active.onEvent(
                .toolCall(AgentToolCall(
                    id: itemID,
                    kind: type,
                    title: command,
                    detail: cwd,
                    status: status
                ))
            )

        case "mcpToolCall":
            let server = item["server"] as? String ?? "MCP"
            let tool = item["tool"] as? String ?? "tool"
            active.onEvent(
                .toolCall(AgentToolCall(
                    id: itemID,
                    kind: type,
                    title: "\(server) · \(tool)",
                    detail: prettyJSON(item["arguments"]),
                    status: status
                ))
            )

        case "dynamicToolCall", "collabToolCall", "webSearch":
            let title = item["tool"] as? String
                ?? item["query"] as? String
                ?? type
            active.onEvent(
                .toolCall(AgentToolCall(
                    id: itemID,
                    kind: type,
                    title: title,
                    detail: nil,
                    status: status
                ))
            )

        case "fileChange":
            let changes = item["changes"] as? [[String: Any]] ?? []
            let paths = changes.compactMap { $0["path"] as? String }
            let diff = changes.compactMap { $0["diff"] as? String }
                .joined(separator: "\n")
            active.onEvent(
                .fileChange(AgentFileChange(
                    id: itemID,
                    paths: paths,
                    status: status,
                    diff: diff.isEmpty ? nil : diff
                ))
            )

        default:
            break
        }
    }

    private func handleServerRequest(method: String, message: [String: Any]) {
        guard let requestID = message["id"] else { return }
        let params = message["params"] as? [String: Any] ?? [:]
        let kind: AgentApprovalKind
        let title: String
        let detail: String

        switch method {
        case "item/commandExecution/requestApproval":
            kind = .command
            title = params["command"] as? String ?? "Approve command"
            let reason = params["reason"] as? String
            let network = params["networkApprovalContext"] as? [String: Any]
            if let host = network?["host"] as? String {
                let proto = network?["protocol"] as? String ?? "network"
                detail = reason ?? "Allow \(proto) access to \(host)."
            } else {
                detail = reason ?? "Codex requests permission to run this command."
            }

        case "item/fileChange/requestApproval":
            kind = .fileChange
            title = "Approve file changes"
            detail = params["reason"] as? String
                ?? "Codex requests permission to apply file changes."

        case "item/permissions/requestApproval":
            kind = .permissions
            title = "Approve additional permissions"
            detail = params["reason"] as? String
                ?? "Codex requests additional runtime permissions."

        default:
            // Unknown server requests fail closed instead of hanging the agent.
            try? send(["id": requestID, "error": [
                "code": -32601,
                "message": "Thrawn does not support \(method) yet."
            ]])
            return
        }

        let approvalID = "\(params["threadId"] as? String ?? "thread"):\(params["approvalId"] as? String ?? params["itemId"] as? String ?? UUID().uuidString):\(method)"
        let available = (params["availableDecisions"] as? [Any])?
            .compactMap { $0 as? String }
            ?? ["accept", "acceptForSession", "decline", "cancel"]
        let approval = AgentApprovalRequest(
            id: approvalID,
            providerID: id,
            kind: kind,
            threadID: params["threadId"] as? String ?? "",
            turnID: params["turnId"] as? String,
            itemID: params["itemId"] as? String,
            title: title,
            detail: detail,
            cwd: params["cwd"] as? String,
            availableDecisions: available,
            createdAt: Date()
        )
        pendingApprovals[approvalID] = PendingApproval(
            requestID: requestID,
            request: approval,
            requestedPermissions: params["permissions"] as? [String: Any]
        )
        activeTurns[approval.threadID]?.onEvent(.approvalRequired(approval))
        approvalHandler?(approval)
    }

    private func finishTurn(
        threadID: String,
        result: Result<AgentRunResult, Error>
    ) {
        guard let active = activeTurns.removeValue(forKey: threadID) else { return }
        active.completion(result)
    }

    private func clearApprovals(threadID: String) {
        let approvalIDs = pendingApprovals.compactMap { approvalID, pending in
            pending.request.threadID == threadID ? approvalID : nil
        }
        for approvalID in approvalIDs {
            pendingApprovals.removeValue(forKey: approvalID)
            approvalResolvedHandler?(approvalID)
        }
    }

    // MARK: Parsing

    private func threadConfiguration(_ options: AgentSessionOptions) -> [String: Any] {
        var params: [String: Any] = [
            "cwd": options.cwd.standardizedFileURL.path,
            "approvalPolicy": options.approvalPolicy.rawValue,
            "sandbox": options.sandbox.rawValue
        ]
        if let developerInstructions = options.developerInstructions,
           !developerInstructions.isEmpty {
            params["developerInstructions"] = developerInstructions
        }
        if let model = options.model, !model.isEmpty {
            params["model"] = model
        }
        if let serviceTier = options.serviceTier, !serviceTier.isEmpty {
            params["serviceTier"] = serviceTier
        }
        return params
    }

    private func parseSession(
        result: [String: Any],
        sessionKey: String
    ) throws -> AgentSessionDescriptor {
        guard let thread = result["thread"] as? [String: Any],
              let threadID = thread["id"] as? String else {
            throw AgentRuntimeError.malformedResponse(
                "Codex did not return a thread id for \(sessionKey)."
            )
        }
        let model = result["model"] as? String
            ?? thread["model"] as? String
            ?? "Codex"
        return AgentSessionDescriptor(
            providerID: id,
            sessionKey: sessionKey,
            providerSessionID: threadID,
            model: model
        )
    }

    private func parseAccount(_ raw: Any?) -> ProviderAccount? {
        guard let object = raw as? [String: Any],
              let type = object["type"] as? String else {
            return nil
        }
        switch type {
        case "chatgpt":
            return ProviderAccount(
                authenticationMode: type,
                email: object["email"] as? String,
                planType: object["planType"] as? String
            )
        case "apiKey":
            return ProviderAccount(
                authenticationMode: type,
                email: nil,
                planType: nil
            )
        default:
            return ProviderAccount(
                authenticationMode: type,
                email: nil,
                planType: nil
            )
        }
    }

    private func parseModel(_ object: [String: Any]) -> ModelDescriptor? {
        guard let id = object["id"] as? String,
              let model = object["model"] as? String else {
            return nil
        }
        let reasoningRows = object["supportedReasoningEfforts"] as? [[String: Any]] ?? []
        let reasoning = reasoningRows.compactMap { row -> ModelDescriptor.ReasoningOption? in
            guard let effort = row["reasoningEffort"] as? String else { return nil }
            return ModelDescriptor.ReasoningOption(
                reasoningEffort: effort,
                description: row["description"] as? String ?? ""
            )
        }
        let tierRows = object["serviceTiers"] as? [[String: Any]] ?? []
        let tiers = tierRows.compactMap { row -> ModelDescriptor.ServiceTier? in
            guard let id = row["id"] as? String else { return nil }
            return ModelDescriptor.ServiceTier(
                id: id,
                name: row["name"] as? String ?? id,
                description: row["description"] as? String ?? ""
            )
        }
        return ModelDescriptor(
            id: id,
            model: model,
            displayName: object["displayName"] as? String ?? model,
            description: object["description"] as? String ?? "",
            isDefault: object["isDefault"] as? Bool ?? false,
            hidden: object["hidden"] as? Bool ?? false,
            defaultReasoningEffort: object["defaultReasoningEffort"] as? String ?? "medium",
            supportedReasoningEfforts: reasoning,
            serviceTiers: tiers,
            defaultServiceTier: object["defaultServiceTier"] as? String,
            inputModalities: object["inputModalities"] as? [String] ?? ["text", "image"]
        )
    }

    private func integer(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private func prettyJSON(_ raw: Any?) -> String? {
        guard let raw, JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(
                withJSONObject: raw,
                options: [.prettyPrinted, .sortedKeys]
              ) else {
            return raw.map { String(describing: $0) }
        }
        return String(data: data, encoding: .utf8)
    }
}
