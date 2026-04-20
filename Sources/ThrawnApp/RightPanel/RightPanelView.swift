
import SwiftUI
import UniformTypeIdentifiers

struct RightPanelView: View {
    @EnvironmentObject var nav: ConsoleNavigationStore
    @EnvironmentObject var threadStore: ThreadStore
    @State private var showPopupChat = false

    /// Hide the floating composer when the user is already inside an active
    /// thread or specialist chat — it would just collide with the reply bar.
    private var showFloatingComposer: Bool {
        if showPopupChat { return false }
        if nav.showMemoryGraph { return false }
        if nav.selectedAgentId != nil { return false }
        if nav.selectedSection == .command && threadStore.selectedThreadId != nil { return false }
        return true
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                ThrawnHeaderBar()

                // Console section switcher
                ConsoleSectionSwitcher()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.obsidianMid.opacity(0.85))
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.chissPrimary.opacity(0.10)).frame(height: 1)
                    }

                ConsoleSectionBody()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.18), value: nav.selectedSection)

            // Popup chat overlay
            if showPopupChat {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closePopupChat()
                    }
                    .transition(.opacity)

                PopupComposerCard(
                    draftText: Binding(
                        get: { threadStore.popupDraftText },
                        set: { threadStore.updatePopupDraft($0) }
                    ),
                    onClose: { closePopupChat() },
                    onSend: { sendFromPopup() }
                )
                .padding(.trailing, 20)
                .padding(.bottom, 80)
                .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
            }

            // Floating Command button
            if showFloatingComposer {
                FloatingCommandButton(
                    unreadCount: threadStore.unreadThreadCount,
                    action: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            showPopupChat = true
                        }
                    }
                )
                .padding(.trailing, 20)
                .padding(.bottom, 20)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: showPopupChat)
        .animation(.easeInOut(duration: 0.18), value: showFloatingComposer)
    }

    private func closePopupChat() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            showPopupChat = false
        }
    }

    private func sendFromPopup() {
        let text = threadStore.popupDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = threadStore.popupAttachments
        guard !text.isEmpty || !attachments.isEmpty else { return }
        threadStore.sendMessage(text, attachments: attachments)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            showPopupChat = false
        }
        // Switch to Command tab to show the new thread
        nav.selectedSection = .command
    }
}

// MARK: - Floating Command Button

struct FloatingCommandButton: View {
    let unreadCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 7) {
                    Image(systemName: "command")
                        .font(.system(size: 14, weight: .bold))
                    Text("Command")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.chissDeep, Color(red: 0.12, green: 0.22, blue: 0.32)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.chissPrimary.opacity(0.45), lineWidth: 1)
                        )
                )
                .shadow(color: Color.chissPrimary.opacity(0.35), radius: 12, x: 0, y: 4)

                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.chissPrimary)
                        )
                        .offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct ThrawnHeaderBar: View {
    @EnvironmentObject var ollama: OllamaClient
    @EnvironmentObject var bootstrap: ThrawnBootstrap
    @EnvironmentObject var updateManager: UpdateManager
    @EnvironmentObject var sparkleUpdater: SparkleUpdaterService
    @EnvironmentObject var flowTab: FlowTabStore
    @EnvironmentObject var screenCapture: ScreenCaptureStore
    @EnvironmentObject var nav: ConsoleNavigationStore

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

            // Runtime badge — adjacent to identity, not pushed right
            HStack(spacing: 6) {
                Text(bootstrap.statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.chissPrimary.opacity(0.70))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Circle()
                    .fill(runtimeDotColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: runtimeDotColor.opacity(0.80), radius: 4)
            }

            Spacer()

            // Memory brain — tap to open 3D memory graph
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    nav.showMemoryGraph.toggle()
                }
            } label: {
                CogneeMemoryBrain(
                    healthy: bootstrap.cogneeHealthy,
                    syncing: bootstrap.cogneePendingFiles > 0 || bootstrap.cogneeStatusText.localizedCaseInsensitiveContains("sync")
                )
            }
            .buttonStyle(.plain)
            .help("Memory Graph — visualize agent activity and knowledge")

            // Action buttons — icon-only, tooltips on hover
            HStack(spacing: 4) {
                // Vision: camera shutter — shows file size badge when screenshot is pending
                Button { screenCapture.captureFullScreen() } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: screenCapture.pendingScreenshot != nil ? "camera.fill" : "camera")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(
                                screenCapture.pendingScreenshot != nil
                                    ? Color(red: 0.55, green: 0.82, blue: 0.95)
                                    : Color.chissPrimary.opacity(0.80)
                            )
                        if screenCapture.isCapturing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.38)
                                .tint(Color.chissPrimary)
                                .frame(width: 8, height: 8)
                                .offset(x: 6, y: -6)
                        } else if screenCapture.pendingScreenshot != nil {
                            // Small dot badge to indicate pending
                            Circle()
                                .fill(Color(red: 0.55, green: 0.82, blue: 0.95))
                                .frame(width: 6, height: 6)
                                .offset(x: 4, y: -4)
                        }
                    }
                    .frame(width: 30, height: 28)
                    .background(
                        Circle()
                            .fill(screenCapture.pendingScreenshot != nil
                                  ? Color(red: 0.55, green: 0.82, blue: 0.95).opacity(0.12)
                                  : Color.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .help("Vision — capture full screen and attach to next message")

                iconBtn("square.grid.2x2.fill", help: "Flow board") {
                    withAnimation(.easeInOut(duration: 0.22)) { flowTab.showFlow.toggle() }
                }
                iconBtn("gearshape", help: "Setup") { bootstrap.showSetup = true }
                iconBtn("waveform.path.ecg", help: "Heal — refresh runtime status") {
                    Task { await bootstrap.refreshRuntimeStatus() }
                }

                Menu {
                    Button("Run Diagnostics") { Task { await bootstrap.runFullHealthTest() } }
                    Button("Reindex Memory") { Task { await bootstrap.reindexCogneeMemory() } }
                    Button("Export Support Bundle") { Task { await bootstrap.exportSupportBundle() } }
                    Button("Check Updates") { Task { await updateManager.checkForUpdates() } }
                    Divider()
                    Button("Guardrails: Standard") { bootstrap.setLiabilityMode(.idiot) }
                    Button("Guardrails: Disabled") { bootstrap.setLiabilityMode(.myFault) }
                        .disabled(!bootstrap.canDisableGuardrails)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.chissPrimary.opacity(0.75))
                        .frame(width: 30, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.06)))
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
        if ollama.connected { return "Online · Ollama" }
        if ollama.authenticating { return "Connecting" }
        if let err = ollama.lastError { return err.count > 30 ? "Connection error" : err }
        return "Ollama offline"
    }

    private var statusColor: Color {
        if ollama.authenticating { return Color(red: 0.95, green: 0.70, blue: 0.20) }
        if ollama.connected { return Color(red: 0.30, green: 0.85, blue: 0.40) }
        return Color(red: 0.85, green: 0.25, blue: 0.20)
    }

    private var runtimeDotColor: Color {
        let isConnected = ollama.connected || bootstrap.apiHealthy
        return isConnected ? Color(red: 0.30, green: 0.85, blue: 0.40) : Color(red: 0.85, green: 0.25, blue: 0.20)
    }

    private func iconBtn(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.chissPrimary.opacity(0.80))
                .frame(width: 30, height: 28)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Cognee Memory Brain Indicator
