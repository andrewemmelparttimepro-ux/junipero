import SwiftUI

struct ReviewView: View {
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
            Text("Review")
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

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(JuniperoTheme.textTertiary.opacity(0.5))

            VStack(spacing: 8) {
                Text("No items pending review")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(JuniperoTheme.textPrimary)

                Text("Code and content reviews requested through Hermes will appear here.")
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
