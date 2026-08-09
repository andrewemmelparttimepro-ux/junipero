import Foundation
import SwiftUI

// MARK: - Product Board Identity
//
// Each business gets its own infinite freeform canvas — Apple-Freeform-style
// but with no bounds, like Evernote's infinite scratch. Blank by default.
// Whatever Andrew drops onto a board persists per-business across launches.
//
// NDAI has one too: the firm is a business Andrew runs, not just the thing
// that runs the others, and its own thinking needs somewhere to live beside
// the client work rather than scattered across theirs.

enum ProductBoardID: String, CaseIterable, Codable, Identifiable {
    case spas360    = "spas-360"
    case hitZero    = "hit-zero"
    case sandProOMP = "sandpro-omp"
    case ndai       = "ndai"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spas360:    return "SPAS 360"
        case .hitZero:    return "Hit Zero"
        case .sandProOMP: return "SandPro OMP"
        case .ndai:       return "NDAI"
        }
    }

    var shortName: String {
        switch self {
        case .spas360:    return "SPAS"
        case .hitZero:    return "HIT ZERO"
        case .sandProOMP: return "OMP"
        case .ndai:       return "NDAI"
        }
    }

    /// Filename of the product logo shipped inside the app bundle. Used by
    /// the switcher buttons and the full-screen overlay header.
    var logoResource: String {
        switch self {
        case .spas360:    return "spas360-logo"
        case .hitZero:    return "hitzero-logo"
        case .sandProOMP: return "sandpro-omp-logo"
        case .ndai:       return "ndai-logo"
        }
    }

    /// SF Symbol fallback used only if the PNG asset can't be loaded.
    var iconFallback: String {
        switch self {
        case .spas360:    return "square.grid.3x3.square"
        case .hitZero:    return "bolt.shield.fill"
        case .sandProOMP: return "building.2.fill"
        case .ndai:       return "hexagon.fill"
        }
    }

    var leadLabel: String {
        switch self {
        case .spas360:    return "Steven"
        case .hitZero:    return "Sir Davos"
        case .sandProOMP: return "Samwell Tarly"
        // The house board answers to the house lead.
        case .ndai:       return "Thrawn"
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
    /// When set, this node is a file pinned to the board — the path points
    /// at the original on disk (link, not copy, so double-click always opens
    /// the live version). Optional so pre-existing v3 boards still decode.
    var filePath: String?
    /// Who wrote this node — "human" or "agent:<id>", straight from the
    /// .board format's meta.author. Agents post to these boards through the
    /// bord CLI; the badge in the UI is this field. Optional so pre-bridge
    /// data still decodes.
    var author: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        body: String = "",
        position: ProductBoardPoint,
        colorSlot: Int = 0,
        updatedAt: Date = Date(),
        filePath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.position = position
        self.colorSlot = colorSlot
        self.updatedAt = updatedAt
        self.filePath = filePath
    }
}

// MARK: - Board Store

@MainActor
final class ProductBoardStore: ObservableObject {
    @Published private(set) var nodesByBoard: [String: [ProductBoardNode]]
    /// Nodes present in a package that Thrawn does not render (ink, shapes,
    /// connectors drawn in boRD or by agents). Preserved verbatim on every
    /// write; surfaced so the UI can say "open in boRD to see everything."
    @Published private(set) var foreignCountByBoard: [String: Int] = [:]

    private let defaults: UserDefaults
    private let storageKey: String

    /// Boards live as real `.board` packages in the directory the bord CLI
    /// searches — durable open files instead of a UserDefaults blob, editable
    /// by boRD and by agents. UserDefaults v3 is read exactly once as a
    /// migration source and then left untouched as a backup.
    ///
    /// Writes are debounced per board (drags call moveNode continuously) and
    /// a directory watcher reloads when anything else — boRD, the CLI, an
    /// agent — changes a package, so external work appears without restarting.
    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "thrawn.productBoards.v3"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        nodesByBoard = [:]

