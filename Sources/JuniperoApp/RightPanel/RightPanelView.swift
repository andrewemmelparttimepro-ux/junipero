import SwiftUI

enum PanelMode: String {
    case chat
    case flow
}

struct RightPanelView: View {
    @EnvironmentObject var bootstrap: HermesBootstrap
    @EnvironmentObject var threadStore: ThreadStore
    @State private var mode: PanelMode = .chat

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: mode switch + status
            topBar

            Rectangle()
                .fill(JuniperoTheme.divider)
                .frame(height: 1)

            // Content
            Group {
                switch mode {
                case .chat:
                    CommandView()
                case .flow:
                    FlowView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(JuniperoTheme.backgroundPrimary)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 0) {
            // Mode toggle — the switch
            modeSwitch

            Spacer()

            // Minimal status
            HStack(spacing: 8) {
                Circle()
                    .fill(healthDotColor)
                    .frame(width: 6, height: 6)

                Text(bootstrap.statusText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(JuniperoTheme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(JuniperoTheme.backgroundSecondary.opacity(0.6))
    }

    // MARK: - Mode Switch

    private var modeSwitch: some View {
        HStack(spacing: 0) {
            switchLabel("Chat", isActive: mode == .chat) {
                withAnimation(.easeInOut(duration: 0.2)) { mode = .chat }
            }
            switchLabel("Flow", isActive: mode == .flow) {
                withAnimation(.easeInOut(duration: 0.2)) { mode = .flow }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(JuniperoTheme.backgroundPrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(JuniperoTheme.divider, lineWidth: 1)
        )
    }

    private func switchLabel(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular, design: .monospaced))
                .foregroundColor(isActive ? JuniperoTheme.textPrimary : JuniperoTheme.textTertiary)
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .background(
                    isActive
                        ? RoundedRectangle(cornerRadius: 7).fill(JuniperoTheme.backgroundElevated)
                        : nil
                )
        }
        .buttonStyle(.plain)
    }

    private var healthDotColor: Color {
        if threadStore.isSending { return JuniperoTheme.statusThinking }
        if bootstrap.hermesHealthy { return JuniperoTheme.statusOnline }
        if bootstrap.isWorking { return JuniperoTheme.statusWarning }
        return JuniperoTheme.statusError
    }
}
