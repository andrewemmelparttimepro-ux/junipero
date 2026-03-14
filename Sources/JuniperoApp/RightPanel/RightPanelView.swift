
import SwiftUI
import UniformTypeIdentifiers

struct RightPanelView: View {
    @EnvironmentObject var nav: ConsoleNavigationStore

    var body: some View {
        VStack(spacing: 0) {
            ThrawnHeaderBar()

            // Console section switcher
            ConsoleSectionSwitcher()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.obsidianMid.opacity(0.85))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.chissPrimary.opacity(0.10)).frame(height: 1)
                }

            ConsoleSectionBody()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.18), value: nav.selectedSection)
    }
}

struct ThrawnHeaderBar: View {
    @EnvironmentObject var gatewayWS: GatewayWSClient
    @EnvironmentObject var bootstrap: ThrawnBootstrap
    @EnvironmentObject var updateManager: UpdateManager
    @EnvironmentObject var sparkleUpdater: SparkleUpdaterService
    @EnvironmentObject var flowTab: FlowTabStore

    var body: some View {
        HStack(spacing: 12) {
            // Avatar + identity
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.chissDeep)
                        .frame(width: 34, height: 34)
                        .shadow(color: Color.chissPrimary.opacity(0.35), radius: 8)
                    Text("T")
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundColor(Color.chissPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("THRAWN")
                        .font(.system(size: 12, weight: .bold, design: .serif))
                        .tracking(2.5)
                        .foregroundColor(Color.chissPrimary)
                        .shadow(color: Color.chissPrimary.opacity(0.40), radius: 6)
                    HStack(spacing: 5) {
                        Circle().fill(statusColor).frame(width: 6, height: 6)
                            .shadow(color: statusColor.opacity(0.80), radius: 4)
                        Text(statusLabel)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.60))
                    }
                }
            }

            Spacer()

            // Runtime badge
            HStack(spacing: 6) {
                Text(bootstrap.statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.chissPrimary.opacity(0.70))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 180, alignment: .leading)
                Circle()
                    .fill(runtimeDotColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: runtimeDotColor.opacity(0.80), radius: 4)
            }

            // Action buttons
            HStack(spacing: 6) {
                headerBtn("Flow", icon: "square.grid.2x2.fill") {
                    withAnimation(.easeInOut(duration: 0.22)) { flowTab.showFlow.toggle() }
                }
                headerBtn("Setup", icon: "gearshape") { bootstrap.showSetup = true }
                headerBtn("Heal", icon: "waveform.path.ecg") { Task { await bootstrap.refreshRuntimeStatus() } }
                Menu {
                    Button("Run Diagnostics") { Task { await bootstrap.runFullHealthTest() } }
                    Button("Export Support Bundle") { Task { await bootstrap.exportSupportBundle() } }
                    Button("Check Updates") {
                        sparkleUpdater.checkForUpdates()
                        Task { await updateManager.checkForUpdates() }
                    }
                    Divider()
                    Button("Guardrails: Standard") { bootstrap.setLiabilityMode(.idiot) }
                    Button("Guardrails: Disabled") { bootstrap.setLiabilityMode(.myFault) }
                        .disabled(!bootstrap.canDisableGuardrails)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.chissPrimary.opacity(0.75))
                        .frame(width: 30, height: 28)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(
            ZStack {
                Color.obsidianMid
                LinearGradient(
                    colors: [Color.chissDeep.opacity(0.45), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.chissPrimary.opacity(0.18)).frame(height: 1)
        }
    }

    private var statusLabel: String {
        if gatewayWS.authenticating { return "Connecting" }
        if gatewayWS.connected { return "Online" }
        if let err = gatewayWS.lastError { return err.count > 30 ? "Connection error" : err }
        return bootstrap.openClawHealthy ? "Online" : "Offline"
    }

    private var statusColor: Color {
        if gatewayWS.authenticating { return Color(red: 0.95, green: 0.70, blue: 0.20) }
        if gatewayWS.connected { return Color(red: 0.30, green: 0.85, blue: 0.40) }
        return Color(red: 0.85, green: 0.25, blue: 0.20)
    }

    private var runtimeDotColor: Color {
        bootstrap.openClawHealthy ? Color(red: 0.30, green: 0.85, blue: 0.40) : Color(red: 0.85, green: 0.25, blue: 0.20)
    }

    private func headerBtn(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                Text(label).font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundColor(Color.chissPrimary.opacity(0.80))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.06)).overlay(Capsule().stroke(Color.chissPrimary.opacity(0.18), lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }
}

// PopupComposerCard kept for legacy use — may be referenced by other views
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
                .fill(Color.obsidianMid)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.chissPrimary.opacity(0.28), lineWidth: 1)
                )
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
                    .foregroundColor(Color.chissPrimary)
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
