import Foundation
import SwiftUI

// MARK: - Product Board Identity
//
// SPAS 360, Hit Zero, and SandPro OMP each get their own infinite freeform
// canvas — Apple-Freeform-style but with no bounds, like Evernote's infinite
// scratch. Blank by default. Whatever Andrew drops onto the board persists
// per-product across launches.

enum ProductBoardID: String, CaseIterable, Codable, Identifiable {
    case spas360    = "spas-360"
    case hitZero    = "hit-zero"
    case sandProOMP = "sandpro-omp"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spas360:    return "SPAS 360"
        case .hitZero:    return "Hit Zero"
        case .sandProOMP: return "SandPro OMP"
        }
    }

    var shortName: String {
        switch self {
        case .spas360:    return "SPAS"
        case .hitZero:    return "HIT ZERO"
        case .sandProOMP: return "OMP"
        }
    }

    /// Filename of the product logo shipped inside the app bundle. Used by
    /// the switcher buttons and the full-screen overlay header.
    var logoResource: String {
        switch self {
        case .spas360:    return "spas360-logo"
        case .hitZero:    return "hitzero-logo"
        case .sandProOMP: return "sandpro-omp-logo"
        }
    }

    /// SF Symbol fallback used only if the PNG asset can't be loaded.
    var iconFallback: String {
        switch self {
        case .spas360:    return "square.grid.3x3.square"
        case .hitZero:    return "bolt.shield.fill"
        case .sandProOMP: return "building.2.fill"
        }
    }

    var leadLabel: String {
        switch self {
        case .spas360:    return "Steven"
        case .hitZero:    return "Sir Davos"
        case .sandProOMP: return "Samwell Tarly"
        }
    }
}

// MARK: - Board Geometry

struct ProductBoardPoint: Codable, Equatable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

// MARK: - Freeform Note

/// A single freeform note on a product board. Position is measured in board
/// coordinates (unbounded, both signs), NOT in screen pixels. The view
/// transforms board coordinates through the current pan + zoom transform.
struct ProductBoardNode: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var body: String
    var position: ProductBoardPoint
    /// A gentle accent tint for the note — cycles per color slot so a
    /// blanket of notes doesn't read as a wall of grey.
    var colorSlot: Int
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        body: String = "",
        position: ProductBoardPoint,
        colorSlot: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.position = position
        self.colorSlot = colorSlot
        self.updatedAt = updatedAt
    }
}

// MARK: - Board Store

@MainActor
final class ProductBoardStore: ObservableObject {
    @Published private(set) var nodesByBoard: [String: [ProductBoardNode]]

    private let defaults: UserDefaults
    private let storageKey: String

    /// Storage key was bumped from `v2` to `v3` when the schema switched
    /// from the predefined mindmap (anchor / workstream / evidence) to true
    /// freeform notes. Old v2 data is left in UserDefaults for recovery
    /// but is not read — the new experience starts blank.
    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "thrawn.productBoards.v3"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey

        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: [ProductBoardNode]].self, from: data) {
            nodesByBoard = decoded
        } else {
            // Blank canvases by design. Andrew fills them, we don't seed them.
            var empty: [String: [ProductBoardNode]] = [:]
            for board in ProductBoardID.allCases {
                empty[board.rawValue] = []
            }
            nodesByBoard = empty
        }

        // Ensure any newly-added board has an entry so callers can rely on
        // `nodes(for:)` returning at minimum an empty array.
        for board in ProductBoardID.allCases where nodesByBoard[board.rawValue] == nil {
            nodesByBoard[board.rawValue] = []
        }
    }

    func nodes(for board: ProductBoardID) -> [ProductBoardNode] {
        nodesByBoard[board.rawValue] ?? []
    }

    /// Update just the position of a note. Called continuously during drag,
    /// so avoid heavier work here.
    func moveNode(_ nodeID: String, on board: ProductBoardID, to point: ProductBoardPoint) {
        guard var nodes = nodesByBoard[board.rawValue],
              let index = nodes.firstIndex(where: { $0.id == nodeID })
        else { return }
        nodes[index].position = point
        nodes[index].updatedAt = Date()
        nodesByBoard[board.rawValue] = nodes
        persist()
    }

    /// Update the text of an existing note.
    func updateNode(_ nodeID: String, on board: ProductBoardID, title: String, body: String) {
        guard var nodes = nodesByBoard[board.rawValue],
              let index = nodes.firstIndex(where: { $0.id == nodeID })
        else { return }
        nodes[index].title = title
        nodes[index].body = body
        nodes[index].updatedAt = Date()
        nodesByBoard[board.rawValue] = nodes
        persist()
    }

    /// Add a note at a specific board-space point. Empty title is allowed —
    /// the note appears as a placeholder the user can immediately edit.
    @discardableResult
    func addNote(
        to board: ProductBoardID,
        title: String = "",
        body: String = "",
        at point: ProductBoardPoint
    ) -> ProductBoardNode {
        let existing = nodesByBoard[board.rawValue] ?? []
        let node = ProductBoardNode(
            title: title,
            body: body,
            position: point,
            // Cycle through accent slots so back-to-back notes don't clump
            // into the same color.
            colorSlot: existing.count % 5
        )
        nodesByBoard[board.rawValue, default: []].append(node)
        persist()
        return node
    }

    func deleteNode(_ nodeID: String, on board: ProductBoardID) {
        guard var nodes = nodesByBoard[board.rawValue] else { return }
        nodes.removeAll { $0.id == nodeID }
        nodesByBoard[board.rawValue] = nodes
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(nodesByBoard) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
