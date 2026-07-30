import XCTest
@testable import ThrawnApp

final class StableGatewayPolicyTests: XCTestCase {
    func testRequestedStableDefaults() {
        for agentID in ["thrawn", "archivist", "sentinel", "dwight"] {
            let route = StableGatewayPolicy.defaultOverride(for: agentID)
            XCTAssertEqual(route?.provider, .codex)
            XCTAssertEqual(route?.model, ProviderRouter.dynamicCodexModel)
            XCTAssertEqual(route?.allowFallback, false)
        }

        let steven = StableGatewayPolicy.defaultOverride(for: "steven")
        XCTAssertEqual(steven?.provider, .grok)
        XCTAssertEqual(steven?.model, ProviderRouter.dynamicGrokModel)
        XCTAssertEqual(steven?.allowFallback, false)
    }

    func testOnlyLiveAgentRuntimesAreSelectableSubscriptionBackends() {
        XCTAssertTrue(ProviderBackend.codex.isSubscriptionGateway)
        XCTAssertTrue(ProviderBackend.grok.isSubscriptionGateway)
        XCTAssertTrue(ProviderBackend.claude.isSubscriptionGateway)
        XCTAssertFalse(ProviderBackend.xai.isSubscriptionGateway)
        XCTAssertFalse(ProviderBackend.openai.isSubscriptionGateway)
    }

    func testGatewayCatalogExposesKnownSignInPathsWithoutClaimingAdapters() {
        XCTAssertEqual(
            SubscriptionGatewayCatalog.all.map(\.id),
            ["openai", "grok", "claude", "cursor", "opencode"]
        )
        XCTAssertEqual(
            SubscriptionGatewayCatalog.all.first(where: { $0.id == "openai" })?.backend,
            .codex
        )
        XCTAssertEqual(
            SubscriptionGatewayCatalog.all.first(where: { $0.id == "grok" })?.backend,
            .grok
        )
        XCTAssertEqual(
            SubscriptionGatewayCatalog.all.first(where: { $0.id == "claude" })?.backend,
            .claude
        )
    }
}
