import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bootstrap: HermesBootstrap
    @EnvironmentObject var threadStore: ThreadStore

    var body: some View {
        HStack(spacing: 0) {
            LeftPanelView()
                .frame(width: 380)

            Rectangle()
                .fill(JuniperoTheme.copper.opacity(0.3))
                .frame(width: 1)

            RightPanelView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    JuniperoTheme.backgroundPrimary,
                    JuniperoTheme.backgroundPrimary.opacity(0.97)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .frame(minWidth: 1200, minHeight: 800)
    }
}
