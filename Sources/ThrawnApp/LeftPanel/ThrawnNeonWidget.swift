import SwiftUI

struct ThrawnNeonWidget: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.06, green: 0.10, blue: 0.18),
                            Color(red: 0.04, green: 0.06, blue: 0.14),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.35, green: 0.78, blue: 0.98),
                                    Color(red: 0.18, green: 0.55, blue: 0.90),
                                    Color(red: 0.45, green: 0.85, blue: 1.0),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.5
                        )
                )
                .shadow(color: Color.black.opacity(0.28), radius: 12, x: 0, y: 8)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
                .padding(7)

            VStack(spacing: 8) {
                HStack(spacing: 9) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 0.55, green: 0.82, blue: 0.95))
                        .shadow(color: Color(red: 0.55, green: 0.82, blue: 0.95).opacity(0.65), radius: 6)

                    Text("powered by Claude")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.65, green: 0.85, blue: 1.0))
                        .shadow(color: Color(red: 0.45, green: 0.75, blue: 0.95).opacity(0.60), radius: 7)
                }

                Text("THRAWN")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .tracking(3.0)
                    .foregroundStyle(Color(red: 0.40, green: 0.88, blue: 1.0))
                    .shadow(color: Color(red: 0.30, green: 0.80, blue: 1.0).opacity(0.70), radius: 10)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}
