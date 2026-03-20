import SwiftUI

// MARK: - Flow View
// The "other side" of the switch — shows Hermes agent workflow,
// active tasks, tool calls, and thinking chain in real-time.

struct FlowView: View {
    @EnvironmentObject var threadStore: ThreadStore
    @EnvironmentObject var bootstrap: HermesBootstrap

    var body: some View {
        VStack(spacing: 0) {
            if threadStore.threads.isEmpty {
                emptyState
            } else {
                flowContent
            }
        }
        .background(JuniperoTheme.backgroundPrimary)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundColor(JuniperoTheme.textTertiary)

            Text("No activity yet")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(JuniperoTheme.textSecondary)

            Text("Start a conversation and the flow will appear here.")
                .font(.system(size: 12))
                .foregroundColor(JuniperoTheme.textTertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Flow Content

    private var flowContent: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(threadStore.threads) { thread in
                    FlowThreadRow(thread: thread)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Flow Thread Row

struct FlowThreadRow: View {
    let thread: ChatThread
    @EnvironmentObject var threadStore: ThreadStore

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                threadStore.selectedThreadId = thread.id
            }
        }) {
            HStack(spacing: 14) {
                // State indicator
                stateIndicator

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    // Latest message preview
                    Text(thread.userMessagePreview)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(JuniperoTheme.textPrimary)
                        .lineLimit(1)

                    if !thread.assistantMessagePreview.isEmpty {
                        Text(thread.assistantMessagePreview)
                            .font(.system(size: 12))
                            .foregroundColor(JuniperoTheme.textTertiary)
                            .lineLimit(1)
                    }

                    // Meta row
                    HStack(spacing: 10) {
                        Text(thread.formattedDate)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(JuniperoTheme.textTertiary)

                        Text("\(thread.messages.count) msgs")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(JuniperoTheme.textTertiary)

                        if threadStore.queuedCount(for: thread.id) > 0 {
                            Text("\(threadStore.queuedCount(for: thread.id)) queued")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(JuniperoTheme.statusWarning)
                        }
                    }
                }

                Spacer()

                // State badge
                if thread.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                } else if thread.state == .failed {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 12))
                        .foregroundColor(JuniperoTheme.statusError)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                threadStore.selectedThreadId == thread.id
                    ? JuniperoTheme.backgroundElevated
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var stateIndicator: some View {
        let color: Color = {
            if thread.isLoading { return JuniperoTheme.statusOnline }
            switch thread.state {
            case .pending: return JuniperoTheme.statusWarning
            case .success: return JuniperoTheme.textTertiary
            case .failed: return JuniperoTheme.statusError
            }
        }()

        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
    }
}
