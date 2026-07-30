import SwiftUI

struct ThrawnActivitySpinner: View {
    let active: Bool
    var diameter: CGFloat = 24
    var lineWidth: CGFloat = 2.4
    var trackOpacity: Double = 0.16

    @State private var rotation: Double = 0
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.chissPrimary.opacity(active ? trackOpacity : 0), lineWidth: lineWidth)

            Circle()
                .trim(from: 0.04, to: 0.31)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.48, green: 0.90, blue: 1.0),
                            Color(red: 0.30, green: 0.85, blue: 0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(rotation))
                .opacity(active ? 1 : 0)
                .shadow(color: Color.chissPrimary.opacity(active ? 0.85 : 0), radius: diameter * 0.08)

            Circle()
                .fill(Color(red: 0.30, green: 0.85, blue: 0.55))
                .frame(width: max(4, diameter * 0.12), height: max(4, diameter * 0.12))
                .offset(y: -diameter / 2)
                .rotationEffect(.degrees(rotation))
                .opacity(active ? 1 : 0)
                .shadow(color: Color(red: 0.30, green: 0.85, blue: 0.55).opacity(active ? 0.9 : 0), radius: diameter * 0.10)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(active && pulse ? 1.035 : 1.0)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
        .onAppear { updateAnimation(active) }
        .onChange(of: active) { updateAnimation($0) }
    }

    private func updateAnimation(_ shouldRun: Bool) {
        guard shouldRun else {
            rotation = 0
            pulse = false
            return
        }
        rotation = 0
        pulse = false
        DispatchQueue.main.async {
            withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            pulse = true
        }
    }
}
