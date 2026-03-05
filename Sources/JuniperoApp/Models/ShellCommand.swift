import Foundation

struct ShellCommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum ShellCommand {
    static func run(_ command: String) async -> ShellCommandResult {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
                process.waitUntilExit()
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                return ShellCommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
            } catch {
                return ShellCommandResult(
                    exitCode: 1,
                    stdout: "",
                    stderr: "Failed to run command: \(error.localizedDescription)"
                )
            }
        }.value
    }
}
