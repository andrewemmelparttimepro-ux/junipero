import SwiftUI

struct ThreadCard: View {
    @EnvironmentObject var threadStore: ThreadStore
    let thread: ChatThread

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(thread.formattedDate)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.black.opacity(0.7))
                Spacer()
                if queuedCount > 0 {
                    Text("Queued \(queuedCount)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(red: 0.18, green: 0.32, blue: 0.58))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.88, green: 0.93, blue: 0.99))
                        )
                }
                if thread.unreadCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "envelope.badge.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(thread.unreadCount > 1 ? "NEW \(thread.unreadCount)" : "NEW")
                            .font(.system(size: 9, weight: .heavy))
                    }
                    .foregroundColor(Color(red: 0.08, green: 0.28, blue: 0.06))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.56, green: 0.98, blue: 0.46))
                    )
                }
                statusIcon
            }

            line(title: "Andrew", text: thread.userMessagePreview, titleColor: Color(red: 0.14, green: 0.32, blue: 0.62))

            if thread.isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.55)
                    Text("Thrawn is thinking...")
                        .font(.system(size: 12))
                        .foregroundColor(Color.black.opacity(0.72))
                }
            } else if thread.state == .failed {
                Text(thread.errorMessage ?? "Request failed.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.75, green: 0.20, blue: 0.20))
                    .lineLimit(2)
            } else {
                line(title: "Thrawn", text: thread.assistantMessagePreview, titleColor: Color.black.opacity(0.8))
                if let model = thread.modelUsed, let latencyMs = thread.latencyMs {
                    Text("\(model) • \(latencyMs)ms")
                        .font(.system(size: 10))
                        .foregroundColor(Color.black.opacity(0.68))
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    thread.unreadCount > 0
                        ? Color.white.opacity(0.88)
                        : Color.white.opacity(0.82)
                )
        )
        .overlay {
            if thread.unreadCount > 0 {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.66, green: 0.98, blue: 0.62).opacity(0.28),
                                Color(red: 0.40, green: 0.92, blue: 0.48).opacity(0.20),
                                Color(red: 0.22, green: 0.72, blue: 0.28).opacity(0.16),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.45),
                                        Color.white.opacity(0.10),
                                        Color.clear,
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .allowsHitTesting(false)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    thread.unreadCount > 0
                        ? Color(red: 0.34, green: 0.85, blue: 0.28).opacity(0.8)
                        : Color.black.opacity(0.06),
                    lineWidth: thread.unreadCount > 0 ? 1.2 : 0.6
                )
        )
        .shadow(
            color: thread.unreadCount > 0 ? Color(red: 0.42, green: 0.94, blue: 0.32).opacity(0.35) : .clear,
            radius: thread.unreadCount > 0 ? 10 : 0,
            x: 0,
            y: 0
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    thread.unreadCount > 0
                        ? LinearGradient(
                            colors: [
                                Color.white.opacity(0.78),
                                Color.white.opacity(0.26),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        : LinearGradient(
                            colors: [Color.clear, Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                    lineWidth: thread.unreadCount > 0 ? 0.9 : 0
                )
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusIcon: some View {
        if thread.isLoading {
            ProgressView()
                .scaleEffect(0.55)
        } else if thread.state == .failed {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(Color(red: 0.85, green: 0.25, blue: 0.20))
        } else {
            EmptyView()
        }
    }

    private func line(title: String, text: String, titleColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(titleColor)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Color.black.opacity(0.92))
                .lineLimit(2)
        }
    }

    private var queuedCount: Int {
        threadStore.queuedCount(for: thread.id)
    }
}
