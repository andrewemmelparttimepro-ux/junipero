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
            // Thread header
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        threadStore.selectedThreadId = nil
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.75))
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Thread")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                    if let thread {
                        Text(thread.formattedDate)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.42))
                    }
                }

                Spacer()

                if queuedCount > 0 {
                    HStack(spacing: 6) {
                        Text("\(queuedCount) queued")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(red: 0.65, green: 0.78, blue: 1.0))
                        Button("Clear") {
                            threadStore.clearQueuedMessages(for: threadId)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(red: 0.65, green: 0.78, blue: 1.0))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(red: 0.28, green: 0.42, blue: 0.88).opacity(0.22)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(red: 0.07, green: 0.09, blue: 0.13))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }

            // Messages
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(spacing: 12) {
                        if let thread {
                            ForEach(thread.messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }

                            if thread.isLoading {
                                HStack(spacing: 10) {
                                    ProgressView()
                                        .scaleEffect(0.65)
                                        .tint(Color(red: 0.45, green: 0.65, blue: 1.0))
                                    Text("Thrawn is thinking…")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(red: 0.55, green: 0.72, blue: 1.0))
                                    Spacer()
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
                                .id("loading-\(thread.id.uuidString)")
                            } else if thread.state == .failed {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.55))
                                    Text(thread.errorMessage ?? "Request failed.")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.55))
                                    Spacer()
                                    Button("Retry") {
                                        threadStore.retryThread(thread.id)
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color(red: 0.55, green: 0.72, blue: 1.0))
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.95, green: 0.35, blue: 0.32).opacity(0.10)))
                                .id("failed-\(thread.id.uuidString)")
                            }
                        }
                        Color.clear.frame(height: 1).id(bottomAnchorId)
                    }
                    .padding(14)
                    .onAppear { scrollToBottom(proxy: proxy, animated: false) }
                    .onChange(of: thread?.messages.count ?? 0) { _ in scrollToBottom(proxy: proxy, animated: true) }
                    .onChange(of: thread?.isLoading ?? false) { _ in scrollToBottom(proxy: proxy, animated: true) }
                }
            }
            .background(Color(red: 0.05, green: 0.06, blue: 0.09))

            // Attachment strip
            if !threadStore.attachments(for: threadId).isEmpty {
                ThreadAttachmentStrip(
                    attachments: threadStore.attachments(for: threadId),
                    onRemove: { id in threadStore.removeAttachment(threadId: threadId, attachmentId: id) }
                )
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .background(Color(red: 0.06, green: 0.08, blue: 0.11))
            }

            // Reply input
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

            HStack(alignment: .bottom, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    let replyText = replyTextBinding.wrappedValue
                    if replyText.isEmpty {
                        Text("Reply to Thrawn…")
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.28))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: replyTextBinding)
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.92))
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .focused($isReplyFocused)
                        .frame(minHeight: 38, maxHeight: 100)
                        .fixedSize(horizontal: false, vertical: true)
                        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
                            threadStore.handleFileDrop(providers: providers, threadId: threadId)
                            return true
                        }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(isReplyFocused ? 0.07 : 0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    isReplyFocused
                                        ? Color(red: 0.30, green: 0.50, blue: 1.0).opacity(0.55)
                                        : Color.white.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                )

                if isDropTargeted {
                    Text("Drop to attach")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.55, green: 0.72, blue: 1.0))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(red: 0.28, green: 0.42, blue: 0.88).opacity(0.22)))
                }

                Button(action: sendReply) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(canReply ? .white : Color.white.opacity(0.28))
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(
                                canReply
                                    ? LinearGradient(colors: [Color(red: 0.30, green: 0.48, blue: 1.0), Color(red: 0.18, green: 0.32, blue: 0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom)
                            )
                        )
                        .shadow(color: canReply ? Color(red: 0.28, green: 0.44, blue: 1.0).opacity(0.45) : .clear, radius: 8)
                }
                .buttonStyle(.plain)
                .disabled(!canReply)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.07, green: 0.09, blue: 0.13), Color(red: 0.05, green: 0.07, blue: 0.10)],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
        .background {
            FileDropCatcher(isTargeted: $isDropTargeted) { urls in
                threadStore.handleDroppedURLs(urls, threadId: threadId)
            }
        }
        .onAppear {
            threadStore.markThreadRead(threadId)
            DispatchQueue.main.async { isReplyFocused = true }
        }
        .onChange(of: threadStore.selectedThreadId) { selected in
            guard selected == threadId else { return }
            DispatchQueue.main.async { isReplyFocused = true }
        }
    }

    private var canReply: Bool {
        let text = replyTextBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty || !threadStore.attachments(for: threadId).isEmpty
    }

    private func sendReply() {
        let text = replyTextBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = threadStore.attachments(for: threadId)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        threadStore.sendMessage(in: threadId, text: text, attachments: attachments)
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
        if animated { withAnimation(.easeOut(duration: 0.2)) { action() } } else { action() }
    }

    private var queuedCount: Int { threadStore.queuedCount(for: threadId) }
}

