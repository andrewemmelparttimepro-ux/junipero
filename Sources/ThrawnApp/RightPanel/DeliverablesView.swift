import SwiftUI
import Foundation
import AppKit

// MARK: - Model

struct DeliverableItem: Identifiable {
    var id: String
    var ticketId: String
    var title: String
    var fileName: String
    var filePath: String
    var folderPath: String
    var project: String
    var kind: String
    var status: String
    var createdAt: Date?
    var updatedAt: Date?
    var thumbnailPath: String?
    var summary: String
    var fileSize: Int64
}

// MARK: - Store

@MainActor
final class DeliverablesStore: ObservableObject {
    @Published var items: [DeliverableItem] = []
    @Published var isLoading = false
    @Published var errorText: String?

    func load() {
        isLoading = true
        errorText = nil
        Task {
            let snapshot = await Task.detached(priority: .utility) {
                Self.loadManifest()
            }.value

            items = snapshot.items
            if items.isEmpty {
                errorText = "No HTML deliverables yet. Publish index.html entries in \(snapshot.root)"
            }
            isLoading = false
        }
    }

    nonisolated private static func loadManifest() -> (items: [DeliverableItem], root: String) {
        let fm = FileManager.default
        let root = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/deliverables", isDirectory: true)
        let manifest = root.appendingPathComponent("manifest.json")

        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: manifest.path) {
                try "{\n  \"deliverables\": []\n}\n".write(to: manifest, atomically: true, encoding: .utf8)
            }
        } catch {
            return ([], manifest.path)
        }

        guard let data = try? Data(contentsOf: manifest),
              let rawItems = manifestItems(from: data)
        else { return ([], manifest.path) }

        let items = rawItems.compactMap { item -> DeliverableItem? in
            guard let rawPath = firstString(item, keys: ["filePath", "file_path", "path", "evidence_path", "evidencePath"]) else {
                return nil
            }

            let sourceURL = resolvePath(rawPath)
            let fileURL = primaryDeliverableURL(from: sourceURL)
            let folderURL = folderURL(for: fileURL, sourceURL: sourceURL, item: item)
            let thumbnail = firstString(item, keys: ["thumbnailPath", "thumbnail_path"]).map { resolvePath($0).path }
            let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let updatedAt = dateValue(item, keys: ["updatedAt", "updated_at"]) ?? attrs?.contentModificationDate
            let createdAt = dateValue(item, keys: ["createdAt", "created_at", "timestamp"])
            let ticketId = firstString(item, keys: ["ticketId", "ticket_id", "taskId", "task_id"]) ?? "UNTICKETED"
            let title = firstString(item, keys: ["title"])
                ?? firstString(item, keys: ["description"])
                ?? readableTitle(ticketId: ticketId, url: fileURL)
            let kind = firstString(item, keys: ["kind", "type"]) ?? (fileURL.pathExtension.isEmpty ? "html" : fileURL.pathExtension.lowercased())
            let id = firstString(item, keys: ["id"]) ?? stableId(ticketId: ticketId, path: fileURL.path, title: title)

            return DeliverableItem(
                id: id,
                ticketId: ticketId,
                title: title,
                fileName: fileURL.lastPathComponent,
                filePath: fileURL.path,
                folderPath: folderURL.path,
                project: firstString(item, keys: ["project"]) ?? firstString(item, keys: ["agent"]) ?? "General",
                kind: kind,
                status: firstString(item, keys: ["status"]) ?? "Ready",
                createdAt: createdAt,
                updatedAt: updatedAt,
                thumbnailPath: thumbnail,
                summary: firstString(item, keys: ["summary", "description"]) ?? "",
                fileSize: Int64(attrs?.fileSize ?? 0)
            )
        }
        .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }

        return (items, manifest.path)
    }

    nonisolated private static func manifestItems(from data: Data) -> [[String: Any]]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let dict = json as? [String: Any],
           let deliverables = dict["deliverables"] as? [[String: Any]] {
            return deliverables
        }
        return json as? [[String: Any]]
    }

    nonisolated private static func firstString(_ item: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = item[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    nonisolated private static func dateValue(_ item: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            guard let value = firstString(item, keys: [key]) else { continue }
            if let date = ISO8601DateFormatter().date(from: value) { return date }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    nonisolated private static func resolvePath(_ path: String) -> URL {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path) ?? URL(fileURLWithPath: path)
        }
        if path.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return URL(fileURLWithPath: home).appendingPathComponent(String(path.dropFirst(2)))
        }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        if path.hasPrefix("workspace/") {
            return ThrawnPaths.appSupportDir.appendingPathComponent(path)
        }
        return ThrawnPaths.appSupportDir.appendingPathComponent("workspace").appendingPathComponent(path)
    }

    nonisolated private static func primaryDeliverableURL(from sourceURL: URL) -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return sourceURL }

        for name in ["index.html", "visual-board.html", "report.html", "board.html", "report.md", "board.md"] {
            let candidate = sourceURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return sourceURL
    }

    nonisolated private static func folderURL(for fileURL: URL, sourceURL: URL, item: [String: Any]) -> URL {
        if let rawFolder = firstString(item, keys: ["folderPath", "folder_path"]) {
            return resolvePath(rawFolder)
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return sourceURL
        }
        return fileURL.deletingLastPathComponent()
    }

    nonisolated private static func readableTitle(ticketId: String, url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let cleaned = base.split(separator: " ").map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
        return "\(ticketId) \(cleaned)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func stableId(ticketId: String, path: String, title: String) -> String {
        let raw = "\(ticketId)-\(title)-\(path)"
        let slug = raw.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(slug.prefix(120))
    }
}

