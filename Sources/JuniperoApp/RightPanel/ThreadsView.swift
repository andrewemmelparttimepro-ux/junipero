import SwiftUI

private enum ThreadSortOrder: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"
    case unread = "Unread First"

    var id: String { rawValue }
}

struct ThreadsView: View {
    @EnvironmentObject var threadStore: ThreadStore
    @State private var searchText = ""
    @State private var sortOrder: ThreadSortOrder = .newest

    private var filteredThreads: [ChatThread] {
        var threads = threadStore.threads

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = searchText.lowercased()
            threads = threads.filter { thread in
                let hay = (thread.latestUserText + " " + thread.latestAssistantText).lowercased()
                return hay.contains(q)
            }
        }

        switch sortOrder {
        case .newest:
            threads.sort(by: { $0.updatedAt > $1.updatedAt })
        case .oldest:
            threads.sort(by: { $0.updatedAt < $1.updatedAt })
        case .unread:
            threads.sort(by: { lhs, rhs in
                let l = lhs.unreadCount > 0 ? 0 : 1
                let r = rhs.unreadCount > 0 ? 0 : 1
                if l == r { return lhs.updatedAt > rhs.updatedAt }
                return l < r
            })
        }

        return threads
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            Rectangle()
                .fill(JuniperoTheme.divider)
                .frame(height: 1)

            if filteredThreads.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredThreads) { thread in
                            ThreadCard(thread: thread)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        threadStore.selectedThreadId = thread.id
                                        threadStore.markThreadRead(thread.id)
                                    }
                                }
                                .contextMenu {
                                    if thread.state == .failed {
                                        Button("Retry") { threadStore.retryThread(thread.id) }
                                    }
                                    Button("Delete") { threadStore.deleteThread(thread.id) }
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(JuniperoTheme.backgroundPrimary)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(JuniperoTheme.textTertiary)
                    .font(.system(size: 14))

                TextField("Search threads...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(JuniperoTheme.textPrimary)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(JuniperoTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(JuniperoTheme.backgroundSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 8) {
                Text("Sort:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(JuniperoTheme.textTertiary)

                ForEach(ThreadSortOrder.allCases) { order in
                    Button(action: { sortOrder = order }) {
                        Text(order.rawValue)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(sortOrder == order ? JuniperoTheme.copper : JuniperoTheme.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(sortOrder == order ? JuniperoTheme.copper.opacity(0.12) : JuniperoTheme.backgroundSurface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text("\(filteredThreads.count) of \(threadStore.threads.count)")
                    .font(.system(size: 11))
                    .foregroundColor(JuniperoTheme.textTertiary)

                if !threadStore.threads.isEmpty {
                    Button("Clear All") { threadStore.clearAllThreads() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(JuniperoTheme.textTertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(JuniperoTheme.textTertiary)
            Text("No threads found")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(JuniperoTheme.textPrimary)
            Text(searchText.isEmpty
                ? "Start a conversation with Hermes to see threads here."
                : "No threads match your search.")
                .font(.system(size: 14))
                .foregroundColor(JuniperoTheme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
