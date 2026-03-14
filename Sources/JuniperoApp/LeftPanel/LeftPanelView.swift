import SwiftUI

struct LeftPanelView: View {
    var body: some View {
        HStack(spacing: 16) {
            AgentRailView()
                .frame(width: 310)

            VStack(spacing: 0) {
                Spacer(minLength: 12)

                AnalogClockView()
                    .frame(width: 340, height: 340)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }
}
