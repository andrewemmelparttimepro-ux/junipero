import Foundation
import SwiftUI

// MARK: - Execution Abstraction Layer
//
// Central chokepoint for all computer access. Every shell command,
// file write, and process spawn flows through ExecutionService.
//
// Two backends:
//   • DirectExecutionBackend  — uses Process() (notarized DMG builds)
//   • XPCExecutionBackend     — talks to embedded helper (App Store builds)
//
// The safety toggle (AccessMode) gates everything at this layer.
// When restricted, all execution requests return a clear error.
// When unleashed, commands flow to the active backend.

// MARK: - Protocol

/// Protocol for executing commands on the host system.
protocol ExecutionBackend: Sendable {
    func execute(_ command: String) async -> ShellCommandResult
    func isAvailable() async -> Bool
}

// MARK: - Execution Service (Observable)

@MainActor
final class ExecutionService: ObservableObject {
    @Published var accessMode: AccessMode = .restricted
    @Published var backendAvailable: Bool = false
    @Published var showUnleashConfirmation: Bool = false
    @Published var commandHistory: [ExecutedCommand] = []

    private let backend: ExecutionBackend

    struct ExecutedCommand: Identifiable {
        let id = UUID()
        let timestamp: Date
        let command: String
        let result: ShellCommandResult
        let agentId: String?  // nil = user session, "r2d2" = agent heartbeat, etc.
        var durationMs: Int
    }

    init(backend: ExecutionBackend? = nil) {
        #if APPSTORE_BUILD
        self.backend = backend ?? XPCExecutionBackend()
        #else
        self.backend = backend ?? DirectExecutionBackend()
        #endif

        // Load persisted access mode
        let prefs = ThrawnPreferencesStore.load()
        self.accessMode = prefs.effectiveAccessMode
    }

    // MARK: - Central Execution Gate

    /// Execute a shell command. Returns restricted error if safety is ON.
    /// This is the ONLY way to run commands in the app.
    func run(_ command: String, agentId: String? = nil) async -> ShellCommandResult {
        guard accessMode == .unleashed else {
            return ShellCommandResult(
                exitCode: 1,
                stdout: "",
                stderr: "[RESTRICTED] Computer access is disabled. Toggle safety OFF in the console to enable full OpenClaw access."
            )
        }

        let startTime = Date()
        let result = await backend.execute(command)
        let duration = Int(Date().timeIntervalSince(startTime) * 1000)

        let entry = ExecutedCommand(
            timestamp: startTime,
            command: command,
            result: result,
            agentId: agentId,
            durationMs: duration
        )

        // Log to FlightRecorder
        FlightRecorder.logExec(
            agent: agentId,
            command: command,
            exitCode: result.exitCode,
            durationMs: duration,
            stdoutLength: result.stdout.count,
            stderrLength: result.stderr.count,
            stderrPreview: result.stderr.isEmpty ? nil : result.stderr
        )

        if result.exitCode != 0 {
            FlightRecorder.logError(
                source: "exec:\(agentId ?? "user")",
                message: "Command failed (exit \(result.exitCode)): \(String(command.prefix(200)))",
                context: ["stderr": String(result.stderr.prefix(300))]
            )
        }

        // Keep last 200 commands in history
        commandHistory.append(entry)
        if commandHistory.count > 200 {
            commandHistory.removeFirst(commandHistory.count - 200)
        }

        return result
    }

    // MARK: - Access Mode Control

    /// Request to toggle to unleashed mode. Shows confirmation dialog.
    func requestUnleash() {
        guard ThrawnPreferencesStore.load().canToggleAccess else { return }
        showUnleashConfirmation = true
    }

    /// Confirm unleash after user accepts the dialog.
    func confirmUnleash() {
        ThrawnPreferencesStore.setAccessMode(.unleashed)
        accessMode = .unleashed
        showUnleashConfirmation = false

        Task {
            backendAvailable = await backend.isAvailable()
        }
    }

    /// Return to restricted mode (immediate, no confirmation needed).
    func restrict() {
        ThrawnPreferencesStore.setAccessMode(.restricted)
        accessMode = .restricted
        showUnleashConfirmation = false
    }

    /// Toggle access mode. If going to unleashed, shows confirmation first.
    func toggleAccess() {
        if accessMode == .unleashed {
            restrict()
        } else {
            requestUnleash()
        }
    }

    // MARK: - Backend Health

    func checkBackendHealth() async {
        backendAvailable = await backend.isAvailable()
    }

    // MARK: - Sync from Preferences

    func syncFromPreferences() {
        let prefs = ThrawnPreferencesStore.load()
        accessMode = prefs.effectiveAccessMode
    }
}
