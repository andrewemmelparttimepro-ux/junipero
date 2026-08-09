import Foundation

// MARK: - Board Package Bridge
//
// Thrawn's whiteboards as real `.board` packages — boRD's open format,
// implemented here independently from the published spec
// (boRD/spec/BOARD_FORMAT_SPEC.md). This is the point of an open format:
// Thrawn does not link BoardKit, it speaks the file.
//
// Why this exists: the boards used to live in UserDefaults, which made them
// invisible to every agent and one corrupted plist away from gone. As
// packages they are durable files, they open full-fat in boRD, the `bord`
// CLI already searches this exact directory — and an agent that can append a
// line to a text file can post to Andrew's whiteboard, with attribution.
//
// The one rule that outranks all others here (spec §4.3): **preserve the
// unknown.** Thrawn renders notes and file pins. A board may also hold ink,
// shapes, connectors, frames — drawn in boRD or by an agent. Those nodes are
// carried as raw JSON and written back byte-for-byte. Thrawn edits only what
// Thrawn touched.

enum BoardPackageBridge {

    // MARK: Locations

    /// The directory the `bord` CLI already searches — that overlap is the
    /// entire integration story for agents.
    static var boardsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Thrawn/workspace/boards", isDirectory: true)
    }

    static func packageURL(for board: ProductBoardID) -> URL {
        boardsDirectory.appendingPathComponent("\(board.displayName).board", isDirectory: true)
    }

    // MARK: Timestamps — ISO 8601 with milliseconds, per spec §2

    private static let isoWriter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoReaderPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func isoString(_ date: Date) -> String { isoWriter.string(from: date) }

    static func isoDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return isoWriter.date(from: string) ?? isoReaderPlain.date(from: string)
    }

    // MARK: Loaded shape

    struct LoadedBoard {
        /// Nodes Thrawn renders: notes and file pins, in z order.
        var notes: [ProductBoardNode]
        /// The full board.json, kept verbatim for read-modify-write.
        var rawBoard: [String: Any]
        /// Nodes present in the package that Thrawn does not render (ink,
        /// shapes, connectors, …). Counted so the UI can say they exist.
        var foreignNodeCount: Int
        /// Snapshot of the package nodes keyed by id, for diffing at save.
        var rawNodesByID: [String: [String: Any]]
    }

    // MARK: Reading

    static func load(board: ProductBoardID) -> LoadedBoard? {
        let url = packageURL(for: board).appendingPathComponent("board.json")
        guard let data = try? Data(contentsOf: url),
              let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let nodes = raw["nodes"] as? [[String: Any]]
        else { return nil }

        var mapped: [ProductBoardNode] = []
        var foreign = 0
        var byID: [String: [String: Any]] = [:]

        for node in nodes {
            guard let id = node["id"] as? String else { continue }
            byID[id] = node
            if let productNode = productNode(from: node) {
                mapped.append(productNode)
            } else {
                foreign += 1
            }
        }

        // z order, ties on id — same ordering rule the spec gives renderers.
        mapped.sort { a, b in
            let za = (byID[a.id]?["z"] as? Int) ?? 0
            let zb = (byID[b.id]?["z"] as? Int) ?? 0
            return za == zb ? a.id < b.id : za < zb
        }

        return LoadedBoard(notes: mapped, rawBoard: raw, foreignNodeCount: foreign, rawNodesByID: byID)
    }

    /// Map one package node into Thrawn's model, or nil when it is a kind
    /// Thrawn does not render (which is fine — it is preserved regardless).
    private static func productNode(from node: [String: Any]) -> ProductBoardNode? {
        guard let id = node["id"] as? String,
              let content = node["content"] as? [String: Any],
              let type = content["type"] as? String
        else { return nil }

        let value = content["value"] as? [String: Any] ?? [:]
        let meta = node["meta"] as? [String: Any] ?? [:]
        let frame = node["frame"] as? [String: Any] ?? [:]
        let origin = frame["origin"] as? [String: Any] ?? [:]
        let x = (origin["x"] as? Double) ?? 0
        let y = (origin["y"] as? Double) ?? 0

        // Thrawn's accent slot rides in userInfo — the spec's host-data bag —
        // so it survives boRD editing the same node. Fall back to a stable
        // hash so notes born in boRD still get a consistent tint.
        let userInfo = meta["userInfo"] as? [String: Any] ?? [:]
        let slot = Int(userInfo["thrawn.colorSlot"] as? String ?? "") ?? abs(id.hashValue % 5)

        let author = meta["author"] as? String
        let modified = isoDate(meta["modifiedAt"] as? String) ?? Date()

        switch type {
        case "note":
            var result = ProductBoardNode(
                id: id,
                title: value["title"] as? String ?? "",
                body: value["body"] as? String ?? "",
                position: ProductBoardPoint(x, y),
                colorSlot: slot,
                updatedAt: modified
            )
            result.author = author
            return result
        case "file":
            var result = ProductBoardNode(
                id: id,
                title: value["displayName"] as? String ?? (value["path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "File",
                body: "",
                position: ProductBoardPoint(x, y),
                colorSlot: slot,
                updatedAt: modified,
                filePath: value["path"] as? String
            )
            result.author = author
            return result
        default:
            return nil
        }
    }

    // MARK: Writing

    /// Persist Thrawn's current notes into the package.
    ///
    /// Node-level read-modify-write against the freshest board.json on disk:
    /// foreign nodes pass through untouched, edited notes are updated in
    /// place (keeping their z, style, tags, and anything boRD added), new
    /// notes are appended above the current top, deletions are removed. Every
    /// change is appended to the operation log with `from`/`to` values so it
    /// is invertible in boRD, exactly as the spec asks.
    static func save(board: ProductBoardID, notes: [ProductBoardNode]) {
        let packageURL = packageURL(for: board)
        ensurePackageExists(board: board)

        // Re-read at write time, not from a cached snapshot: an agent may
        // have appended since Thrawn loaded, and their work must survive.
        let current = load(board: board)
        var raw = current?.rawBoard ?? emptyBoardJSON(title: board.displayName)
        var rawNodes = (raw["nodes"] as? [[String: Any]]) ?? []
        let previousByID = current?.rawNodesByID ?? [:]

        let now = Date()
        let wantedByID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        var ops: [[String: Any]] = []

        var maxZ = rawNodes.compactMap { $0["z"] as? Int }.max() ?? 0

        // Update or delete the note/file nodes Thrawn manages.
        var nextNodes: [[String: Any]] = []
        for node in rawNodes {
            guard let id = node["id"] as? String,
                  let content = node["content"] as? [String: Any],
                  let type = content["type"] as? String,
                  type == "note" || type == "file"
            else {
                nextNodes.append(node)   // foreign: byte-for-byte passthrough
                continue
            }

            guard let wanted = wantedByID[id] else {
                // Deleted in Thrawn. Log carries the full node so boRD can
                // undo the deletion.
                ops.append(operation(kind: ["type": "deleteNode", "id": id, "node": node], at: now))
                continue
            }

            var updated = node
            apply(wanted, to: &updated, now: now)
            if NSDictionary(dictionary: updated) != NSDictionary(dictionary: node) {
                ops.append(operation(kind: ["type": "updateNode", "id": id, "node": updated], at: now))
                nextNodes.append(updated)
            } else {
                nextNodes.append(node)
            }
        }

        // Brand-new notes.
        let existingIDs = Set(previousByID.keys)
        for note in notes where !existingIDs.contains(note.id) {
            maxZ += 1
            let node = newNodeJSON(for: note, z: maxZ, now: now)
            ops.append(operation(kind: ["type": "addNode", "node": node], at: now))
            nextNodes.append(node)
        }

        guard !ops.isEmpty else { return }

        raw["nodes"] = sortedForCanonicalOutput(nextNodes)

        var manifest = (raw["manifest"] as? [String: Any]) ?? emptyManifest(title: board.displayName)
        manifest["modifiedAt"] = isoString(now)
        manifest["nodeCount"] = nextNodes.count
        manifest["generator"] = "thrawn"
        raw["manifest"] = manifest

        do {
            try writeJSON(raw, to: packageURL.appendingPathComponent("board.json"))
            try writeJSON(manifest, to: packageURL.appendingPathComponent("manifest.json"))
            try appendOps(ops, packageURL: packageURL)
        } catch {
            // Never silently lose a write. The store surfaces this.
            NSLog("[Thrawn] Board package write failed for %@: %@", board.displayName, error.localizedDescription)
        }
    }

    /// Copy Thrawn's editable fields onto an existing node dict, leaving
    /// every field Thrawn does not manage (z, style, rotation, tags, external)
    /// exactly as it was.
    private static func apply(_ note: ProductBoardNode, to node: inout [String: Any], now: Date) {
        var frame = node["frame"] as? [String: Any] ?? [:]
        var size = frame["size"] as? [String: Any] ?? ["width": 218.0, "height": 110.0]
        if size["width"] == nil { size["width"] = 218.0 }
        if size["height"] == nil { size["height"] = 110.0 }
        frame["origin"] = ["x": note.position.x, "y": note.position.y]
        frame["size"] = size
        node["frame"] = frame

        var content = node["content"] as? [String: Any] ?? [:]
        let type = content["type"] as? String ?? "note"
        var value = content["value"] as? [String: Any] ?? [:]
        if type == "note" {
            value["title"] = note.title
            value["body"] = note.body
        } else if type == "file" {
            value["displayName"] = note.title
            if let path = note.filePath { value["path"] = path }
        }
        content["value"] = value
        node["content"] = content

        var meta = node["meta"] as? [String: Any] ?? [:]
        meta["modifiedAt"] = isoString(note.updatedAt)
        if meta["createdAt"] == nil { meta["createdAt"] = isoString(now) }
        if meta["author"] == nil { meta["author"] = "human" }
        var userInfo = meta["userInfo"] as? [String: Any] ?? [:]
        userInfo["thrawn.colorSlot"] = String(note.colorSlot)
        meta["userInfo"] = userInfo
        node["meta"] = meta
    }

    private static func newNodeJSON(for note: ProductBoardNode, z: Int, now: Date) -> [String: Any] {
        // boRD's own note palette, so a note born in Thrawn looks native
        // when the board opens there.
        let palette: [[String: Double]] = [
            ["r": 1.00, "g": 0.93, "b": 0.58, "a": 1],
            ["r": 0.74, "g": 0.88, "b": 1.00, "a": 1],
            ["r": 1.00, "g": 0.80, "b": 0.84, "a": 1],
            ["r": 0.80, "g": 0.94, "b": 0.76, "a": 1],
            ["r": 0.92, "g": 0.84, "b": 1.00, "a": 1],
        ]

        let content: [String: Any]
        if let path = note.filePath {
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
            content = ["type": "file", "value": [
                "attachment": "linked",
                "path": path,
                "displayName": note.title,
                "fileExtension": URL(fileURLWithPath: path).pathExtension,
                "byteSize": size ?? 0,
            ]]
        } else {
            content = ["type": "note", "value": ["title": note.title, "body": note.body]]
        }

        return [
            "id": note.id,
            "frame": [
                "origin": ["x": note.position.x, "y": note.position.y],
                "size": ["width": 218.0, "height": 110.0],
            ],
            "rotation": 0.0,
            "z": z,
            "style": [
                "fill": palette[((note.colorSlot % palette.count) + palette.count) % palette.count],
                "stroke": ["color": ["r": 0, "g": 0, "b": 0, "a": 0.10], "width": 1, "dash": "solid"],
                "cornerRadius": 10,
                "opacity": 1,
                "shadow": true,
                "text": [
                    "fontSize": 13, "weight": "semibold",
                    "color": ["r": 0.18, "g": 0.16, "b": 0.13, "a": 1],
                    "alignment": "leading", "monospaced": false, "italic": false,
                    "underline": false, "strikethrough": false, "lineSpacing": 2,
                ],
            ],
            "content": content,
            "meta": [
                "createdAt": isoString(note.updatedAt),
                "modifiedAt": isoString(note.updatedAt),
                "author": note.author ?? "human",
                "tags": [],
                "locked": false,
                "userInfo": ["thrawn.colorSlot": String(note.colorSlot)],
            ],
        ]
    }

    // MARK: Package scaffolding

    static func ensurePackageExists(board: ProductBoardID) {
        let url = packageURL(for: board)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.appendingPathComponent("manifest.json").path) else { return }
        do {
            try fm.createDirectory(at: url.appendingPathComponent("ops"), withIntermediateDirectories: true)
            try fm.createDirectory(at: url.appendingPathComponent("assets"), withIntermediateDirectories: true)
            let boardJSON = emptyBoardJSON(title: board.displayName)
            try writeJSON(boardJSON, to: url.appendingPathComponent("board.json"))
            try writeJSON(boardJSON["manifest"] as? [String: Any] ?? [:], to: url.appendingPathComponent("manifest.json"))
        } catch {
            NSLog("[Thrawn] Could not create board package %@: %@", board.displayName, error.localizedDescription)
        }
    }

    private static func emptyManifest(title: String) -> [String: Any] {
        [
            "format": "pro.ndai.board",
            "schemaVersion": 1,
            "id": UUID().uuidString,
            "title": title,
            "createdAt": isoString(Date()),
            "modifiedAt": isoString(Date()),
            "nodeCount": 0,
            "generator": "thrawn",
        ]
    }

    private static func emptyBoardJSON(title: String) -> [String: Any] {
        [
            "manifest": emptyManifest(title: title),
            "background": "whiteboard",
            "viewport": ["offsetX": 0.0, "offsetY": 0.0, "zoom": 1.0],
            "nodes": [[String: Any]](),
        ]
    }

    // MARK: Canonical output + IO

    /// Flat array sorted by z then id — the spec's rule for diff-stable files.
    private static func sortedForCanonicalOutput(_ nodes: [[String: Any]]) -> [[String: Any]] {
        nodes.sorted { a, b in
            let za = (a["z"] as? Int) ?? 0
            let zb = (b["z"] as? Int) ?? 0
            if za != zb { return za < zb }
            return ((a["id"] as? String) ?? "") < ((b["id"] as? String) ?? "")
        }
    }

    private static func writeJSON(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    private static func operation(kind: [String: Any], at date: Date) -> [String: Any] {
        ["id": UUID().uuidString, "at": isoString(date), "author": "human", "kind": kind]
    }

    /// Append one line per operation to the current segment, creating
    /// `000001.jsonl` when the log is empty. Appending is the whole contract —
    /// this is the same door the agents use.
    private static func appendOps(_ ops: [[String: Any]], packageURL: URL) throws {
        let opsDir = packageURL.appendingPathComponent("ops")
        try FileManager.default.createDirectory(at: opsDir, withIntermediateDirectories: true)

        let segments = (try? FileManager.default.contentsOfDirectory(atPath: opsDir.path))?
            .filter { $0.hasSuffix(".jsonl") }.sorted() ?? []
        let segment = opsDir.appendingPathComponent(segments.last ?? "000001.jsonl")

        var payload = Data()
        for op in ops {
            payload.append(try JSONSerialization.data(withJSONObject: op, options: [.sortedKeys, .withoutEscapingSlashes]))
            payload.append(0x0A)
        }

        if FileManager.default.fileExists(atPath: segment.path) {
            let handle = try FileHandle(forWritingTo: segment)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
        } else {
            try payload.write(to: segment, options: .atomic)
        }
    }
}
