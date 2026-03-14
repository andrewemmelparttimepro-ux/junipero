import SwiftUI
import UniformTypeIdentifiers

struct RightPanelView: View {
    @EnvironmentObject var threadStore: ThreadStore
    @State private var isComposerOpen = false

    var body: some View {
        VStack(spacing: 0) {
            ThrawnHeaderBar()

            ZStack(alignment: .bottomTrailing) {
                // Original flow: thread list fills the panel
                Group {
                    if threadStore.allThreadsMode {
                        ThreadListView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ThreadListView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                // Thread detail slides over when selected
                if let selectedId = threadStore.selectedThreadId {
                    ThreadDetailView(threadId: selectedId)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(2)
                }

                // Floating compose button + popup
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
                            Image(systemName: isComposerOpen && threadStore.selectedThreadId == nil ? "xmark" : "plus.message.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text(isComposerOpen && threadStore.selectedThreadId == nil ? "Close" : "Command")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.28, green: 0.44, blue: 0.98),
                                            Color(red: 0.17, green: 0.28, blue: 0.72),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(color: Color(red: 0.30, green: 0.45, blue: 1.0).opacity(0.38), radius: 12, x: 0, y: 5)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.05, green: 0.07, blue: 0.10).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }

    private func sendFromPopup() {
        let trimmed = threadStore.popupDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = threadStore.popupAttachments
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        threadStore.sendMessage(trimmed, attachments: attachments)
    }
}

// MARK: - Header

struct ThrawnHeaderBar: View {
    @EnvironmentObject var threadStore: ThreadStore
    @EnvironmentObject var bootstrap: ThrawnBootstrap
    @EnvironmentObject var updateManager: UpdateManager
    @EnvironmentObject var sparkleUpdater: SparkleUpdaterService

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.80), radius: 7)
                Text("THRAWN")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .tracking(3)
                    .foregroundColor(.white)
                Text("·")
                    .foregroundColor(Color.white.opacity(0.25))
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.62, green: 0.76, blue: 0.96))
            }

            Spacer()

            HStack(spacing: 6) {
                thrawnButton(threadStore.allThreadsMode ? "Exit Threads" : "Threads", selected: threadStore.allThreadsMode) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        threadStore.allThreadsMode.toggle()
                        threadStore.selectedThreadId = nil
                    }
                }
                thrawnButton("Setup") { bootstrap.showSetup = true }
                thrawnButton("Refresh") { Task { await bootstrap.refreshRuntimeStatus() } }
                thrawnButton("Updates") {
                    sparkleUpdater.checkForUpdates()
                    Task { await updateManager.checkForUpdates() }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.15),
                    Color(red: 0.05, green: 0.07, blue: 0.11),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    private var statusText: String {
        if threadStore.isSending { return "Stream active" }
        if bootstrap.openClawHealthy { return "Gateway aligned" }
        switch threadStore.connectivity {
        case .online: return "Gateway aligned"
        case .offline: return "Gateway unavailable"
        case .unknown: return "Connecting…"
        }
    }

    private var statusColor: Color {
        if threadStore.isSending { return Color(red: 0.30, green: 0.55, blue: 1.0) }
        if bootstrap.openClawHealthy { return Color(red: 0.38, green: 0.72, blue: 1.0) }
        switch threadStore.connectivity {
        case .online: return Color(red: 0.38, green: 0.72, blue: 1.0)
        case .offline: return Color(red: 0.95, green: 0.36, blue: 0.34)
        case .unknown: return Color.white.opacity(0.45)
        }
    }

    private func thrawnButton(_ title: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(selected ? 0.98 : 0.78))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(selected ? Color(red: 0.24, green: 0.37, blue: 0.82) : Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }
}
