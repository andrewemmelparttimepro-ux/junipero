import Foundation
import XCTest
@testable import ThrawnApp

final class CodexAppServerProviderIntegrationTests: XCTestCase {
    @MainActor
    func testLiveIsolatedAccountCreateAndResumeWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["THRAWN_RUN_LIVE_PROVIDER_TESTS"] == "1" else {
            throw XCTSkip("Set THRAWN_RUN_LIVE_PROVIDER_TESTS=1 to exercise the signed-in OpenAI subscription.")
        }

        let sourceAuth = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard FileManager.default.fileExists(atPath: sourceAuth.path) else {
            throw XCTSkip("The current Codex account is not signed in.")
        }

        let profile = FileManager.default.temporaryDirectory
            .appendingPathComponent("thrawn-codex-profile-test-\(UUID().uuidString)")
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("thrawn-codex-workspace-test-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: profile)
            try? FileManager.default.removeItem(at: workspace)
        }
        try FileManager.default.createDirectory(
            at: profile,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: sourceAuth,
            to: profile.appendingPathComponent("auth.json")
        )
        try Data("""
        cli_auth_credentials_store = "file"

        [history]
        persistence = "save-all"
        """.utf8).write(to: profile.appendingPathComponent("config.toml"))

        let provider = CodexAppServerProvider(
            profileID: "integration-thrawn",
            stateDirectory: profile
        )
        let status = await provider.probe()
        XCTAssertEqual(status.state, .ready, status.detail)

        let options = AgentSessionOptions(
            sessionKey: "integration:codex",
            agentID: "thrawn",
            provider: .codex,
            cwd: workspace,
            developerInstructions: "Return only the exact requested text. Do not use tools.",
            model: nil,
            reasoningEffort: "low",
            approvalPolicy: .never,
            sandbox: .readOnly
        )
        let session = try await provider.createSession(options: options)
        let result = try await provider.runTurn(
            session: session,
            prompt: "Reply exactly: THRAWN_CODEX_SWIFT_OK",
            options: options
        ) { _ in }
        XCTAssertEqual(
            result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            "THRAWN_CODEX_SWIFT_OK"
        )

        let resumed = try await provider.resumeSession(
            providerSessionID: result.providerSessionID,
            options: options
        )
        let followUp = try await provider.runTurn(
            session: resumed,
            prompt: "Reply exactly: THRAWN_CODEX_RESUME_OK",
            options: options
        ) { _ in }
        XCTAssertEqual(
            followUp.text.trimmingCharacters(in: .whitespacesAndNewlines),
            "THRAWN_CODEX_RESUME_OK"
        )
    }
}
