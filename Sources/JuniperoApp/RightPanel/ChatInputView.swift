import SwiftUI
import UniformTypeIdentifiers

struct ChatInputView: View {
    @EnvironmentObject var threadStore: ThreadStore
    @State private var messageText = ""
    @FocusState private var isFocused: Bool
    @State private var isDraggingOver = false
    @State private var droppedFileInfo: String? = nil

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
                    Text("Send a message to O'Brien")
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

                // Dropped file info banner
                if let fileInfo = droppedFileInfo {
                    HStack(spacing: 6) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 10))
                        Text(fileInfo)
                            .font(.system(size: 10))
                            .lineLimit(1)
                        Spacer()
                        Button(action: { droppedFileInfo = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundColor(Color(red: 0.80, green: 0.95, blue: 1.0))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                    .padding(.horizontal, 14)
                }

                // Text field + Send button
                HStack(spacing: 10) {
                    ZStack {
                        TextField("Type a message...", text: $messageText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundColor(Color.black.opacity(0.95))
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isDraggingOver
                                        ? Color(red: 0.75, green: 0.93, blue: 1.0)
                                        : Color.white
                                    )
                                    .shadow(color: isDraggingOver
                                        ? Color(red: 0.0, green: 0.6, blue: 0.9).opacity(0.6)
                                        : .black.opacity(0.10),
                                        radius: isDraggingOver ? 6 : 2, x: 0, y: 1)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isDraggingOver
                                                ? Color(red: 0.0, green: 0.70, blue: 1.0)
                                                : Color.clear,
                                                lineWidth: 2)
                                    )
                            )
                            .lineLimit(1...4)
                            .focused($isFocused)
                            .onSubmit {
                                sendMessage()
                            }

                        // Drop overlay indicator
                        if isDraggingOver {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(red: 0.0, green: 0.70, blue: 1.0).opacity(0.12))
                                .overlay(
                                    VStack(spacing: 4) {
                                        Image(systemName: "arrow.down.doc.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(Color(red: 0.0, green: 0.70, blue: 1.0))
                                        Text("Drop file to attach")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(Color(red: 0.0, green: 0.70, blue: 1.0))
                                    }
                                )
                                .allowsHitTesting(false)
                        }
                    }
                    .onDrop(of: [UTType.item], isTargeted: $isDraggingOver) { providers in
                        handleDrop(providers: providers)
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
            .animation(.easeInOut(duration: 0.15), value: isDraggingOver)
        }
    }

    private var sendButtonColor: Color {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Color.white.opacity(0.15)
            : Color(red: 0.25, green: 0.50, blue: 0.80)
    }

    private func sendMessage() {
        var trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || droppedFileInfo != nil else { return }

        // Prepend file path info if a file was dropped
        if let fileInfo = droppedFileInfo {
            if trimmed.isEmpty {
                trimmed = fileInfo
            } else {
                trimmed = "\(fileInfo)\n\(trimmed)"
            }
            droppedFileInfo = nil
        }

        threadStore.sendMessage(trimmed)
        messageText = ""
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Try to load a file URL first
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                DispatchQueue.main.async {
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        self.droppedFileInfo = url.path
                    } else if let url = item as? URL {
                        self.droppedFileInfo = url.path
                    }
                }
            }
            return true
        }

        // Fallback: try generic URL
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                DispatchQueue.main.async {
                    if let url = url {
                        self.droppedFileInfo = url.path
                    }
                }
            }
            return true
        }

        return false
    }
}
