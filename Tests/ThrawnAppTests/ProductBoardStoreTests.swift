import Foundation
import XCTest
@testable import ThrawnApp

final class ProductBoardStoreTests: XCTestCase {
    @MainActor
    func testEveryProductStartsWithItsOwnBlankCanvas() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ProductBoardStore(defaults: defaults, storageKey: "boards")

        for board in ProductBoardID.allCases {
            XCTAssertTrue(store.nodes(for: board).isEmpty)
        }
    }

    @MainActor
    func testNotesAndCardPositionsSurviveStoreRecreation() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storageKey = "boards"
        let original = ProductBoardStore(defaults: defaults, storageKey: storageKey)
        let board = ProductBoardID.hitZero
        let firstNode = original.addNote(
            to: board,
            title: "Carissa follow-up",
            body: "Keep the external dependency visible on the product canvas.",
            at: ProductBoardPoint(80, 120)
        )

        original.moveNode(
            firstNode.id,
            on: board,
            to: ProductBoardPoint(444, -222)
        )
        let restored = ProductBoardStore(defaults: defaults, storageKey: storageKey)
        let restoredFirst = try XCTUnwrap(
            restored.nodes(for: board).first(where: { $0.id == firstNode.id })
        )
        XCTAssertEqual(restoredFirst.position, ProductBoardPoint(444, -222))
        XCTAssertEqual(restoredFirst.title, "Carissa follow-up")
        XCTAssertEqual(
            restoredFirst.body,
            "Keep the external dependency visible on the product canvas."
        )
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "ProductBoardStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
