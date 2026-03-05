import SwiftUI

struct OpenClawNeonWidget: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.12, blue: 0.20),
                            Color(red: 0.06, green: 0.08, blue: 0.16),
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
                                    Color(red: 0.96, green: 0.62, blue: 0.22),
                                    Color(red: 0.35, green: 0.78, blue: 0.98),
                                    Color(red: 0.92, green: 0.36, blue: 0.40),
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
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 0.98, green: 0.68, blue: 0.24))
                        .shadow(color: Color(red: 0.98, green: 0.68, blue: 0.24).opacity(0.65), radius: 6)

                    Text("powered by")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.32))
                        .shadow(color: Color(red: 1.0, green: 0.65, blue: 0.26).opacity(0.60), radius: 7)
                }

                Text("OPEN CLAW")
                    .font(.system(size: 35, weight: .black, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(Color(red: 0.40, green: 0.96, blue: 0.98))
                    .shadow(color: Color(red: 0.30, green: 0.90, blue: 1.0).opacity(0.70), radius: 10)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}
