import SwiftUI

struct ThreadCard: View {
    @EnvironmentObject var threadStore: ThreadStore
    let thread: ChatThread

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(thread.formattedDate)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(JuniperoTheme.textTertiary)

                Spacer()

                if threadStore.queuedCount(for: thread.id) > 0 {
                    Text("Queued \(threadStore.queuedCount(for: thread.id))")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(JuniperoTheme.copper)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(JuniperoTheme.copper.opacity(0.12)))
                }

                if thread.unreadCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "envelope.badge.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(thread.unreadCount > 1 ? "NEW \(thread.unreadCount)" : "NEW")
                            .font(.system(size: 9, weight: .heavy))
                    }
                    .foregroundColor(JuniperoTheme.copper)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(JuniperoTheme.copper.opacity(0.15)))
                }

                statusIcon
            }

            messageLine(title: "You", text: thread.userMessagePreview, titleColor: JuniperoTheme.copperLight)

            if thread.isLoading {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.55)
                    Text("Hermes is thinking...")
                        .font(.system(size: 12))
                        .foregroundColor(JuniperoTheme.textSecondary)
                }
            } else if thread.state == .failed {
                Text(thread.errorMessage ?? "Request failed.")
                    .font(.system(size: 12))
                    .foregroundColor(JuniperoTheme.statusError)
                    .lineLimit(2)
            } else {
                messageLine(title: "Hermes", text: thread.assistantMessagePreview, titleColor: JuniperoTheme.textSecondary)
                if let model = thread.modelUsed, let latencyMs = thread.latencyMs {
                    Text("\(model) \u{2022} \(latencyMs)ms")
                        .font(.system(size: 10))
                        .foregroundColor(JuniperoTheme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(JuniperoTheme.backgroundSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    thread.unreadCount > 0
                        ? JuniperoTheme.copper.opacity(0.4)
                        : JuniperoTheme.divider,
                    lineWidth: thread.unreadCount > 0 ? 1.2 : 0.6
                )
        )
        .shadow(
            color: thread.unreadCount > 0 ? JuniperoTheme.copper.opacity(0.15) : .clear,
            radius: thread.unreadCount > 0 ? 10 : 0
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusIcon: some View {
        if thread.isLoading {
            ProgressView().scaleEffect(0.55)
        } else if thread.state == .failed {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(JuniperoTheme.statusError)
        } else {
            EmptyView()
        }
    }

    private func messageLine(title: String, text: String, titleColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(titleColor)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(JuniperoTheme.textPrimary)
                .lineLimit(2)
        }
    }
}
