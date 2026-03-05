import SwiftUI

struct ContentView: View {
    @EnvironmentObject var threadStore: ThreadStore

    var body: some View {
        ZStack {
            // Linen/cream background
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.96, blue: 0.93),
                    Color(red: 0.96, green: 0.94, blue: 0.90),
                    Color(red: 0.97, green: 0.95, blue: 0.91),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle linen texture overlay
            LinenTexture()
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

// Subtle linen texture effect
struct LinenTexture: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.02),
                        Color.brown.opacity(0.02),
                        Color.white.opacity(0.01),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .blendMode(.multiply)
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
