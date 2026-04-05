import Foundation

// MARK: - Shell Command Result

struct ShellCommandResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }

    var isRestricted: Bool {
        stderr.hasPrefix("[RESTRICTED]")
    }
}

// MARK: - Direct Execution Backend
//
// Uses Process() to run shell commands directly.
// Used for notarized DMG distribution (non-App-Store builds).
// For App Store builds, XPCExecutionBackend talks to the embedded helper instead.

final class DirectExecutionBackend: ExecutionBackend {
    func isAvailable() async -> Bool {
        // Always available when running outside the sandbox
        return FileManager.default.isExecutableFile(atPath: "/bin/zsh")
    }

    func execute(_ command: String) async -> ShellCommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", command]

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()

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
                    continuation.resume(returning: ShellCommandResult(
                        exitCode: process.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    ))
                } catch {
                    continuation.resume(returning: ShellCommandResult(
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
    /// Direct shell execution — bypasses the safety toggle.
    /// Legacy callers only. New code must use ExecutionService.run().
    static func run(_ command: String) async -> ShellCommandResult {
        await DirectExecutionBackend().execute(command)
    }
}
