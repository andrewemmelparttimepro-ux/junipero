import SwiftUI
import Foundation
import AppKit

// MARK: - Model

struct DeliverableItem: Identifiable {
    let id = UUID()
    var fileName: String
    var filePath: String
    var project: String
    var lastModified: Date?
    var fileSize: Int64
}

// MARK: - Store

@MainActor
final class DeliverablesStore: ObservableObject {
    @Published var items: [DeliverableItem] = []
    @Published var isLoading = false
    @Published var errorText: String?

    private static let brainRoot = "/Volumes/brain/NDAI"
    private static let fallbackRoot = "/Users/crustacean/.openclaw/workspace"

    func load() {
        isLoading = true
        errorText = nil
        Task {
            let fm = FileManager.default
            let usesBrain = fm.fileExists(atPath: Self.brainRoot)
            let root = usesBrain ? Self.brainRoot : Self.fallbackRoot
            var found: [DeliverableItem] = []

            let rootURL = URL(fileURLWithPath: root)
            if let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                var depth: [URL: Int] = [rootURL: 0]
                for case let fileURL as URL in enumerator {
                    // Depth limit
                    let parent = fileURL.deletingLastPathComponent()
                    let parentDepth = depth[parent] ?? 0
                    let currentDepth = parentDepth + 1
                    depth[fileURL] = currentDepth

                    if currentDepth > 3 {
                        enumerator.skipDescendants()
                        continue
                    }

                    let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if isDir { continue }

                    let ext = fileURL.pathExtension.lowercased()
                    let allowedExts: Set<String> = ["md", "pdf", "txt", "json", "csv", "png", "jpg", "mp4", "zip", "swift", "html", "docx", "xlsx"]
                    guard allowedExts.contains(ext) else { continue }

                    let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                    let modified = attrs?.contentModificationDate
                    let size = Int64(attrs?.fileSize ?? 0)

                    // Project = immediate child folder of root
                    let components = fileURL.pathComponents
                    let rootComponents = rootURL.pathComponents
                    let projectName: String
                    if components.count > rootComponents.count {
                        projectName = components[rootComponents.count]
                    } else {
                        projectName = "Root"
                    }

                    found.append(DeliverableItem(
                        fileName: fileURL.lastPathComponent,
                        filePath: fileURL.path,
                        project: projectName,
                        lastModified: modified,
                        fileSize: size
                    ))
                }
            }

            // Sort by most recently modified
            found.sort { ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast) }
            items = Array(found.prefix(200))
            if items.isEmpty { errorText = "No deliverables found in \(root)" }
            isLoading = false
        }
    }
}

// MARK: - View

struct DeliverablesView: View {
    @StateObject private var store = DeliverablesStore()
    @State private var searchText = ""

    var filtered: [DeliverableItem] {
        if searchText.isEmpty { return store.items }
        return store.items.filter {
            $0.fileName.localizedCaseInsensitiveContains(searchText) ||
            $0.project.localizedCaseInsensitiveContains(searchText)
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
                        Text("\(filtered.count) files")
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
                        Text(err).font(.system(size: 13)).foregroundColor(Color.white.opacity(0.45))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 12)], spacing: 12) {
                            ForEach(filtered) { item in
                                DeliverableCard(item: item)
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

private struct DeliverableCard: View {
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: fileIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.chissPrimary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.chissDeep.opacity(0.55)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.90))
                        .lineLimit(1)
                    Text(item.project)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.chissPrimary.opacity(0.70))
                }
                Spacer()
            }

            if let modified = item.lastModified {
                Text(Self.dateFormatter.string(from: modified))
                    .font(.system(size: 9.5))
                    .foregroundColor(Color.white.opacity(0.35))
            }

            Divider().background(Color.chissPrimary.opacity(0.12))

            HStack(spacing: 8) {
                Button {
                    let url = URL(fileURLWithPath: item.filePath)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder").font(.system(size: 9, weight: .bold))
                        Text("Reveal").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(Color.chissPrimary.opacity(0.80))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.chissDeep.opacity(0.40)).overlay(Capsule().stroke(Color.chissPrimary.opacity(0.25), lineWidth: 1)))
                }
                .buttonStyle(.plain)

                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: item.filePath))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square").font(.system(size: 9, weight: .bold))
                        Text("Open").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.chissDeep).overlay(Capsule().stroke(Color.chissPrimary.opacity(0.40), lineWidth: 1)))
                }
                .buttonStyle(.plain)

                Spacer()

                if item.fileSize > 0 {
                    Text(formatSize(item.fileSize))
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.28))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.obsidianMid)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.chissPrimary.opacity(0.18), lineWidth: 1))
        )
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
