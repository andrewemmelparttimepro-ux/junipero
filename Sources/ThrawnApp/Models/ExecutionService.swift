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
// Thrawn runs in full-operation mode by default. AccessMode remains only for
// legacy preference decoding and stable call sites.

// MARK: - Protocol

/// Protocol for executing commands on the host system.
protocol ExecutionBackend: Sendable {
    func execute(_ command: String) async -> ShellCommandResult
    func isAvailable() async -> Bool
}

// MARK: - Execution Service (Observable)

@MainActor
final class ExecutionService: ObservableObject {
    @Published var accessMode: AccessMode = .fullOperation
    @Published var backendAvailable: Bool = false
    @Published var commandHistory: [ExecutedCommand] = []

    private let backend: ExecutionBackend

    struct ExecutedCommand: Identifiable {
        let id = UUID()
        let timestamp: Date
        let command: String
        let result: ShellCommandResult
        let agentId: String?  // nil = user session, otherwise the V2 agent ID.
        var durationMs: Int
    }

    init(backend: ExecutionBackend? = nil) {
        #if APPSTORE_BUILD
        self.backend = backend ?? XPCExecutionBackend()
        #else
        self.backend = backend ?? DirectExecutionBackend()
        #endif

        ThrawnPreferencesStore.setAccessMode(.fullOperation)
        self.accessMode = .fullOperation
    }

    // MARK: - Central Execution Gate

    /// Execute a shell command. This is the normal tool path for Thrawn and agents.
    func run(_ command: String, agentId: String? = nil) async -> ShellCommandResult {
        let startTime = Date()
        let result: ShellCommandResult
        if let reason = ShellCommandSafety.blockReason(for: command) {
            result = ShellCommandResult(
                exitCode: ShellCommandSafety.blockedExitCode,
                stdout: "",
                stderr: reason
            )
        } else {
            result = await backend.execute(command)
        }
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

    // MARK: - Backend Health

    func checkBackendHealth() async {
        backendAvailable = await backend.isAvailable()
    }

    // MARK: - Sync from Preferences

    func syncFromPreferences() {
        accessMode = .fullOperation
    }
}
