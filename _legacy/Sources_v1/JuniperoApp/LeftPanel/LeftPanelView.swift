import SwiftUI

struct LeftPanelView: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            HStack {
                OpenClawNeonWidget()
                    .frame(width: 235, height: 130)
                    .rotationEffect(.degrees(-6))
                Spacer()
            }
            .padding(.leading, 4)

            Spacer()
                .frame(height: 6)

            // Hero: Analog Clock (Size 3 — Large)
            AnalogClockView()
                .frame(width: 320, height: 320)

            Spacer()
                .frame(height: 22)

            // Bitcoin Widget (Size 1 — Small)
            BitcoinWidget()
                .frame(width: 220, height: 120)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }
}
