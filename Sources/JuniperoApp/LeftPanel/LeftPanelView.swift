import SwiftUI

struct LeftPanelView: View {
    var body: some View {
        HStack(spacing: 18) {
            AgentRailView()
                .frame(width: 330)

            VStack(spacing: 20) {
                Spacer(minLength: 10)

                AnalogClockView()
                    .frame(width: 360, height: 360)

                VStack(alignment: .leading, spacing: 10) {
                    Text("THRAWN")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .tracking(4)
                        .foregroundColor(Color.white.opacity(0.95))
                    Text("Executive command surface for Andrew. One interface. A full fleet behind it.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.66))
                        .frame(maxWidth: 420, alignment: .leading)
                    Text("The console should talk to OpenClaw through the same Gateway-native route as the dashboard, while exposing tasks, reviews, approvals, deliverables, and agent handoffs.")
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundColor(Color(red: 0.62, green: 0.74, blue: 0.88))
                        .frame(maxWidth: 460, alignment: .leading)
                }
                .padding(.horizontal, 8)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
    }
}
