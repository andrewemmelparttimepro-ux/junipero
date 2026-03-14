import SwiftUI
import UniformTypeIdentifiers

struct RightPanelView: View {
    @EnvironmentObject var threadStore: ThreadStore
    @EnvironmentObject var nav: ConsoleNavigationStore
    @EnvironmentObject var roster: AgentRosterStore

    var body: some View {
        VStack(spacing: 0) {
            ThrawnHeaderBar()

            switch nav.selectedSection {
            case .command:
                CommandPanelView()
            case .tasks:
                ConsoleSectionBody()
            case .review:
                ConsoleSectionBody()
            case .approvals:
                ConsoleSectionBody()
            case .deliverables:
                ConsoleSectionBody()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - Command Panel (default view, Junipero-style simplicity)

struct CommandPanelView: View {
    @EnvironmentObject var threadStore: ThreadStore

    var body: some View {
        VStack(spacing: 0) {
            // Chat input at the top
            ChatInputView()

            // Threads populate chronologically below, newest at top
            // When they overflow they simply disappear — no scroll here
            InlineThreadFeedView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// Inline thread feed — shows as many recent threads as fit, no scroll
struct InlineThreadFeedView: View {
    @EnvironmentObject var threadStore: ThreadStore

    // Show the N most recent threads; the view clips naturally when it runs out of space
    private var recentThreads: [ChatThread] {
        threadStore.threads
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                if recentThreads.isEmpty {
                    VStack(spacing: 10) {
                        Spacer()
                        Text("No threads yet.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.35))
                        Text("Send a message above to start.")
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.22))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(recentThreads) { thread in
                        Button {
                            threadStore.selectedThreadId = thread.id
                            withAnimation(.easeInOut(duration: 0.18)) {
                                nav_push_thread()
                            }
                        } label: {
                            InlineThreadRow(thread: thread)
                        }
                        .buttonStyle(.plain)
                        Divider()
                            .background(Color.white.opacity(0.06))
                    }
                }
            }
            .frame(width: geo.size.width, alignment: .topLeading)
            .clipped()
        }
    }

    private func nav_push_thread() {
        // handled by ThreadDetailView sheet triggered by selectedThreadId
    }
}

struct InlineThreadRow: View {
    @EnvironmentObject var threadStore: ThreadStore
    let thread: ChatThread

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // State dot
            Circle()
                .fill(thread.isLoading ? Color(red: 0.30, green: 0.55, blue: 1.0) :
                      thread.state == .failed ? Color(red: 0.95, green: 0.35, blue: 0.32) :
                      Color.white.opacity(0.25))
                .frame(width: 7, height: 7)
                .shadow(color: thread.isLoading ? Color(red: 0.30, green: 0.55, blue: 1.0).opacity(0.7) : .clear, radius: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(thread.userMessagePreview.isEmpty ? "…" : thread.userMessagePreview)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.88))
                        .lineLimit(1)
                    Spacer()
                    Text(thread.formattedDate)
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.38))
                }

                if thread.isLoading {
                    Text("Thrawn is thinking…")
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(red: 0.55, green: 0.72, blue: 1.0))
                } else if thread.state == .failed {
                    Text(thread.errorMessage ?? "Failed")
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.55))
                        .lineLimit(1)
                } else {
                    Text(thread.assistantMessagePreview.isEmpty ? "—" : thread.assistantMessagePreview)
                        .font(.system(size: 11.5))
                        .foregroundColor(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            thread.unreadCount > 0
                ? Color(red: 0.22, green: 0.32, blue: 0.58).opacity(0.18)
                : Color.clear
        )
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if threadStore.selectedThreadId == thread.id {
                Rectangle()
                    .fill(Color(red: 0.30, green: 0.52, blue: 1.0).opacity(0.22))
                    .frame(height: 1)
            }
        }
    }
}

// MARK: - Header

struct ThrawnHeaderBar: View {
    @EnvironmentObject var threadStore: ThreadStore
    @EnvironmentObject var bootstrap: ThrawnBootstrap
    @EnvironmentObject var updateManager: UpdateManager
    @EnvironmentObject var sparkleUpdater: SparkleUpdaterService
    @EnvironmentObject var nav: ConsoleNavigationStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Status dot + name
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: statusColor.opacity(0.80), radius: 7)
                    Text("THRAWN")
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .tracking(3)
                        .foregroundColor(.white)
                    Text("·")
                        .foregroundColor(Color.white.opacity(0.3))
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.62, green: 0.76, blue: 0.96))
                }

                Spacer()

                HStack(spacing: 6) {
                    thrawnButton("Setup") { bootstrap.showSetup = true }
                    thrawnButton("Updates") { sparkleUpdater.checkForUpdates() }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Section tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ConsoleSection.allCases) { section in
                        Button { nav.selectedSection = section } label: {
                            HStack(spacing: 5) {
                                Image(systemName: section.icon)
                                    .font(.system(size: 10, weight: .bold))
                                Text(section.rawValue)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.white.opacity(nav.selectedSection == section ? 0.98 : 0.68))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(nav.selectedSection == section ? Color(red: 0.25, green: 0.40, blue: 0.90) : Color.white.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                    }

                    // Threads tab — opens full thread browser
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            threadStore.allThreadsMode.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Threads")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(threadStore.allThreadsMode ? 0.98 : 0.68))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(threadStore.allThreadsMode ? Color(red: 0.25, green: 0.40, blue: 0.90) : Color.white.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.12, blue: 0.18),
                    Color(red: 0.06, green: 0.08, blue: 0.12),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            // Show full thread browser over the panel
            if threadStore.allThreadsMode {
                ThreadBrowserOverlay()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        // Show thread detail when a thread is selected
        .overlay {
            if let selectedId = threadStore.selectedThreadId {
                ThreadDetailView(threadId: selectedId)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(5)
            }
        }
    }

    private var statusText: String {
        if threadStore.isSending { return "Stream active" }
        if bootstrap.openClawHealthy { return "Gateway aligned" }
        switch threadStore.connectivity {
        case .online: return "Gateway aligned"
        case .offline: return "Gateway unavailable"
        case .unknown: return "Connecting…"
        }
    }

    private var statusColor: Color {
        if threadStore.isSending { return Color(red: 0.30, green: 0.55, blue: 1.0) }
        if bootstrap.openClawHealthy { return Color(red: 0.38, green: 0.72, blue: 1.0) }
        switch threadStore.connectivity {
        case .online: return Color(red: 0.38, green: 0.72, blue: 1.0)
        case .offline: return Color(red: 0.95, green: 0.36, blue: 0.34)
        case .unknown: return Color.white.opacity(0.45)
        }
    }

    private func thrawnButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.80))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full Threads Browser (Threads tab)

struct ThreadBrowserOverlay: View {
    @EnvironmentObject var threadStore: ThreadStore

    private var sortedThreads: [ChatThread] {
        threadStore.threads.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Threads")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        threadStore.allThreadsMode = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

            if sortedThreads.isEmpty {
                Spacer()
                Text("No threads yet.")
                    .foregroundColor(.white.opacity(0.35))
                    .font(.system(size: 13))
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedThreads) { thread in
                            Button {
                                threadStore.selectedThreadId = thread.id
                                withAnimation { threadStore.allThreadsMode = false }
                            } label: {
                                InlineThreadRow(thread: thread)
                            }
                            .buttonStyle(.plain)
                            Divider().background(Color.white.opacity(0.06))
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.05, green: 0.07, blue: 0.11).opacity(0.99))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