// MARK: - View

struct DeliverablesView: View {
    @StateObject private var store = DeliverablesStore()
    @State private var searchText = ""

    var filtered: [DeliverableItem] {
        if searchText.isEmpty { return store.items }
        return store.items.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.ticketId.localizedCaseInsensitiveContains(searchText) ||
            $0.fileName.localizedCaseInsensitiveContains(searchText) ||
            $0.project.localizedCaseInsensitiveContains(searchText) ||
            $0.summary.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            Color.obsidian.ignoresSafeArea()
            RadialGradient(colors: [Color.chissDeep.opacity(0.35), Color.clear], center: .topLeading, startRadius: 0, endRadius: 600)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DELIVERABLES")
                            .font(.system(size: 14, weight: .bold, design: .serif))
                            .tracking(3)
                            .foregroundColor(Color.chissPrimary)
                            .shadow(color: Color.chissPrimary.opacity(0.40), radius: 8)
                        Text("\(filtered.count) HTML deliverables")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.40))
                    }
                    Spacer()
                    // Search
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(Color.chissPrimary.opacity(0.60))
                        TextField("Search...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.85))
                            .frame(width: 120)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.obsidianMid).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.chissPrimary.opacity(0.22), lineWidth: 1)))

                    if store.isLoading {
                        ProgressView().progressViewStyle(.circular).scaleEffect(0.65).tint(Color.chissPrimary).padding(.leading, 8)
                    }
                    Button { store.load() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .bold))
                            Text("Reload").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(Color.chissPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.chissDeep.opacity(0.55)).overlay(Capsule().stroke(Color.chissPrimary.opacity(0.35), lineWidth: 1)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24).padding(.vertical, 14)
                .background(Color.obsidianMid.opacity(0.92))
                .overlay(alignment: .bottom) { Rectangle().fill(Color.chissPrimary.opacity(0.12)).frame(height: 1) }

                if let err = store.errorText {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "shippingbox").font(.system(size: 36)).foregroundColor(Color.chissPrimary.opacity(0.40))
                        Text("No HTML Deliverables")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.82))
                        Text(err).font(.system(size: 12)).foregroundColor(Color.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 520)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 230), spacing: 14)], spacing: 14) {
                            ForEach(filtered) { item in
                                DeliverableTile(item: item)
                            }
                        }
                        .padding(.horizontal, 24).padding(.vertical, 18)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { store.load() }
    }
}

// MARK: - Deliverable Card

private struct DeliverableTile: View {
    let item: DeliverableItem

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private var fileIcon: String {
        let ext = (item.fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "globe"
        case "md": return "doc.text.fill"
        case "pdf": return "doc.richtext.fill"
        case "png", "jpg", "jpeg": return "photo.fill"
        case "mp4", "mov": return "film.fill"
        case "json": return "curlybraces"
        case "swift": return "swift"
        case "zip": return "archivebox.fill"
        default: return "doc.fill"
        }
    }

    var body: some View {
        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: item.filePath))
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                preview

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(item.ticketId)
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundColor(Color.green.opacity(0.88))
                            .lineLimit(1)
                        Spacer()
                        Text(item.status.uppercased())
                            .font(.system(size: 8, weight: .black))
                            .tracking(0.8)
                            .foregroundColor(Color.chissPrimary.opacity(0.72))
                    }

                    Text(item.title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.92))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(item.project)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.chissPrimary.opacity(0.72))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 9, weight: .bold))
                    Text(item.fileName.lowercased() == "index.html" ? "Open HTML" : "Open")
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                    if item.fileSize > 0 {
                        Text(formatSize(item.fileSize))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.34))
                    }
                }
                .foregroundColor(Color.chissPrimary.opacity(0.84))
            }
            .padding(12)
            .aspectRatio(1, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.obsidianMid)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.chissPrimary.opacity(0.18), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open HTML") { NSWorkspace.shared.open(URL(fileURLWithPath: item.filePath)) }
            Button("Reveal Folder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.folderPath)]) }
        }
    }

    @ViewBuilder
    private var preview: some View {
        let thumbnail = item.thumbnailPath ?? (isImage(item.filePath) ? item.filePath : nil)
        if let thumbnail, let image = NSImage(contentsOfFile: thumbnail) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .aspectRatio(1.35, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.chissDeep.opacity(0.34))
                Image(systemName: fileIcon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(Color.chissPrimary.opacity(0.78))
            }
            .aspectRatio(1.35, contentMode: .fit)
        }
    }

    private func isImage(_ path: String) -> Bool {
        ["png", "jpg", "jpeg", "heic", "webp"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
