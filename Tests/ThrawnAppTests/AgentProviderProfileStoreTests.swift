import Foundation
import XCTest
@testable import ThrawnApp

final class AgentProviderProfileStoreTests: XCTestCase {
    func testStableProfilesSeedOnlyTheirRequestedCurrentAccountsOnce() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("thrawn-profile-root-\(UUID().uuidString)")
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("thrawn-profile-home-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: home)
        }

        let codexSource = home.appendingPathComponent(".codex/auth.json")
        let grokSource = home.appendingPathComponent(".grok/auth.json")
        try FileManager.default.createDirectory(
            at: codexSource.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: grokSource.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("codex-account".utf8).write(to: codexSource)
        try Data("grok-account".utf8).write(to: grokSource)

        let store = AgentProviderProfileStore(
            rootDirectory: root,
            homeDirectory: home
        )
        store.prepareStableProfiles()

        for agentID in StableGatewayPolicy.openAIAgentIDs {
            let profile = store.profileDirectory(agentID: agentID, backend: .codex)
            XCTAssertEqual(
                try Data(contentsOf: profile.appendingPathComponent("auth.json")),
                Data("codex-account".utf8)
            )
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: profile.appendingPathComponent("config.toml").path
                )
            )
        }

        let steven = store.profileDirectory(agentID: "steven", backend: .grok)
        let stevenAuth = steven.appendingPathComponent("auth.json")
        XCTAssertEqual(
            try Data(contentsOf: stevenAuth),
            Data("grok-account".utf8)
        )

        for agentID in StableGatewayPolicy.stableAgentIDs {
            let claude = store.profileDirectory(agentID: agentID, backend: .claude)
            var isDirectory: ObjCBool = false
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: claude.path,
                    isDirectory: &isDirectory
                )
            )
            XCTAssertTrue(isDirectory.boolValue)
        }

        // A later launch must not restore credentials after this agent signs out.
        try FileManager.default.removeItem(at: stevenAuth)
        store.prepareStableProfiles()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stevenAuth.path))
    }
}
