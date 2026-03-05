import SwiftUI

private enum ThreadFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case failed = "Failed"
    case active = "Active"
    case recent = "24h"

    var id: String { rawValue }
}

private enum ThreadSort: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"
    case errorsFirst = "Errors First"

    var id: String { rawValue }
}

struct ThreadListView: View {
    @EnvironmentObject var threadStore: ThreadStore
    @State private var searchText: String = ""
    @State private var filter: ThreadFilter = .all
    @State private var sort: ThreadSort = .newest

    private var displayedThreads: [ChatThread] {
        let filtered = threadStore.threads.filter { thread in
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let q = searchText.lowercased()
                let hay = (thread.latestUserText + " " + thread.latestAssistantText).lowercased()
                if !hay.contains(q) {
                    return false
                }
            }

            switch filter {
            case .all:
                return true
            case .failed:
                return thread.state == .failed
            case .active:
                return thread.isLoading
            case .recent:
                return Date().timeIntervalSince(thread.updatedAt) <= 86_400
            }
        }

        switch sort {
        case .newest:
            return filtered.sorted { $0.updatedAt > $1.updatedAt }
        case .oldest:
            return filtered.sorted { $0.updatedAt < $1.updatedAt }
        case .errorsFirst:
            return filtered.sorted { lhs, rhs in
                let l = lhs.state == .failed ? 0 : 1
                let r = rhs.state == .failed ? 0 : 1
                if l == r { return lhs.updatedAt > rhs.updatedAt }
                return l < r
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            controlsBar

            if threadStore.threads.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Text("🌙")
                        .font(.system(size: 40))
                    Text("No conversations yet")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Click Chat in the bottom-right to start")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                Spacer()
            } else if displayedThreads.isEmpty {
                Spacer()
                Text("No threads match your filter.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.8))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(displayedThreads) { thread in
                            ThreadCard(thread: thread)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        threadStore.selectedThreadId = thread.id
                                        threadStore.markThreadRead(thread.id)
                                    }
                                }
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .contextMenu {
                                    if thread.state == .failed {
                                        Button("Retry") {
                                            threadStore.retryThread(thread.id)
                                        }
                                    }
                                    if thread.isLoading {
                                        Button("Cancel") {
                                            threadStore.cancelRequest(for: thread.id)
                                        }
                                    }
                                    if threadStore.queuedCount(for: thread.id) > 0 {
                                        Button("Clear Queue") {
                                            threadStore.clearQueuedMessages(for: thread.id)
                                        }
                                    }
                                    Button("Delete") {
                                        threadStore.deleteThread(thread.id)
                                    }
                                }
                        }
                    }
                    .padding(12)
                    .animation(.spring(response: 0.36, dampingFraction: 0.86), value: threadStore.threads.map(\.id))
                }
            }
        }
    }

    private var controlsBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                TextField("Search threads…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(Color.black.opacity(0.92))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.92))
                    )

                Menu {
                    Picker("Filter", selection: $filter) {
                        ForEach(ThreadFilter.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    Picker("Sort", selection: $sort) {
                        ForEach(ThreadSort.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 16))
                        .foregroundColor(Color.black.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("Showing \(displayedThreads.count) of \(threadStore.threads.count)")
                    .font(.system(size: 11))
                    .foregroundColor(Color.black.opacity(0.6))
                Spacer()
                if queuedTotal > 0 {
                    Text("\(queuedTotal) queued")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.18, green: 0.32, blue: 0.58))
                }
                if !threadStore.threads.isEmpty {
                    Button("Clear All") {
                        threadStore.clearAllThreads()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.black.opacity(0.65))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var queuedTotal: Int {
        threadStore.threads.reduce(into: 0) { partial, thread in
            partial += threadStore.queuedCount(for: thread.id)
        }
    }
}
