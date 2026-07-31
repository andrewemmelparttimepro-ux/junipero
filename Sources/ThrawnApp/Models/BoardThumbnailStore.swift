import Foundation
import AppKit
import QuickLookThumbnailing

// MARK: - Board Thumbnail Store
//
// Generates real content previews for files pinned to the product
// whiteboards — the first page of a PDF, the rendered page of a DOCX, the
// image itself — using QuickLook's thumbnailing service. Falls back to the
// Finder file icon when a file type has no preview generator.
//
// Cache key includes the file's modification date, so regenerating a
// document (e.g. a new revision of a migration manual) invalidates the old
// preview automatically instead of showing stale content.
//
// Reliability rule: never block the UI and never fail silently. Generation
// happens off the main actor, every failure is logged to FlightRecorder
// once per key, and the caller always gets a usable image (preview or icon).

@MainActor
final class BoardThumbnailStore: ObservableObject {
    static let shared = BoardThumbnailStore()

    /// Rendered previews keyed by path + mtime + requested size.
    @Published private(set) var cache: [String: NSImage] = [:]

    /// Keys that produced no QuickLook preview — remembered so we don't
    /// retry (and re-log) on every redraw.
    private var failedKeys: Set<String> = []
    /// Keys with generation in flight, to dedupe concurrent requests.
    private var inFlight: Set<String> = []

    /// Bound so a board full of documents can't grow memory without limit.
    private static let maxCachedThumbnails = 240

    private init() {}

    /// Cached preview for a file, if one has already been generated.
    func thumbnail(for path: String, size: CGSize) -> NSImage? {
        cache[Self.key(path: path, size: size)]
    }

    /// True when this file has been checked and has no QuickLook preview —
    /// the caller should show the Finder icon instead of a loading state.
    func hasNoPreview(for path: String, size: CGSize) -> Bool {
        failedKeys.contains(Self.key(path: path, size: size))
    }

    /// Request a preview. Returns immediately; the published cache updates
    /// when generation finishes. Safe to call repeatedly from `onAppear`.
    func requestThumbnail(for path: String, size: CGSize, scale: CGFloat) {
        let key = Self.key(path: path, size: size)
        guard cache[key] == nil,
              !failedKeys.contains(key),
              !inFlight.contains(key)
        else { return }

        guard FileManager.default.fileExists(atPath: path) else {
            failedKeys.insert(key)
            return
        }

        inFlight.insert(key)
        let url = URL(fileURLWithPath: path)
        let effectiveScale = max(scale, 1)

        Task { [weak self] in
            let image = await Self.generate(url: url, size: size, scale: effectiveScale)
            guard let self else { return }
            self.inFlight.remove(key)
            if let image {
                self.store(image, forKey: key)
            } else {
                self.failedKeys.insert(key)
            }
        }
    }

    /// Drop any cached preview for a path (all sizes) so the next request
    /// regenerates it. Used when a card's file is replaced in place.
    func invalidate(path: String) {
        let prefix = "\(path)|"
        for key in cache.keys where key.hasPrefix(prefix) {
            cache.removeValue(forKey: key)
        }
        failedKeys = failedKeys.filter { !$0.hasPrefix(prefix) }
    }

    // MARK: - Internals

    private func store(_ image: NSImage, forKey key: String) {
        if cache.count >= Self.maxCachedThumbnails {
            // Simple bound: clear the oldest half rather than tracking full
            // LRU order. Regeneration is cheap and this only trips on very
            // large boards.
            cache.removeAll()
        }
        cache[key] = image
    }

    private static func key(path: String, size: CGSize) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let stamp = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(path)|\(Int(stamp))|\(Int(size.width))x\(Int(size.height))"
    }

    private static func generate(url: URL, size: CGSize, scale: CGFloat) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            // .all lets QuickLook fall back through its own tiers
            // (thumbnail → low-quality → icon) rather than failing outright.
            representationTypes: .all
        )

        do {
            let representation = try await QLThumbnailGenerator.shared
                .generateBestRepresentation(for: request)
            return representation.nsImage
        } catch {
            FlightRecorder.logEvent(
                category: "board",
                action: "thumbnail-unavailable",
                detail: "\(url.lastPathComponent): \(error.localizedDescription)"
            )
            return nil
        }
    }
}
