import Foundation

struct ShellCommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum ShellCommand {
    /// Runs a shell command without blocking Swift's cooperative thread pool.
    ///
    /// Uses GCD (DispatchQueue.global) instead of Task.detached so that
    /// blocking `waitUntilExit()` calls don't starve the async executor.
    /// Also reads stdout/stderr concurrently to prevent pipe-buffer deadlocks
    /// on large outputs (e.g. chat.history with many messages).
    static func run(_ command: String) async -> ShellCommandResult {
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
