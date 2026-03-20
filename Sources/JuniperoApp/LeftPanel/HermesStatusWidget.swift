import SwiftUI

struct HermesStatusWidget: View {
    @EnvironmentObject private var bootstrap: HermesBootstrap

    var body: some View {
        ZStack {
            // Dark glass background
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(JuniperoTheme.backgroundSurface.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(JuniperoTheme.copperDark.opacity(0.40), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.30), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 8) {
                // Header
                Text("HERMES AGENT")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundColor(JuniperoTheme.copper)

                // Connection status
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: statusColor.opacity(0.60), radius: 4)

                    Text(statusLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(JuniperoTheme.textPrimary)
                }

                // Model info
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 9))
                        .foregroundColor(JuniperoTheme.textTertiary)

                    Text(bootstrap.providerModel)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(JuniperoTheme.textSecondary)
                        .lineLimit(1)
                }

                // Uptime / session indicator
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9))
                        .foregroundColor(JuniperoTheme.textTertiary)

                    Text(bootstrap.statusText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(JuniperoTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Status Helpers

    private var statusColor: Color {
        if bootstrap.hermesHealthy {
            return JuniperoTheme.statusOnline
        } else if bootstrap.isWorking {
            return JuniperoTheme.statusWarning
        } else {
            return JuniperoTheme.statusError
        }
    }

    private var statusLabel: String {
        if bootstrap.hermesHealthy {
            return "Online"
        } else if bootstrap.isWorking {
            return "Starting..."
        } else {
            return "Offline"
        }
    }
}
