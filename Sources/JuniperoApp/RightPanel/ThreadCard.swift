import SwiftUI

struct ThreadCard: View {
    @EnvironmentObject var threadStore: ThreadStore
    let thread: ChatThread

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                // State dot
                Circle()
                    .fill(stateDotColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: stateDotColor.opacity(0.75), radius: 5)

                Text(thread.formattedDate)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.42))

                Spacer()

                if queuedCount > 0 {
                    Text("Queued \(queuedCount)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(red: 0.65, green: 0.78, blue: 1.0))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(red: 0.28, green: 0.42, blue: 0.88).opacity(0.22)))
                }

                if thread.unreadCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "envelope.badge.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(thread.unreadCount > 1 ? "NEW \(thread.unreadCount)" : "NEW")
                            .font(.system(size: 9, weight: .heavy))
                    }
                    .foregroundColor(Color(red: 0.55, green: 0.88, blue: 1.0))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(red: 0.22, green: 0.45, blue: 0.88).opacity(0.30)))
                }

                statusIcon
            }

            // User message preview
            threadLine(label: "You", text: thread.userMessagePreview, labelColor: Color(red: 0.65, green: 0.78, blue: 1.0))

            // Response
            if thread.isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.55)
                        .tint(Color(red: 0.45, green: 0.65, blue: 1.0))
                    Text("Thrawn is thinking…")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.55, green: 0.72, blue: 1.0))
                }
            } else if thread.state == .failed {
                Text(thread.errorMessage ?? "Request failed.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.55))
                    .lineLimit(2)
            } else {
                threadLine(label: "Thrawn", text: thread.assistantMessagePreview, labelColor: Color.white.opacity(0.70))
                if let model = thread.modelUsed, let latencyMs = thread.latencyMs {
                    Text("\(model) · \(latencyMs)ms")
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.30))
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    thread.unreadCount > 0
                        ? Color(red: 0.14, green: 0.18, blue: 0.28)
                        : Color(red: 0.09, green: 0.11, blue: 0.16)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            thread.unreadCount > 0
                                ? Color(red: 0.30, green: 0.50, blue: 1.0).opacity(0.45)
                                : Color.white.opacity(0.07),
                            lineWidth: 1
                        )
                )
        )
        .shadow(
            color: thread.unreadCount > 0 ? Color(red: 0.28, green: 0.44, blue: 1.0).opacity(0.20) : .clear,
            radius: 10, x: 0, y: 4
        )
        .contentShape(Rectangle())
    }

    private func threadLine(label: String, text: String, labelColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(labelColor)
            Text(text.isEmpty ? "—" : text)
                .font(.system(size: 13))
                .foregroundColor(Color.white.opacity(0.82))
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if thread.isLoading {
            ProgressView().scaleEffect(0.55).tint(.white)
        } else if thread.state == .failed {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(Color(red: 0.95, green: 0.45, blue: 0.42))
        } else {
            EmptyView()
        }
    }

    private var stateDotColor: Color {
        if thread.isLoading { return Color(red: 0.30, green: 0.55, blue: 1.0) }
        if thread.state == .failed { return Color(red: 0.95, green: 0.45, blue: 0.42) }
        if thread.unreadCount > 0 { return Color(red: 0.45, green: 0.72, blue: 1.0) }
        return Color.white.opacity(0.20)
    }

    private var queuedCount: Int {
        threadStore.queuedCount(for: thread.id)
    }
}
