import SwiftUI
#if os(macOS)
import AppKit
#endif
import UniformTypeIdentifiers

struct ThreadDetailView: View {
    @EnvironmentObject var threadStore: ThreadStore
    let threadId: UUID
    @FocusState private var isReplyFocused: Bool
    @State private var isDropTargeted = false

    private var thread: ChatThread? {
        threadStore.threads.first(where: { $0.id == threadId })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Thread")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(JuniperoTheme.textPrimary)
                Spacer()
                if let thread {
                    Text(thread.formattedDate)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(JuniperoTheme.textTertiary)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        threadStore.selectedThreadId = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(JuniperoTheme.copper)
                        .frame(width: 28, height: 28)
                        .background(JuniperoTheme.copper.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(JuniperoTheme.backgroundSecondary)

            // Messages
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(spacing: 10) {
                        if let thread {
                            ForEach(thread.messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }

                            if thread.isLoading {
                                HStack {
                                    ProgressView().scaleEffect(0.6)
                                    Text("Hermes is thinking...")
                                        .font(.system(size: 12))
                                        .foregroundColor(JuniperoTheme.textSecondary)
                                    Spacer()
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(JuniperoTheme.assistantBubble))
                            } else if thread.state == .failed {
                                HStack {
                                    Text(thread.errorMessage ?? "Request failed.")
                                        .font(.system(size: 12))
                                        .foregroundColor(JuniperoTheme.statusError)
                                    Spacer()
                                    Button("Retry") { threadStore.retryThread(thread.id) }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(JuniperoTheme.copper)
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(JuniperoTheme.backgroundSurface))
                            }
                        }
                        Color.clear.frame(height: 1).id(bottomAnchorId)
                    }
                    .padding(12)
                    .onAppear { scrollToBottom(proxy: proxy, animated: false) }
                    .onChange(of: thread?.messages.count ?? 0) { _ in
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
            }
            .background(JuniperoTheme.backgroundPrimary)

            // Reply input
            HStack(spacing: 10) {
                TextField("Reply to this thread...", text: replyTextBinding, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(JuniperoTheme.textPrimary)
                    .lineLimit(1...5)
                    .focused($isReplyFocused)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(JuniperoTheme.backgroundSurface))
                    .onSubmit { sendReply() }

                Button(action: sendReply) {
                    Text("Send")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(JuniperoTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(JuniperoTheme.copper))
                }
                .buttonStyle(.plain)
                .disabled(replyTextBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            .background(JuniperoTheme.backgroundSecondary)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(JuniperoTheme.copper.opacity(0.15), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 8)
        .onAppear {
            threadStore.markThreadRead(threadId)
            DispatchQueue.main.async { isReplyFocused = true }
        }
    }

    private func sendReply() {
        let text = replyTextBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        threadStore.sendMessage(in: threadId, text: text)
        DispatchQueue.main.async { isReplyFocused = true }
    }

    private var replyTextBinding: Binding<String> {
        Binding(
            get: { threadStore.draftText(for: threadId) },
            set: { threadStore.updateThreadDraft(threadId: threadId, text: $0) }
        )
    }

    private var bottomAnchorId: String { "thread-bottom-\(threadId.uuidString)" }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        let action = { proxy.scrollTo(bottomAnchorId, anchor: .bottom) }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { action() }
        } else {
            action()
        }
    }
}

// MARK: - Message Bubble (shared)

struct MessageBubble: View {
    let message: ChatMessage
    @State private var copied = false

    var body: some View {
        HStack {
            if message.role == .assistant {
                bubble(text: message.text, isUser: false)
                Spacer(minLength: 20)
            } else {
                Spacer(minLength: 20)
                bubble(text: message.text, isUser: true)
            }
        }
    }

    @ViewBuilder
    private func bubble(text: String, isUser: Bool) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(JuniperoTheme.textPrimary)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .padding(.top, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isUser ? JuniperoTheme.userBubble : JuniperoTheme.assistantBubble)
            )
            .overlay(alignment: .topTrailing) {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        copyToClipboard(text)
                    } label: {
                        Image(systemName: copied ? "checkmark" : "clipboard")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(JuniperoTheme.textSecondary)
                            .padding(5)
                            .background(Circle().fill(JuniperoTheme.backgroundElevated))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
            }
            .contextMenu {
                Button("Copy") { copyToClipboard(text) }
            }
    }

    private func copyToClipboard(_ text: String) {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#endif
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run { copied = false }
        }
    }
}
