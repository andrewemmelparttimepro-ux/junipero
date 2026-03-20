import SwiftUI
import UniformTypeIdentifiers

enum RightPanelTab: String, CaseIterable, Identifiable {
    case command = "Command"
    case threads = "Threads"
    case tasks = "Tasks"
    case review = "Review"
    case approvals = "Approvals"
    case deliverables = "Deliverables"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .command: return "terminal"
        case .threads: return "bubble.left.and.bubble.right"
        case .tasks: return "checklist"
        case .review: return "doc.text.magnifyingglass"
        case .approvals: return "checkmark.seal"
        case .deliverables: return "tray.full"
        }
    }
}

struct RightPanelView: View {
    @EnvironmentObject var bootstrap: HermesBootstrap
    @EnvironmentObject var threadStore: ThreadStore
    @State private var selectedTab: RightPanelTab = .command
    @State private var isComposerOpen = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            tabBar

            Rectangle()
                .fill(JuniperoTheme.divider)
                .frame(height: 1)

            ZStack {
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Thread detail overlay
                if let selectedId = threadStore.selectedThreadId {
                    ThreadDetailView(threadId: selectedId)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(2)
                }
            }
        }
        .background(JuniperoTheme.backgroundPrimary)
        .overlay(alignment: .bottomTrailing) {
            composerFAB
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [JuniperoTheme.copper, JuniperoTheme.copperDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)
                .overlay(
                    Text("H")
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundColor(JuniperoTheme.textPrimary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Hermes")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(JuniperoTheme.textPrimary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(healthDotColor)
                        .frame(width: 7, height: 7)

                    Text(bootstrap.statusText)
                        .font(.system(size: 11))
                        .foregroundColor(JuniperoTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if threadStore.unreadThreadCount > 0 {
                    Text("\(threadStore.unreadThreadCount) NEW")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(JuniperoTheme.copper)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(JuniperoTheme.copper.opacity(0.15))
                        )
                }

                Text("\(threadStore.threads.count) conv")
                    .font(.system(size: 11))
                    .foregroundColor(JuniperoTheme.textTertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(JuniperoTheme.backgroundSecondary)
    }

    private var healthDotColor: Color {
        if threadStore.isSending {
            return JuniperoTheme.statusThinking
        }
        if bootstrap.hermesHealthy {
            return JuniperoTheme.statusOnline
        }
        if bootstrap.isWorking {
            return JuniperoTheme.statusWarning
        }
        return JuniperoTheme.statusError
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(RightPanelTab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(JuniperoTheme.backgroundSecondary.opacity(0.7))
    }

    private func tabButton(for tab: RightPanelTab) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
                threadStore.selectedThreadId = nil
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(selectedTab == tab ? JuniperoTheme.copper : JuniperoTheme.textTertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                selectedTab == tab ? JuniperoTheme.copper.opacity(0.12) : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .command:
            CommandView()
        case .threads:
            ThreadsView()
        case .tasks:
            TasksView()
        case .review:
            ReviewView()
        case .approvals:
            ApprovalsView()
        case .deliverables:
            DeliverablesView()
        }
    }

    // MARK: - Composer FAB

    private var composerFAB: some View {
        Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                isComposerOpen.toggle()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(isComposerOpen ? "Hide" : "Chat")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(JuniperoTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [JuniperoTheme.copper, JuniperoTheme.copperDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .shadow(color: JuniperoTheme.copper.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.bottom, 14)
    }
}
