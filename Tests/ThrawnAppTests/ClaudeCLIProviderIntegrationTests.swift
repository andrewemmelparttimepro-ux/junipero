import XCTest
@testable import ThrawnApp

@MainActor
final class ClaudeCLIProviderIntegrationTests: XCTestCase {
    func testCreateAndResumeClaudeSubscriptionSession() async throws {
        guard ProcessInfo.processInfo.environment["THRAWN_RUN_LIVE_PROVIDER_TESTS"] == "1" else {
            throw XCTSkip("Set THRAWN_RUN_LIVE_PROVIDER_TESTS=1 to run live provider checks.")
        }

        let profile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Thrawn/subscription-profiles/thrawn/claude",
                isDirectory: true
            )
        let provider = ClaudeCLIProvider(
            profileID: "integration",
            stateDirectory: profile
        )
        let status = await provider.probe()
        XCTAssertEqual(status.state, .ready, status.detail)

        let sessionKey = "claude-integration-\(UUID().uuidString)"
        let options = AgentSessionOptions(
            sessionKey: sessionKey,
            agentID: "integration",
            provider: .claude,
            cwd: FileManager.default.temporaryDirectory,
            model: "sonnet",
            approvalPolicy: .untrusted,
            sandbox: .readOnly
        )
        let session = try await provider.createSession(options: options)
        let first = try await provider.runTurn(
            session: session,
            prompt: "Reply with exactly THRAWN_CLAUDE_ONE.",
            options: options
        ) { _ in }
        XCTAssertTrue(first.text.contains("THRAWN_CLAUDE_ONE"))

        let resumed = try await provider.resumeSession(
            providerSessionID: first.providerSessionID,
            options: options
        )
        let second = try await provider.runTurn(
            session: resumed,
            prompt: "Reply with only the exact token from your previous answer.",
            options: options
        ) { _ in }
        XCTAssertTrue(second.text.contains("THRAWN_CLAUDE_ONE"))
    }
}
