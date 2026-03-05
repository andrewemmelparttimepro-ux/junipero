import SwiftUI

struct ContentView: View {
    @EnvironmentObject var threadStore: ThreadStore

    var body: some View {
        ZStack {
            // San Junipero-inspired dusk background.
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.16),
                    Color(red: 0.06, green: 0.10, blue: 0.24),
                    Color(red: 0.11, green: 0.07, blue: 0.24),
                    Color(red: 0.09, green: 0.16, blue: 0.31),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            AtmosphereHaze()
                .ignoresSafeArea()
            RetroGridOverlay()
                .ignoresSafeArea()

            if threadStore.allThreadsMode {
                RightPanelView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                HStack(spacing: 0) {
                    // Left Panel — 40%
                    LeftPanelView()
                        .frame(maxWidth: .infinity)

                    // Subtle divider
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.05),
                                    Color.black.opacity(0.1),
                                    Color.black.opacity(0.05),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 1)

                    // Right Panel — 60%
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

struct AtmosphereHaze: View {
    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color(red: 0.10, green: 0.62, blue: 0.92).opacity(0.30),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 10,
                endRadius: 540
            )
            .offset(x: -120, y: -120)

            RadialGradient(
                colors: [
                    Color(red: 0.98, green: 0.22, blue: 0.58).opacity(0.22),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 520
            )
            .offset(x: 90, y: 110)
        }
    }
}

struct RetroGridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let step: CGFloat = 34
            Path { path in
                var y: CGFloat = 0
                while y <= geo.size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    y += step
                }
                var x: CGFloat = 0
                while x <= geo.size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    x += step
                }
            }
            .stroke(Color.white.opacity(0.035), lineWidth: 0.7)
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.06),
                        Color.clear,
                        Color.white.opacity(0.04),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.softLight)
            )
        }
    }
}

struct GeometryRatioLayout: Layout {
    let leftRatio: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        return proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let leftWidth = bounds.width * leftRatio
        let rightWidth = bounds.width * (1 - leftRatio)

        subviews[0].place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: leftWidth, height: bounds.height)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + leftWidth, y: bounds.minY),
            proposal: ProposedViewSize(width: rightWidth, height: bounds.height)
        )
    }
}
