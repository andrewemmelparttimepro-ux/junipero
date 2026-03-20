import SwiftUI

struct ChatInputView: View {
    @EnvironmentObject var threadStore: ThreadStore
    @State private var messageText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // MSN-style separator
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.70, blue: 0.88),
                            Color(red: 0.45, green: 0.60, blue: 0.80),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)

            // Input area with MSN blue chrome
            VStack(spacing: 8) {
                // MSN-style mini toolbar
                HStack(spacing: 12) {
                    Text("💬")
                        .font(.system(size: 12))
                    Text("Send a command to Thrawn")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.88))
                    Spacer()

                    // Emoji shortcode hint
                    Text(threadStore.isSending ? "Sending..." : "MSN shortcuts: :-) (y) (L)")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.72))
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                if let error = threadStore.lastErrorText {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 1.0, green: 0.92, blue: 0.92))
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                }

                // Text field + Send button
                HStack(spacing: 10) {
                    TextField("Type a message...", text: $messageText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundColor(Color.black.opacity(0.95))
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        )
                        .lineLimit(1...4)
                        .focused($isFocused)
                        .onSubmit {
                            sendMessage()
                        }

                    Button(action: sendMessage) {
                        HStack(spacing: 5) {
                            Text("Send")
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(sendButtonColor)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.22, green: 0.40, blue: 0.65),
                        Color(red: 0.16, green: 0.32, blue: 0.55),
                        Color(red: 0.12, green: 0.26, blue: 0.48),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var sendButtonColor: Color {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Color.white.opacity(0.15)
            : Color(red: 0.25, green: 0.50, blue: 0.80)
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        threadStore.sendMessage(trimmed)
        messageText = ""
    }
}
