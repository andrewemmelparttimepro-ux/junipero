
enum RightPanelTab: String, CaseIterable {
    case threads = "Threads"
    case flow = "Flow"
}

import SwiftUI
import UniformTypeIdentifiers

struct RightPanelView: View {
    @EnvironmentObject var threadStore: ThreadStore
    @State private var isComposerOpen = false
    @State private var activeTab: RightPanelTab = .threads

    var body: some View {
        VStack(spacing: 0) {
            ThrawnHeaderBar(activeTab: $activeTab)

            switch activeTab {
            case .threads:
                ZStack(alignment: .bottomTrailing) {
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
                                onSend: { sendFromPopup() }
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
                                Text(isComposerOpen && threadStore.selectedThreadId == nil ? "Hide" : "Command")
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

            case .flow:
                FlowBoardView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func sendFromPopup() {
        let trimmed = threadStore.popupDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = threadStore.popupAttachments
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        threadStore.sendMessage(trimmed, attachments: attachments)
    }
}

struct ThrawnHeaderBar: View {
    @EnvironmentObject var threadStore: ThreadStore
    @EnvironmentObject var bootstrap: ThrawnBootstrap
    @EnvironmentObject var updateManager: UpdateManager
    @EnvironmentObject var sparkleUpdater: SparkleUpdaterService
    @Binding var activeTab: RightPanelTab

    var body: some View {
        HStack {
            // Thrawn avatar and status
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Text("T")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Thrawn")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(statusText)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: 128, alignment: .leading)

            Spacer()

            ViewThatFits(in: .horizontal) {
                fullHeaderControls
                compactHeaderControls
            }
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
        if bootstrap.openClawHealthy {
            if isAuthIssue {
                return "Auth Needed"
            }
            return "Online"
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
        if bootstrap.openClawHealthy {
            if isAuthIssue {
                return Color(red: 0.95, green: 0.70, blue: 0.20)
            }
            return Color(red: 0.30, green: 0.85, blue: 0.30)
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

    private var isAuthIssue: Bool {
        guard let error = threadStore.lastErrorText?.lowercased() else { return false }
        return error.contains("auth")
            || error.contains("token")
            || error.contains("unauthorized")
            || error.contains("authentication")
    }

    private var runtimeDotColor: Color {
        if bootstrap.openClawHealthy && (!bootstrap.enableOllamaFallback || bootstrap.ollamaHealthy) {
            return Color(red: 0.30, green: 0.85, blue: 0.30)
        }
        if bootstrap.openClawHealthy {
            return Color(red: 0.95, green: 0.70, blue: 0.20)
        }
        return Color(red: 0.85, green: 0.25, blue: 0.20)
    }

    private var fullHeaderControls: some View {
        HStack(spacing: 8) {
            runtimeBadge(maxWidth: 140)
            ForEach(RightPanelTab.allCases, id: \.self) { tab in
                actionButton(tab.rawValue, selected: activeTab == tab) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        activeTab = tab
                        if tab == .threads {
                            threadStore.allThreadsMode = false
                        }
                    }
                }
            }
            actionButton("Setup") {
                bootstrap.showSetup = true
            }
            actionButton("Heal") {
                Task { await bootstrap.refreshRuntimeStatus() }
            }
            actionButton("Support") {
                Task { await bootstrap.exportSupportBundle() }
            }
            actionButton("Test") {
                Task { await bootstrap.runFullHealthTest() }
            }
            actionButton("Updates") {
                sparkleUpdater.checkForUpdates()
                Task { await updateManager.checkForUpdates() }
            }
            capabilityMenu
            if threadStore.unreadThreadCount > 0 {
                Text(threadStore.unreadThreadCount > 1 ? "\(threadStore.unreadThreadCount) NEW" : "NEW")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(Color(red: 0.08, green: 0.28, blue: 0.06))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.56, green: 0.98, blue: 0.46))
                    )
            }
            Text("\(threadStore.threads.count) conv")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
        }
    }

    private var compactHeaderControls: some View {
        HStack(spacing: 8) {
            runtimeBadge(maxWidth: 110)
            ForEach(RightPanelTab.allCases, id: \.self) { tab in
                actionButton(tab.rawValue, selected: activeTab == tab) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        activeTab = tab
                    }
                }
            }
            Menu {
                Button("Setup") { bootstrap.showSetup = true }
                Button("Heal") { Task { await bootstrap.refreshRuntimeStatus() } }
                Button("Support") { Task { await bootstrap.exportSupportBundle() } }
                Button("Full Test") { Task { await bootstrap.runFullHealthTest() } }
                Button("Check Updates") {
                    sparkleUpdater.checkForUpdates()
                    Task { await updateManager.checkForUpdates() }
                }
                Divider()
                Button("I'm an idiot") { bootstrap.setLiabilityMode(.idiot) }
                Button("It's my fault") { bootstrap.setLiabilityMode(.myFault) }
                    .disabled(!bootstrap.canDisableGuardrails)
            } label: {
                HStack(spacing: 4) {
                    Text("Tools")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                )
            }
            .buttonStyle(.plain)
            if threadStore.unreadThreadCount > 0 {
                Text(threadStore.unreadThreadCount > 1 ? "\(threadStore.unreadThreadCount)" : "NEW")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(Color(red: 0.08, green: 0.28, blue: 0.06))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.56, green: 0.98, blue: 0.46))
                    )
            }
        }
    }

    private var capabilityMenu: some View {
        Menu {
            Button("I'm an idiot") { bootstrap.setLiabilityMode(.idiot) }
            Button("It's my fault") { bootstrap.setLiabilityMode(.myFault) }
                .disabled(!bootstrap.canDisableGuardrails)
        } label: {
            Text(bootstrap.liabilityMode == .myFault ? "My Fault" : "Idiot")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(
                            bootstrap.liabilityMode == .myFault
                                ? Color(red: 0.60, green: 0.24, blue: 0.22).opacity(0.6)
                                : Color.white.opacity(0.14)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func runtimeBadge(maxWidth: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(bootstrap.statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
            Circle()
                .fill(runtimeDotColor)
                .frame(width: 7, height: 7)
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
    }

    private func actionButton(_ title: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(selected ? 0.28 : 0.14))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct PopupComposerCard: View {
    @EnvironmentObject var threadStore: ThreadStore
    @Binding var draftText: String
    @FocusState private var isInputFocused: Bool
    @State private var isDropTargeted = false
    let onClose: () -> Void
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Message Thrawn")
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
                .focused($isInputFocused)
                .onSubmit {
                    onSend()
                }
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
                    threadStore.handleFileDrop(providers: providers, threadId: nil)
                    return true
                }

            if isDropTargeted {
                Text("Drop files to attach")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 0.14, green: 0.30, blue: 0.56))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.92))
                    )
            }

            if !threadStore.popupAttachments.isEmpty {
                AttachmentStrip(
                    attachments: threadStore.popupAttachments,
                    onRemove: { id in
                        threadStore.removeAttachment(threadId: nil, attachmentId: id)
                    }
                )
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
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && threadStore.popupAttachments.isEmpty)
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
        .background {
            FileDropCatcher(isTargeted: $isDropTargeted) { urls in
                threadStore.handleDroppedURLs(urls, threadId: nil)
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
    }
}

private struct AttachmentStrip: View {
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
