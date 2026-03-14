import SwiftUI

// MARK: - Thrawn Chiss Palette
// Chiss skin: steel-slate blue ~#7BA7BC / HSB 200° 35% 74%
// Accent deep: #2A4A62
// Glass surface: near-black with blue tint

extension Color {
    static let chissPrimary   = Color(red: 0.484, green: 0.655, blue: 0.737) // #7BA7BC
    static let chissDeep      = Color(red: 0.165, green: 0.290, blue: 0.384) // #2A4A62
    static let chissDark      = Color(red: 0.055, green: 0.110, blue: 0.160) // #0E1C29
    static let obsidian       = Color(red: 0.040, green: 0.055, blue: 0.075) // #0A0E13
    static let obsidianMid    = Color(red: 0.072, green: 0.100, blue: 0.132) // #121922
    static let glassEdge      = Color(red: 0.484, green: 0.655, blue: 0.737).opacity(0.18)
}

struct ContentView: View {
    @EnvironmentObject var threadStore: ThreadStore

    var body: some View {
        ZStack {
            ThrawnObsidianBackdrop()
                .ignoresSafeArea()

            if threadStore.allThreadsMode {
                RightPanelView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                HStack(spacing: 0) {
                    LeftPanelView()
                        .frame(maxWidth: .infinity)

                    // Glass divider
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.chissPrimary.opacity(0.08),
                                    Color.chissPrimary.opacity(0.22),
                                    Color.chissPrimary.opacity(0.08),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 1)

                    RightPanelView()
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: threadStore.allThreadsMode)
    }
}

struct ThrawnObsidianBackdrop: View {
    var body: some View {
        ZStack {
            // Base obsidian
            Color.obsidian

            // Chiss blue ambient — top left
            RadialGradient(
                colors: [
                    Color.chissDeep.opacity(0.65),
                    Color.clear,
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 680
            )

            // Chiss blue ambient — bottom right
            RadialGradient(
                colors: [
                    Color.chissDark.opacity(0.80),
                    Color.clear,
                ],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 500
            )

            // Subtle center luminance — alien glass sheen
            RadialGradient(
                colors: [
                    Color.chissPrimary.opacity(0.06),
                    Color.clear,
                ],
                center: .center,
                startRadius: 0,
                endRadius: 600
            )

            // Fine noise/grain overlay — obsidian glass texture
            ObsidianGrainTexture()
                .blendMode(.screen)
                .opacity(0.028)
        }
    }
}

struct ObsidianGrainTexture: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                var rng = SystemRandomNumberGenerator()
                for _ in 0..<Int(size.width * size.height * 0.015) {
                    let x = CGFloat(rng.next() % UInt64(size.width))
                    let y = CGFloat(rng.next() % UInt64(size.height))
                    let bright = Double(rng.next() % 100) / 100.0
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)),
                        with: .color(Color.white.opacity(bright * 0.8))
                    )
                }
            }
        }
    }
}
