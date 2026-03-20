import SwiftUI

struct LeftPanelView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Top-left: "powered by HERMES" badge
            HStack {
                HermesBadge()
                    .frame(width: 220, height: 110)
                    .rotationEffect(.degrees(-4))
                Spacer()
            }
            .padding(.leading, 8)
            .padding(.top, 12)

            Spacer()

            // HERO: Analog Clock — the centerpiece
            AnalogClockView()
                .frame(width: 360, height: 360)

            Spacer()
                .frame(height: 24)

            // Hermes status card
            HermesStatusWidget()
                .frame(width: 240, height: 100)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JuniperoTheme.backgroundPrimary)
        .padding(.horizontal, 24)
    }
}
