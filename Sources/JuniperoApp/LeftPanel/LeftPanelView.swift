import SwiftUI

struct LeftPanelView: View {
    @EnvironmentObject var bootstrap: HermesBootstrap

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // HERO: Analog Clock — the centerpiece
            AnalogClockView()
                .frame(width: 340, height: 340)

            Spacer()
                .frame(height: 28)

            // Minimal status — just the dot and a word
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: statusColor.opacity(0.6), radius: 4)

                Text(statusLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(JuniperoTheme.textSecondary)
                    .tracking(2)
                    .textCase(.uppercase)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JuniperoTheme.backgroundPrimary)
    }

    private var statusColor: Color {
        if bootstrap.hermesHealthy { return JuniperoTheme.statusOnline }
        if bootstrap.isWorking { return JuniperoTheme.statusWarning }
        return JuniperoTheme.statusError
    }

    private var statusLabel: String {
        if bootstrap.hermesHealthy { return "Online" }
        if bootstrap.isWorking { return "Starting" }
        return "Offline"
    }
}
