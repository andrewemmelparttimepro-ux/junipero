import SwiftUI

struct ChatInputView: View {
    @EnvironmentObject var threadStore: ThreadStore
    @EnvironmentObject var bootstrap: HermesBootstrap
    @State private var messageText = ""
    @State private var isSending = false
    @FocusState private var isInputFocused: Bool

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && bootstrap.hermesHealthy
    }

    var body: some View {
        VStack(spacing: 8) {
            if let error = threadStore.lastErrorText {
                errorBanner(error)
            }

            inputRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    JuniperoTheme.backgroundSecondary,
                    JuniperoTheme.backgroundSecondary.opacity(0.95)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(JuniperoTheme.statusError)

            Text(error)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(JuniperoTheme.statusError)
                .lineLimit(2)

            Spacer()

            Button(action: {
                threadStore.lastErrorText = nil
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(JuniperoTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(JuniperoTheme.statusError.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Input Row

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextEditor(text: $messageText)
                .font(.system(size: 14))
                .foregroundColor(JuniperoTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .focused($isInputFocused)
                .frame(minHeight: 36, maxHeight: 120)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(JuniperoTheme.backgroundSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isInputFocused
                                ? JuniperoTheme.copper.opacity(0.4)
                                : JuniperoTheme.divider,
                            lineWidth: 1
                        )
                )
                .overlay(alignment: .topLeading) {
                    if messageText.isEmpty {
                        Text("Message Hermes")
                            .font(.system(size: 14))
                            .foregroundColor(JuniperoTheme.textTertiary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }

            sendButton
        }
    }

    // MARK: - Send Button

    private var sendButton: some View {
        Button(action: sendMessage) {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(
                    canSend ? JuniperoTheme.textPrimary : JuniperoTheme.textTertiary
                )
                .frame(width: 38, height: 38)
                .background(
                    Group {
                        if canSend {
                            LinearGradient(
                                colors: [JuniperoTheme.copper, JuniperoTheme.copperDark],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        } else {
                            LinearGradient(
                                colors: [JuniperoTheme.backgroundElevated, JuniperoTheme.backgroundElevated],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    }
                )
                .clipShape(Capsule())
                .shadow(
                    color: canSend ? JuniperoTheme.copper.opacity(0.3) : Color.clear,
                    radius: 6,
                    x: 0,
                    y: 2
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .keyboardShortcut(.return, modifiers: [])
    }

    // MARK: - Actions

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        threadStore.sendMessage(trimmed)
        messageText = ""
        isSending = false
    }
}
