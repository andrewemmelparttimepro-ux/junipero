import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bootstrap: HermesBootstrap
    @EnvironmentObject var threadStore: ThreadStore

    var body: some View {
        HStack(spacing: 0) {
            LeftPanelView()
                .frame(width: 380)

            Rectangle()
                .fill(JuniperoTheme.divider)
                .frame(width: 1)

            RightPanelView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(JuniperoTheme.backgroundPrimary)
        .frame(minWidth: 1200, minHeight: 800)
    }
}
