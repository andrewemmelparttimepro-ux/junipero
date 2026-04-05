import Foundation

// MARK: - XPC Execution Backend (App Store Phase 2)
//
// Communicates with ThrawnHelper — an embedded LaunchAgent installed
// via SMAppService — to execute shell commands outside the sandbox.
//
// This is the Apple-approved pattern for App Store developer tools.
// The helper is embedded in the app bundle at:
//   Contents/Library/LoginItems/ThrawnHelper.app
//
// Phase 2 implementation. Currently returns a stub response directing
// users to use the direct-distribution build for full access.

final class XPCExecutionBackend: ExecutionBackend {
    // TODO: Phase 2 — implement NSXPCConnection to ThrawnHelper
    // private var connection: NSXPCConnection?

    func isAvailable() async -> Bool {
        #if APPSTORE_BUILD
        // TODO: Check if ThrawnHelper is registered via SMAppService
        // and responding to XPC pings
        return false
        #else
        return false
        #endif
    }

    func execute(_ command: String) async -> ShellCommandResult {
        // Phase 2: Send command to helper via XPC, await result
        // For now, return a clear message about the limitation
        return ShellCommandResult(
            exitCode: 1,
            stdout: "",
            stderr: "[APP STORE BUILD] Shell execution requires the ThrawnHelper service. This feature is coming in a future update. Use the direct-download build for full computer access."
        )
    }

    /// Install the helper tool via SMAppService.
    /// Called when user first enables unleashed mode on an App Store build.
    func installHelper() async throws {
        // Phase 2: Register helper via SMAppService
        // SMAppService.loginItem(identifier: "com.thrawn.helper").register()
        fatalError("XPC helper installation is not yet implemented. Shipping in Phase 2.")
    }
}