        migrateFromDefaultsIfNeeded()
        // Migration only fires on a virgin install, so a board added to the
        // roster later would have no file until someone happened to write to
        // it — invisible to boRD and to every agent until then. Guaranteeing
        // the package here means a new board is real the moment it exists.
        for board in ProductBoardID.allCases {
            BoardPackageBridge.ensurePackageExists(board: board)
        }
        reloadAllFromPackages()
        for board in ProductBoardID.allCases where nodesByBoard[board.rawValue] == nil {
            nodesByBoard[board.rawValue] = []
        }
        startWatchingPackages()
    }

    deinit {
        for watcher in fileWatchers.values { watcher.cancel() }
    }

    func nodes(for board: ProductBoardID) -> [ProductBoardNode] {
        nodesByBoard[board.rawValue] ?? []
    }

    func foreignNodeCount(for board: ProductBoardID) -> Int {
        foreignCountByBoard[board.rawValue] ?? 0
    }

    /// The package on disk, for "Open in boRD".
    func packageURL(for board: ProductBoardID) -> URL {
        BoardPackageBridge.packageURL(for: board)
    }

    /// Update just the position of a note. Called continuously during drag,
    /// so the package write is debounced — memory now, disk when the hand
    /// settles.
    func moveNode(_ nodeID: String, on board: ProductBoardID, to point: ProductBoardPoint) {
        guard var nodes = nodesByBoard[board.rawValue],
              let index = nodes.firstIndex(where: { $0.id == nodeID })
        else { return }
        nodes[index].position = point
        nodes[index].updatedAt = Date()
        nodesByBoard[board.rawValue] = nodes
        scheduleFlush(board, delay: .milliseconds(600))
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
        scheduleFlush(board, delay: .milliseconds(50))
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
        scheduleFlush(board, delay: .milliseconds(50))
        return node
    }

    /// Pin a file to the board at a board-space point. Stores a link to the
    /// original file; deleting the card never touches the file on disk.
    @discardableResult
    func addFile(
        to board: ProductBoardID,
        url: URL,
        at point: ProductBoardPoint
    ) -> ProductBoardNode {
        let existing = nodesByBoard[board.rawValue] ?? []
        let node = ProductBoardNode(
            title: url.lastPathComponent,
            position: point,
            colorSlot: existing.count % 5,
            filePath: url.path
        )
        nodesByBoard[board.rawValue, default: []].append(node)
        scheduleFlush(board, delay: .milliseconds(50))
        return node
    }

    func deleteNode(_ nodeID: String, on board: ProductBoardID) {
        guard var nodes = nodesByBoard[board.rawValue] else { return }
        nodes.removeAll { $0.id == nodeID }
        nodesByBoard[board.rawValue] = nodes
        scheduleFlush(board, delay: .milliseconds(50))
    }

    // MARK: - Package persistence

    private var flushTasks: [String: Task<Void, Never>] = [:]
    /// Set while our own write lands, so the directory watcher can tell our
    /// writes from an agent's and not bounce the UI for no reason.
    private var lastLocalWrite: Date = .distantPast
    private var fileWatchers: [String: DispatchSourceFileSystemObject] = [:]
    private var reloadDebounce: Task<Void, Never>?

    private func scheduleFlush(_ board: ProductBoardID, delay: Duration) {
        let key = board.rawValue
        flushTasks[key]?.cancel()
        flushTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.flush(board) }
        }
    }

    private func flush(_ board: ProductBoardID) {
        lastLocalWrite = Date()
        BoardPackageBridge.save(board: board, notes: nodesByBoard[board.rawValue] ?? [])
    }

    private func reloadAllFromPackages() {
        for board in ProductBoardID.allCases {
            guard let loaded = BoardPackageBridge.load(board: board) else { continue }
            nodesByBoard[board.rawValue] = loaded.notes
            foreignCountByBoard[board.rawValue] = loaded.foreignNodeCount
        }
    }

    /// One-way, one-time: UserDefaults v3 → packages. The defaults blob is
    /// deliberately left in place afterwards as a recovery backup.
    private func migrateFromDefaultsIfNeeded() {
        let anyPackageExists = ProductBoardID.allCases.contains {
            FileManager.default.fileExists(
                atPath: BoardPackageBridge.packageURL(for: $0).appendingPathComponent("manifest.json").path
            )
        }
        guard !anyPackageExists else { return }

        var legacy: [String: [ProductBoardNode]] = [:]
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: [ProductBoardNode]].self, from: data) {
            legacy = decoded
        }

        for board in ProductBoardID.allCases {
            BoardPackageBridge.ensurePackageExists(board: board)
            let notes = legacy[board.rawValue] ?? []
            if !notes.isEmpty {
                BoardPackageBridge.save(board: board, notes: notes)
            }
        }
    }

    /// Reload when anything else writes a package — boRD saving, an agent
    /// posting through the CLI. That is not an edge case; it is the feature.
    ///
    /// Each board.json is watched individually: a write INSIDE a package does
    /// not touch the boards directory's own mtime, so a directory watcher
    /// would sleep through exactly the events that matter. And because every
    /// well-behaved writer replaces board.json atomically (new inode), a
    /// fired watcher is stale by definition — the handler re-arms on a fresh
    /// descriptor after every event.
    private func startWatchingPackages() {
        try? FileManager.default.createDirectory(
            at: BoardPackageBridge.boardsDirectory, withIntermediateDirectories: true
        )
        for board in ProductBoardID.allCases {
            armWatcher(for: board)
        }
    }

    private func armWatcher(for board: ProductBoardID) {
        fileWatchers[board.rawValue]?.cancel()
        fileWatchers[board.rawValue] = nil

        let fileURL = BoardPackageBridge.packageURL(for: board).appendingPathComponent("board.json")
        // Fall back to the package directory before the file exists, so the
        // very first external write still wakes us.
        let path = FileManager.default.fileExists(atPath: fileURL.path)
            ? fileURL.path
            : BoardPackageBridge.packageURL(for: board).path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.handleExternalChange()
            // Atomic replace = new inode = this descriptor now points at the
            // old file. Re-arm on the fresh one.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                self?.armWatcher(for: board)
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatchers[board.rawValue] = source
    }

    private func handleExternalChange() {
        reloadDebounce?.cancel()
        reloadDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                // Our own flush also fires the watcher; ignore the echo.
                guard Date().timeIntervalSince(self.lastLocalWrite) > 1.0 else { return }
                self.reloadAllFromPackages()
            }
        }
    }
}