// Replaces the old "Memory 2/2" text badge with a brain icon.
// Lit chiss-blue when healthy, blinks while syncing, dims when dead.

struct CogneeMemoryBrain: View {
    let healthy: Bool
    let syncing: Bool

    @State private var blinkOpacity: Double = 1.0

    /// Only blink when NOT healthy and still connecting/syncing.
    /// Healthy = solid lit blue. Dead = dim outline.
    private var shouldBlink: Bool { !healthy && syncing }

    private var brainColor: Color {
        if healthy { return Color.chissPrimary }
        if syncing { return Color.chissPrimary }
        return Color.chissPrimary.opacity(0.20)
    }

    var body: some View {
        Image(systemName: healthy ? "brain.fill" : "brain")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(brainColor)
            .opacity(shouldBlink ? blinkOpacity : 1.0)
            .shadow(color: healthy ? Color.chissPrimary.opacity(0.50) : .clear, radius: 6)
            .onAppear { startBlinkIfNeeded() }
            .onChange(of: shouldBlink) { _ in startBlinkIfNeeded() }
    }

    private func startBlinkIfNeeded() {
        if shouldBlink {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                blinkOpacity = 0.25
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                blinkOpacity = 1.0
            }
        }
    }
}

private struct AttachmentStrip: View {
    let attachments: [ChatAttachment]
    let onRemove: (UUID) -> Void

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic"]

    private func isImage(_ fileName: String) -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return Self.imageExtensions.contains(ext)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentChip(attachment: attachment, isImage: isImage(attachment.fileName), onRemove: onRemove)
                }
            }
        }
        .frame(minHeight: 30)
    }
}

private struct AttachmentChip: View {
    let attachment: ChatAttachment
    let isImage: Bool
    let onRemove: (UUID) -> Void
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            if isImage, let img = thumbnail {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.chissPrimary.opacity(0.30), lineWidth: 1)
                    )
            }
            HStack(spacing: 4) {
                Image(systemName: isImage ? "photo" : "paperclip")
                    .font(.system(size: 9, weight: .bold))
                Text(attachment.fileName)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 80)
                Button { onRemove(attachment.id) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundColor(Color.chissPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.chissPrimary.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.chissPrimary.opacity(0.25), lineWidth: 1)
                )
        )
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        guard isImage, thumbnail == nil else { return }
        let path = attachment.filePath
        Task.detached(priority: .utility) {
            guard let img = NSImage(contentsOfFile: path) else { return }
            // Downscale for thumbnail
            let maxDim: CGFloat = 128
            let ratio = min(maxDim / img.size.width, maxDim / img.size.height, 1.0)
            let newSize = NSSize(width: img.size.width * ratio, height: img.size.height * ratio)
            let thumb = NSImage(size: newSize)
            thumb.lockFocus()
            img.draw(in: NSRect(origin: .zero, size: newSize))
            thumb.unlockFocus()
            Task { @MainActor in thumbnail = thumb }
        }
    }
}
