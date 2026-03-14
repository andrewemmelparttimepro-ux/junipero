import SwiftUI

struct ChatInputView: View {
    @EnvironmentObject var threadStore: ThreadStore
    @State private var messageText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            VStack(spacing: 10) {
                // Error line
                if let error = threadStore.lastErrorText {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text(error)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .foregroundColor(Color(red: 1.0, green: 0.72, blue: 0.72))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                HStack(alignment: .bottom, spacing: 10) {
                    // Input field
                    ZStack(alignment: .topLeading) {
                        if messageText.isEmpty {
                            Text("Issue a command to Thrawn…")
                                .font(.system(size: 13))
                                .foregroundColor(Color.white.opacity(0.28))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $messageText)
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.92))
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .focused($isFocused)
                            .frame(minHeight: 40, maxHeight: 120)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(isFocused ? 0.07 : 0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(
                                        isFocused
                                            ? Color(red: 0.30, green: 0.50, blue: 1.0).opacity(0.55)
                                            : Color.white.opacity(0.08),
                                        lineWidth: 1
                                    )
                            )
                    )

                    // Send button
                    Button(action: sendMessage) {
                        ZStack {
                            if threadStore.isSending {
                                ProgressView()
                                    .scaleEffect(0.65)
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(canSend ? .white : Color.white.opacity(0.30))
                            }
                        }
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(
                                    canSend
                                        ? LinearGradient(
                                            colors: [
                                                Color(red: 0.30, green: 0.48, blue: 1.0),
                                                Color(red: 0.18, green: 0.32, blue: 0.82),
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        : LinearGradient(
                                            colors: [Color.white.opacity(0.06), Color.white.opacity(0.06)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                )
                        )
                        .shadow(
                            color: canSend ? Color(red: 0.28, green: 0.44, blue: 1.0).opacity(0.45) : .clear,
                            radius: 8
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .padding(.top, 8)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.09, blue: 0.13),
                        Color(red: 0.05, green: 0.07, blue: 0.10),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .onAppear { isFocused = true }
    }

    private var canSend: Bool {
        !threadStore.isSending && !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !threadStore.isSending else { return }
        threadStore.sendMessage(trimmed)
        messageText = ""
    }
}
