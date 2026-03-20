import SwiftUI

struct DeliverablesView: View {
    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(JuniperoTheme.divider)
                .frame(height: 1)

            emptyState
        }
        .background(JuniperoTheme.backgroundPrimary)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Deliverables")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(JuniperoTheme.textPrimary)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "tray.full")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(JuniperoTheme.textTertiary.opacity(0.5))

            VStack(spacing: 8) {
                Text("No deliverables yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(JuniperoTheme.textPrimary)

                Text("Files, reports, and artifacts produced by Hermes will be collected here.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(JuniperoTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
