import SwiftUI

struct LeftPanelView: View {
    var body: some View {
        GeometryReader { geometry in
            let clockSize = min(352.0, max(332.0, min(geometry.size.width * 0.60, geometry.size.height * 0.42)))
            let bitcoinWidth = min(176.0, max(164.0, geometry.size.width * 0.28))
            let bitcoinHeight = 96.0
            let clusterHeight = clockSize + 34 + bitcoinHeight
            let remainingHeight = max(0, geometry.size.height - clusterHeight)
            let topOffset = max(40.0, remainingHeight * 0.52)

            ZStack(alignment: .topLeading) {
                LeftPanelAmbientBackdrop(clockSize: clockSize)

                HStack(alignment: .top, spacing: 24) {
                    AgentRailView()
                        .frame(width: 116)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                        .padding(.top, 40)
                        .padding(.bottom, 28)

                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: topOffset)

                        AnalogClockView()
                            .frame(width: clockSize, height: clockSize)

                        Spacer()
                            .frame(height: 34)

                        BitcoinWidget(style: .compact)
                            .frame(width: bitcoinWidth, height: bitcoinHeight)

                        Spacer(minLength: 28)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.trailing, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 32)
                .padding(.trailing, 32)
            }
        }
    }
}

private struct LeftPanelAmbientBackdrop: View {
    let clockSize: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: 128, height: 720)
                .offset(x: 8, y: 24)
                .blur(radius: 1)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.57, green: 0.76, blue: 0.98).opacity(0.22),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: clockSize * 0.72
                    )
                )
                .frame(width: clockSize * 1.28, height: clockSize * 1.28)
                .offset(x: 160, y: 120)
                .blur(radius: 8)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: 260, y: 40)
                .blur(radius: 18)

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 236, height: 132)
                .offset(x: 248, y: 520)
                .blur(radius: 14)
        }
        .allowsHitTesting(false)
    }
}
