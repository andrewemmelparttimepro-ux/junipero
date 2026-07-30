import Foundation
import XCTest
@testable import ThrawnApp

final class GrokCLIProviderIntegrationTests: XCTestCase {
    @MainActor
    func testLiveSubscriptionTurnWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["THRAWN_RUN_LIVE_PROVIDER_TESTS"] == "1" else {
            throw XCTSkip("Set THRAWN_RUN_LIVE_PROVIDER_TESTS=1 to exercise the signed-in Grok subscription.")
        }

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("thrawn-grok-provider-test-\(UUID().uuidString)")
        let profile = FileManager.default.temporaryDirectory
            .appendingPathComponent("thrawn-grok-profile-test-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: profile)
        }
        try FileManager.default.createDirectory(
            at: profile,
            withIntermediateDirectories: true
        )
        let sourceAuth = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/auth.json")
        guard FileManager.default.fileExists(atPath: sourceAuth.path) else {
            throw XCTSkip("The current Grok CLI account is not signed in.")
        }
        try FileManager.default.copyItem(
            at: sourceAuth,
            to: profile.appendingPathComponent("auth.json")
        )

        let provider = GrokCLIProvider(
            profileID: "integration-steven",
            stateDirectory: profile
        )
        let status = await provider.probe()
        XCTAssertEqual(status.state, .ready, status.detail)

        let options = AgentSessionOptions(
            sessionKey: "integration:grok",
            agentID: "steven",
            provider: .grok,
            cwd: workspace,
            developerInstructions: "Return only the exact requested text. Do not use tools.",
            model: ProviderRouter.dynamicGrokModel,
            reasoningEffort: "low",
            approvalPolicy: .never,
            sandbox: .readOnly
        )
        let session = try await provider.createSession(options: options)
        let result = try await provider.runTurn(
            session: session,
            prompt: "Reply exactly: THRAWN_GROK_SWIFT_OK",
            options: options
        ) { _ in }

        XCTAssertEqual(
            result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            "THRAWN_GROK_SWIFT_OK"
        )
        XCTAssertFalse(result.providerSessionID.isEmpty)

        let resumed = try await provider.resumeSession(
            providerSessionID: result.providerSessionID,
            options: options
        )
        let followUp = try await provider.runTurn(
            session: resumed,
            prompt: "Reply exactly: THRAWN_GROK_RESUME_OK",
            options: options
        ) { _ in }
        XCTAssertEqual(
            followUp.text.trimmingCharacters(in: .whitespacesAndNewlines),
            "THRAWN_GROK_RESUME_OK"
        )
    }
}
