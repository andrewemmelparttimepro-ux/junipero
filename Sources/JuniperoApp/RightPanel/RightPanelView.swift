import SwiftUI
import UniformTypeIdentifiers

struct RightPanelView: View {
    @EnvironmentObject var threadStore: ThreadStore
    @EnvironmentObject var roster: AgentRosterStore
    @State private var isComposerOpen = false

    var body: some View {
        VStack(spacing: 0) {
            ThrawnHeaderBar()

            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        CommandStrip()
                        ConsoleSectionSwitcher()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                    ConsoleSectionBody()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.clear)
                }

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
                            draftText: Binding(get: { threadStore.popupDraftText }, set: { threadStore.updatePopupDraft($0) }),
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
                            Image(systemName: "message.badge.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text(isComposerOpen && threadStore.selectedThreadId == nil ? "Hide Command" : "Command")
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
                                            Color(red: 0.28, green: 0.42, blue: 0.98),
                                            Color(red: 0.17, green: 0.28, blue: 0.72),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(color: Color(red: 0.30, green: 0.45, blue: 1.0).opacity(0.34), radius: 10, x: 0, y: 5)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
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

struct ThrawnHeaderBar: View {
    @EnvironmentObject var threadStore: ThreadStore
    @EnvironmentObject var bootstrap: ThrawnBootstrap
    @EnvironmentObject var updateManager: UpdateManager
    @EnvironmentObject var sparkleUpdater: SparkleUpdaterService

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 9, height: 9)
                        .shadow(color: statusColor.opacity(0.75), radius: 8)
                    Text("THRAWN")
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .tracking(3)
                        .foregroundColor(.white)
                }
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.66, green: 0.78, blue: 0.96))
            }

            Spacer()

            HStack(spacing: 8) {
                thrawnButton(threadStore.allThreadsMode ? "Exit Threads" : "Threads", selected: threadStore.allThreadsMode) {
                    withAnimation(.easeInOut(duration: 0.2)) {
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
                    Color(red: 0.10, green: 0.12, blue: 0.18),
                    Color(red: 0.07, green: 0.09, blue: 0.14),
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
        if threadStore.isSending { return "Command stream active" }
        if bootstrap.openClawHealthy { return "Gateway aligned" }
        switch threadStore.connectivity {
        case .online: return "Gateway aligned"
        case .offline: return "Gateway unavailable"
        case .unknown: return "Gateway status unknown"
        }
    }

    private var statusColor: Color {
        if threadStore.isSending { return Color(red: 0.30, green: 0.55, blue: 1.0) }
        if bootstrap.openClawHealthy { return Color(red: 0.38, green: 0.72, blue: 1.0) }
        switch threadStore.connectivity {
        case .online: return Color(red: 0.38, green: 0.72, blue: 1.0)
        case .offline: return Color(red: 0.95, green: 0.36, blue: 0.34)
        case .unknown: return Color.white.opacity(0.55)
        }
    }

    private func thrawnButton(_ title: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(selected ? 0.98 : 0.84))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(selected ? Color(red: 0.24, green: 0.37, blue: 0.82) : Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }
}

struct CommandStrip: View {
    var body: some View {
        HStack(spacing: 12) {
            CommandCard(title: "Task Flow", detail: "Task board, review, deliverables, approvals")
            CommandCard(title: "Agent Fleet", detail: "Dedicated specialists routed through Thrawn")
            CommandCard(title: "Gateway", detail: "Target architecture: same native route as dashboard")
        }
    }
}

private struct CommandCard: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.92))
            Text(detail)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Color.white.opacity(0.6))
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }
}
