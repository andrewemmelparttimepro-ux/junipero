import Foundation

// MARK: - Shell Command Result

struct ShellCommandResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }

    var isRestricted: Bool {
        false
    }

    /// Special exit code returned when the watchdog killed the process.
    /// Picked to be distinguishable from normal exit codes (0-255) and
    /// from kill signals (124 is the canonical "timeout" exit code from
    /// GNU coreutils' `timeout` command).
    static let timeoutExitCode: Int32 = 124
}

// MARK: - Command Safety Policy

/// Blocks automated Keychain reads that return secret values and can produce a
/// password dialog for every item in the login keychain. Metadata-only checks,
/// including codesigning identity discovery, remain available.
enum ShellCommandSafety {
    static let blockedExitCode: Int32 = 77

    private static let blockedPatterns = [
        #"(?i)(?:^|[\s;&|()`])(?:command\s+)?(?:/usr/bin/)?security\s+dump-keychain\b[^\n|;&]*\s-d(?:\s|$)"#,
        #"(?i)(?:^|[\s;&|()`])(?:command\s+)?(?:/usr/bin/)?security\s+find-(?:generic|internet)-password\b[^\n|;&]*\s-w(?:\s|$)"#,
    ]

    static func blockReason(for command: String) -> String? {
        guard blockedPatterns.contains(where: {
            command.range(of: $0, options: .regularExpression) != nil
        }) else {
            return nil
        }

        return "[BLOCKED] Automated bulk decrypted Keychain dumps and password-value reads are disabled. Use non-secret metadata, an existing environment source, or ask Andrew for the exact credential workflow."
    }
}

// MARK: - Direct Execution Backend
//
// Uses Process() to run shell commands directly.
// Used for notarized DMG distribution (non-App-Store builds).
// For App Store builds, XPCExecutionBackend talks to the embedded helper instead.
//
// Reliability rule (per ~/Desktop/memory/feedback_reliability_first.md):
// commands MUST NOT run forever. The agent's tool-loop watchdog is 5 minutes,
// so individual shell commands need a slightly tighter cap so the watchdog
// doesn't bite first (which would leave the process running, leaking).

final class DirectExecutionBackend: ExecutionBackend {
    /// Default per-command timeout. Tuned to be tighter than the
    /// AgentScheduler.toolRoundWatchdogSeconds (300s) so shell-level cleanup
    /// happens before the round-level watchdog.
    static let defaultTimeoutSeconds: TimeInterval = 240  // 4 minutes

    private let timeoutSeconds: TimeInterval

    init(timeoutSeconds: TimeInterval = DirectExecutionBackend.defaultTimeoutSeconds) {
        self.timeoutSeconds = timeoutSeconds
    }

    func isAvailable() async -> Bool {
        // Always available when running outside the sandbox
        return FileManager.default.isExecutableFile(atPath: "/bin/zsh")
    }

    func execute(_ command: String) async -> ShellCommandResult {
        let timeout = self.timeoutSeconds
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", command]

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                // Single-resume guard so the timeout watchdog and the normal
                // wait-loop can't both resume the continuation.
                let resumeLock = NSLock()
                var resumed = false
                let resumeOnce: (ShellCommandResult) -> Void = { result in
                    resumeLock.lock()
                    let alreadyResumed = resumed
                    resumed = true
                    resumeLock.unlock()
                    if !alreadyResumed {
                        continuation.resume(returning: result)
                    }
                }

                do {
                    try process.run()

                    // Watchdog: if the process is still alive after `timeout`
                    // seconds, kill it (and the whole process group via
                    // SIGTERM → SIGKILL escalation). This prevents runaway
                    // commands like `tail -f`, `sleep 1d`, or hung curl from
                    // blocking the heartbeat AND leaking processes.
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak process] in
                        guard let process, process.isRunning else { return }
                        // Try graceful first
                        process.terminate()
                        // Hard kill after 2s grace period if still alive
                        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [weak process] in
                            guard let process, process.isRunning else { return }
                            kill(process.processIdentifier, SIGKILL)
                        }
                        // Resume the continuation immediately with a clear
                        // timeout error — don't wait for the kill to complete.
                        resumeOnce(ShellCommandResult(
                            exitCode: ShellCommandResult.timeoutExitCode,
                            stdout: "",
                            stderr: "[TIMEOUT] Command exceeded \(Int(timeout))s and was killed. Command: \(String(command.prefix(200)))"
                        ))
                    }

                    // Read both pipes concurrently on GCD threads to avoid
                    // pipe-buffer deadlock (64 KB default on macOS).
                    var outData = Data()
                    var errData = Data()
                    let group = DispatchGroup()

                    group.enter()
                    DispatchQueue.global(qos: .utility).async {
                        outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.enter()
                    DispatchQueue.global(qos: .utility).async {
                        errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }

                    group.wait()
                    process.waitUntilExit()

                    let stdout = String(data: outData, encoding: .utf8) ?? ""
                    let stderr = String(data: errData, encoding: .utf8) ?? ""
                    resumeOnce(ShellCommandResult(
                        exitCode: process.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    ))
                } catch {
                    resumeOnce(ShellCommandResult(
                        exitCode: 1,
                        stdout: "",
                        stderr: "Failed to run command: \(error.localizedDescription)"
                    ))
                }
            }
        }
    }
}

// MARK: - Legacy Bridge
//
// Maintains backward compatibility for existing callers that use
// ShellCommand.run() directly (GatewayWSClient, etc.).
// All new code should go through ExecutionService instead.

enum ShellCommand {
    /// Direct shell execution for legacy callers.
    static func run(_ command: String) async -> ShellCommandResult {
        if let reason = ShellCommandSafety.blockReason(for: command) {
            return ShellCommandResult(
                exitCode: ShellCommandSafety.blockedExitCode,
                stdout: "",
                stderr: reason
            )
        }
        return await DirectExecutionBackend().execute(command)
    }
}
