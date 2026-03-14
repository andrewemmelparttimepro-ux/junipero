import SwiftUI

struct ContentView: View {
    @EnvironmentObject var threadStore: ThreadStore

    var body: some View {
        ZStack {
            ThrawnBackdrop()
                .ignoresSafeArea()

            if threadStore.allThreadsMode {
                RightPanelView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                HStack(spacing: 18) {
                    LeftPanelView()
                        .frame(maxWidth: .infinity)

                    RightPanelView()
                        .frame(maxWidth: .infinity)
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: threadStore.allThreadsMode)
    }
}

struct ThrawnBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.07),
                    Color(red: 0.08, green: 0.09, blue: 0.12),
                    Color(red: 0.05, green: 0.06, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.14, green: 0.18, blue: 0.30).opacity(0.55),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 700
            )

            RadialGradient(
                colors: [
                    Color(red: 0.18, green: 0.26, blue: 0.52).opacity(0.22),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 520
            )

            Rectangle()
                .fill(Color.white.opacity(0.018))
                .blendMode(.screen)
        }
    }
}
