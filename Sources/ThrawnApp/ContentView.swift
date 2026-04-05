import SwiftUI

// MARK: - Thrawn Chiss Palette
extension Color {
    static let chissPrimary   = Color(red: 0.484, green: 0.655, blue: 0.737)
    static let chissDeep      = Color(red: 0.165, green: 0.290, blue: 0.384)
    static let chissDark      = Color(red: 0.055, green: 0.110, blue: 0.160)
    static let obsidian       = Color(red: 0.040, green: 0.055, blue: 0.075)
    static let obsidianMid    = Color(red: 0.072, green: 0.100, blue: 0.132)
    static let sithRed        = Color(red: 0.72, green: 0.08, blue: 0.10)
    static let sithGlow       = Color(red: 0.85, green: 0.12, blue: 0.14)
}

struct ContentView: View {
    @EnvironmentObject var flowTab: FlowTabStore
    @EnvironmentObject var execution: ExecutionService

    private var isUnleashed: Bool { execution.accessMode.isUnleashed }

    var body: some View {
        ZStack {
            ThrawnObsidianBackdrop()
                .ignoresSafeArea()

            if flowTab.showFlow {
                FlowBoardView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                HStack(spacing: 0) {
                    LeftPanelView()
                        .frame(maxWidth: .infinity)

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
        .animation(.easeInOut(duration: 0.22), value: flowTab.showFlow)
        // Unleashed mode: subtle red edge glow
        .overlay(
            Group {
                if isUnleashed {
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.sithGlow.opacity(0.15),
                                    Color.sithRed.opacity(0.05),
                                    Color.clear,
                                    Color.sithRed.opacity(0.05),
                                    Color.sithGlow.opacity(0.15)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2
                        )
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        )
        .animation(.easeInOut(duration: 0.4), value: isUnleashed)
        // Unleash confirmation dialog
        .sheet(isPresented: $execution.showUnleashConfirmation) {
            UnleashConfirmationView()
                .environmentObject(execution)
        }
    }
}

struct ThrawnObsidianBackdrop: View {
    var body: some View {
        ZStack {
            Color.obsidian
            RadialGradient(colors: [Color.chissDeep.opacity(0.65), Color.clear], center: .topLeading, startRadius: 0, endRadius: 680)
            RadialGradient(colors: [Color.chissDark.opacity(0.80), Color.clear], center: .bottomTrailing, startRadius: 0, endRadius: 500)
            RadialGradient(colors: [Color.chissPrimary.opacity(0.06), Color.clear], center: .center, startRadius: 0, endRadius: 600)
            ObsidianGrainTexture().blendMode(.screen).opacity(0.028)
        }
    }
}

struct ObsidianGrainTexture: View {
    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, size in
                var rng = SystemRandomNumberGenerator()
                for _ in 0..<Int(size.width * size.height * 0.015) {
                    let x = CGFloat(rng.next() % UInt64(size.width))
                    let y = CGFloat(rng.next() % UInt64(size.height))
                    let bright = Double(rng.next() % 100) / 100.0
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)), with: .color(Color.white.opacity(bright * 0.8)))
                }
            }
        }
    }
}
