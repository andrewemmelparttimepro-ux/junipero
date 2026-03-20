import SwiftUI

struct CommandView: View {
    @EnvironmentObject var threadStore: ThreadStore
    @EnvironmentObject var bootstrap: HermesBootstrap

    private var activeThread: ChatThread? {
        guard let id = threadStore.selectedThreadId else { return nil }
        return threadStore.threads.first(where: { $0.id == id })
    }

    var body: some View {
        VStack(spacing: 0) {
            if let thread = activeThread {
                messageList(for: thread)
            } else if let latest = threadStore.threads.first {
                messageList(for: latest)
            } else {
                welcomeView
            }

            ChatInputView()
        }
        .background(JuniperoTheme.backgroundPrimary)
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [JuniperoTheme.copper.opacity(0.3), JuniperoTheme.copperDark.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .overlay(
                        Image(systemName: "terminal")
                            .font(.system(size: 28, weight: .light))
                            .foregroundColor(JuniperoTheme.copper)
                    )

                Text("What can I help you with?")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(JuniperoTheme.textPrimary)

                Text("Start a conversation with Hermes to get things done.")
                    .font(.system(size: 14))
                    .foregroundColor(JuniperoTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Message List

    private func messageList(for thread: ChatThread) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(thread.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if thread.isLoading {
                        HStack(spacing: 10) {
                            ProgressView().scaleEffect(0.6)
                            Text("Hermes is thinking...")
                                .font(.system(size: 13))
                                .foregroundColor(JuniperoTheme.textSecondary)
                                .italic()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(JuniperoTheme.assistantBubble)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if thread.state == .failed {
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

                    Color.clear.frame(height: 1).id("command-bottom")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onChange(of: thread.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("command-bottom", anchor: .bottom)
                }
            }
        }
    }
}
