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
            HStack {
                Text("Thread")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                Spacer()
                if queuedCount > 0 {
                    HStack(spacing: 6) {
                        Text("\(queuedCount) queued")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(red: 0.12, green: 0.22, blue: 0.42))
                        Button("Clear") {
                            threadStore.clearQueuedMessages(for: threadId)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(red: 0.17, green: 0.30, blue: 0.55))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.84))
                    )
                }
                if let thread {
                    Text(thread.formattedDate)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.76))
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        threadStore.selectedThreadId = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.18, green: 0.36, blue: 0.68),
                        Color(red: 0.10, green: 0.25, blue: 0.50),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

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
                                    ProgressView()
                                        .scaleEffect(0.6)
                                    Text("O'Brien is thinking...")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color.black.opacity(0.72))
                                    Spacer()
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.9))
                                )
                                .id("loading-\(thread.id.uuidString)")
                            } else if thread.state == .failed {
                                HStack {
                                    Text(thread.errorMessage ?? "Request failed.")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(red: 0.75, green: 0.20, blue: 0.20))
                                    Spacer()
                                    Button("Retry") {
                                        threadStore.retryThread(thread.id)
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color(red: 0.20, green: 0.40, blue: 0.70))
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(red: 0.98, green: 0.93, blue: 0.93))
                                )
                                .id("failed-\(thread.id.uuidString)")
                            }
                        }
                        Color.clear.frame(height: 1).id(bottomAnchorId)
                    }
                    .padding(12)
                    .onAppear {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                    .onChange(of: thread?.messages.count ?? 0) { _ in
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                    .onChange(of: thread?.isLoading ?? false) { _ in
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
            }
            .background(Color(red: 0.95, green: 0.95, blue: 0.96))

            HStack(spacing: 10) {
                TextField("Reply to this thread...", text: replyTextBinding, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(Color.black.opacity(0.95))
                    .lineLimit(1...5)
                    .focused($isReplyFocused)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.98))
                    )
                    .onSubmit {
                        sendReply()
                    }
                    .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
                        threadStore.handleFileDrop(providers: providers, threadId: threadId)
                        return true
                    }

                if isDropTargeted {
                    Text("Drop files to attach")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.12, green: 0.28, blue: 0.52))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.95))
                        )
                }

                if !threadStore.attachments(for: threadId).isEmpty {
                    ThreadAttachmentStrip(
                        attachments: threadStore.attachments(for: threadId),
                        onRemove: { id in
                            threadStore.removeAttachment(threadId: threadId, attachmentId: id)
                        }
                    )
                }

                Button(action: sendReply) {
                    Text("Send")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.22, green: 0.48, blue: 0.80))
                        )
                }
                .buttonStyle(.plain)
                .disabled(replyTextBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && threadStore.attachments(for: threadId).isEmpty)
            }
            .padding(12)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.18, green: 0.36, blue: 0.68),
                        Color(red: 0.12, green: 0.28, blue: 0.58),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 8)
        .background {
            FileDropCatcher(isTargeted: $isDropTargeted) { urls in
                threadStore.handleDroppedURLs(urls, threadId: threadId)
            }
        }
        .onAppear {
            threadStore.markThreadRead(threadId)
            DispatchQueue.main.async {
                isReplyFocused = true
            }
        }
        .onChange(of: threadStore.selectedThreadId) { selected in
            guard selected == threadId else { return }
            DispatchQueue.main.async {
                isReplyFocused = true
            }
        }
    }

    private func sendReply() {
        let text = replyTextBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = threadStore.attachments(for: threadId)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        threadStore.sendMessage(in: threadId, text: text, attachments: attachments)
        DispatchQueue.main.async {
            isReplyFocused = true
        }
    }

    private var replyTextBinding: Binding<String> {
        Binding(
            get: { threadStore.draftText(for: threadId) },
            set: { threadStore.updateThreadDraft(threadId: threadId, text: $0) }
        )
    }

    private var bottomAnchorId: String {
        "thread-bottom-\(threadId.uuidString)"
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(bottomAnchorId, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                action()
            }
        } else {
            action()
        }
    }

    private var queuedCount: Int {
        threadStore.queuedCount(for: threadId)
    }
}

private struct ThreadAttachmentStrip: View {
    let attachments: [ChatAttachment]
    let onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 6) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 10, weight: .bold))
                        Text(attachment.fileName)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                        Button {
                            onRemove(attachment.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundColor(Color(red: 0.12, green: 0.28, blue: 0.52))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.94))
                    )
                }
            }
        }
        .frame(height: 30)
    }
}

private struct MessageBubble: View {
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
        let displayText = MSNEmoji.convert(text)
        Text(linkified(displayText))
            .font(.system(size: 13))
            .foregroundColor(Color.black.opacity(0.93))
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .padding(.top, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isUser
                            ? Color(red: 0.84, green: 0.91, blue: 1.0)
                            : Color.white.opacity(0.95)
                    )
            )
            .overlay(alignment: .topTrailing) {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        copyToClipboard(displayText)
                    } label: {
                        Image(systemName: copied ? "checkmark" : "clipboard")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.black.opacity(0.75))
                            .padding(5)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.92))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
            }
            .contextMenu {
                Button("Copy") {
                    copyToClipboard(displayText)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !message.attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(message.attachments) { attachment in
                            Text("📎 \(attachment.fileName)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color.black.opacity(0.65))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .offset(y: 14)
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
        if let attributed = try? AttributedString(mutable, including: \.foundation) {
            return attributed
        }
        return AttributedString(text)
    }

    private func copyToClipboard(_ text: String) {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#endif
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                copied = false
            }
        }
    }
}