// MARK: - Attachment Strip

private struct ThreadAttachmentStrip: View {
    let attachments: [ChatAttachment]
    let onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { att in
                    HStack(spacing: 6) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 10, weight: .bold))
                        Text(att.fileName)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                        Button { onRemove(att.id) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundColor(Color(red: 0.62, green: 0.76, blue: 1.0))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(red: 0.28, green: 0.42, blue: 0.88).opacity(0.18)))
                }
            }
        }
        .frame(height: 32)
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .assistant {
                assistantBubble
                Spacer(minLength: 32)
            } else {
                Spacer(minLength: 32)
                userBubble
            }
        }
    }

    private var userBubble: some View {
        bubble(text: message.text, isUser: true)
    }

    private var assistantBubble: some View {
        bubble(text: message.text, isUser: false)
    }

    @ViewBuilder
    private func bubble(text: String, isUser: Bool) -> some View {
        let displayText = MSNEmoji.convert(text)
        VStack(alignment: isUser ? .trailing : .leading, spacing: 0) {
            Text(linkified(displayText))
                .font(.system(size: 13))
                .foregroundColor(isUser ? Color.white.opacity(0.95) : Color.white.opacity(0.88))
                .textSelection(.enabled)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            isUser
                                ? LinearGradient(
                                    colors: [
                                        Color(red: 0.28, green: 0.44, blue: 0.96),
                                        Color(red: 0.18, green: 0.30, blue: 0.78),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [
                                        Color(red: 0.14, green: 0.16, blue: 0.22),
                                        Color(red: 0.10, green: 0.12, blue: 0.18),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    isUser
                                        ? Color.white.opacity(0.10)
                                        : Color.white.opacity(0.07),
                                    lineWidth: 1
                                )
                        )
                )
                .overlay(alignment: .topTrailing) {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            copyToClipboard(displayText)
                        } label: {
                            Image(systemName: copied ? "checkmark" : "clipboard")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Color.white.opacity(0.55))
                                .padding(5)
                                .background(Circle().fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .padding(5)
                    }
                }
                .contextMenu {
                    Button("Copy") { copyToClipboard(displayText) }
                }

            if !message.attachments.isEmpty {
                VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                    ForEach(message.attachments) { att in
                        HStack(spacing: 5) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 9))
                            Text(att.fileName)
                                .font(.system(size: 10))
                                .lineLimit(1)
                        }
                        .foregroundColor(Color(red: 0.62, green: 0.76, blue: 1.0))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 4)
            }
        }
    }

    private func linkified(_ text: String) -> AttributedString {
        let mutable = NSMutableAttributedString(string: text)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(location: 0, length: (text as NSString).length)
            detector.enumerateMatches(in: text, options: [], range: range) { result, _, _ in
                guard let result, let url = result.url else { return }
                mutable.addAttribute(.link, value: url, range: result.range)
            }
        }
        return (try? AttributedString(mutable, including: \.foundation)) ?? AttributedString(text)
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
