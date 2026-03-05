import SwiftUI

struct LeftPanelView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Hero: Analog Clock (Size 3 — Large)
            AnalogClockView()
                .frame(width: 320, height: 320)

            Spacer()
                .frame(height: 16)

            // Bitcoin Widget (Size 1 — Small)
            BitcoinWidget()
                .frame(width: 220, height: 120)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }
}
