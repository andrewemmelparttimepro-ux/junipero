import Foundation
import XCTest
@testable import ThrawnApp

final class PrimarySessionPersistenceTests: XCTestCase {
    @MainActor
    func testUserTranscriptSurvivesStoreRecreationWithoutProviderAccount() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("thrawn-conversation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let original = PrimarySessionStore(
            sessionKey: "agent-chat",
            agentId: "archivist",
            storageRoot: root
        )
        original.send("Retain this agent context.")

        let restored = PrimarySessionStore(
            sessionKey: "agent-chat",
            agentId: "archivist",
            storageRoot: root
        )
        XCTAssertEqual(restored.messages.count, 1)
        XCTAssertEqual(restored.messages.first?.role, .user)
        XCTAssertEqual(restored.messages.first?.text, "Retain this agent context.")
    }
}
