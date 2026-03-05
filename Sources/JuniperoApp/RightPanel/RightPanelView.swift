import SwiftUI

struct RightPanelView: View {
    @EnvironmentObject var threadStore: ThreadStore
    @State private var isComposerOpen = false

    var body: some View {
        VStack(spacing: 0) {
            // MSN-style header bar
            MSNHeaderBar()

            ZStack(alignment: .bottomTrailing) {
                // Thread stack area
                ThreadListView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.6))

                if let selectedId = threadStore.selectedThreadId {
                    ThreadDetailView(threadId: selectedId)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(2)
                }

                VStack(alignment: .trailing, spacing: 10) {
                    if isComposerOpen && threadStore.selectedThreadId == nil {
                        PopupComposerCard(
                            draftText: Binding(
                                get: { threadStore.popupDraftText },
                                set: { threadStore.updatePopupDraft($0) }
                            ),
                            onClose: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                                    isComposerOpen = false
                                }
                            },
                            onSend: {
                                sendFromPopup()
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Button(action: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            isComposerOpen.toggle()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text(isComposerOpen && threadStore.selectedThreadId == nil ? "Hide Chat" : "Chat")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.18, green: 0.36, blue: 0.68),
                                            Color(red: 0.12, green: 0.28, blue: 0.58),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 14)
            }
        }
    }

    private func sendFromPopup() {
        let trimmed = threadStore.popupDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        threadStore.sendMessage(trimmed)
    }
}

struct MSNHeaderBar: View {
    @EnvironmentObject var threadStore: ThreadStore

    var body: some View {
        HStack {
            // O'Brien avatar and status
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Text("O")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("O'Brien")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(statusText)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    threadStore.allThreadsMode.toggle()
                    threadStore.selectedThreadId = nil
                }
            }) {
                Text(threadStore.allThreadsMode ? "Exit All Threads" : "All Threads")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(threadStore.allThreadsMode ? 0.28 : 0.15))
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)

            // Thread count
            Text("\(threadStore.threads.count) conversations")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.36, blue: 0.68),
                    Color(red: 0.12, green: 0.28, blue: 0.58),
                    Color(red: 0.08, green: 0.22, blue: 0.50),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var statusText: String {
        if threadStore.isSending {
            return "Thinking"
        }
        switch threadStore.connectivity {
        case .online:
            return "Online"
        case .offline:
            return "Offline"
        case .unknown:
            return "Unknown"
        }
    }

    private var statusColor: Color {
        if threadStore.isSending {
            return Color(red: 0.95, green: 0.70, blue: 0.20)
        }
        switch threadStore.connectivity {
        case .online:
            return Color(red: 0.30, green: 0.85, blue: 0.30)
        case .offline:
            return Color(red: 0.85, green: 0.25, blue: 0.20)
        case .unknown:
            return Color.white.opacity(0.6)
        }
    }
}

private struct PopupComposerCard: View {
    @EnvironmentObject var threadStore: ThreadStore
    @Binding var draftText: String
    let onClose: () -> Void
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Message O'Brien")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
            }

            TextField("Type your message...", text: $draftText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(Color.black.opacity(0.95))
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.98))
                )
                .lineLimit(1...5)
                .onSubmit {
                    onSend()
                }

            HStack {
                if threadStore.isSending {
                    Text("Sending...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                Button(action: onSend) {
                    Text("Send")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.22, green: 0.48, blue: 0.80))
                        )
                }
                .buttonStyle(.plain)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.36, blue: 0.68),
                            Color(red: 0.10, green: 0.25, blue: 0.50),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
    }
}
