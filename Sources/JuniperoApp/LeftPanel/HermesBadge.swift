import SwiftUI

struct HermesBadge: View {
    var body: some View {
        ZStack {
            // Dark background
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    JuniperoTheme.copper,
                                    JuniperoTheme.roseGold,
                                    JuniperoTheme.copperDark,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: .black.opacity(0.30), radius: 10, x: 0, y: 6)

            // Subtle inner border
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.6)
                .padding(6)

            VStack(spacing: 6) {
                // "powered by" row with bolt
                HStack(spacing: 7) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(JuniperoTheme.copper)
                        .shadow(color: JuniperoTheme.copper.opacity(0.60), radius: 5)

                    Text("powered by")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(JuniperoTheme.copper)
                        .shadow(color: JuniperoTheme.copper.opacity(0.50), radius: 6)
                }

                // "HERMES" — hero text
                Text("HERMES")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(JuniperoTheme.copperLight)
                    .shadow(color: JuniperoTheme.copper.opacity(0.65), radius: 10)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}
