import SwiftUI

struct AnalogClockView: View {
    @State private var currentTime = Date()

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    private let timezone = TimeZone(identifier: "America/Chicago")!

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                // Outer bezel
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.33, green: 0.35, blue: 0.39),
                                Color(red: 0.14, green: 0.15, blue: 0.18),
                                Color(red: 0.05, green: 0.06, blue: 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(Color(red: 0.66, green: 0.75, blue: 0.86).opacity(0.28), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 12)

                // Inner bezel ring with royal blue glow
                Circle()
                    .fill(Color(red: 0.07, green: 0.08, blue: 0.11))
                    .frame(width: size * 0.94, height: size * 0.94)
                    .overlay(
                        Circle()
                            .stroke(Color(red: 0.25, green: 0.45, blue: 0.98).opacity(0.50), lineWidth: 2.5)
                    )
                    .shadow(color: Color(red: 0.25, green: 0.40, blue: 0.98).opacity(0.45), radius: 20)

                // Deep obsidian face
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.12, green: 0.15, blue: 0.20),
                                Color(red: 0.06, green: 0.07, blue: 0.10),
                                Color.black
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: size * 0.42
                        )
                    )
                    .frame(width: size * 0.88, height: size * 0.88)

                // Subtle inner track ring
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    .frame(width: size * 0.82, height: size * 0.82)

                // Tick marks
                ForEach(0..<60) { i in
                    let angle = Double(i) * 6.0 - 90.0
                    let isMajor = i % 5 == 0
                    let outerRadius = size * 0.40
                    let innerRadius = outerRadius - (isMajor ? size * 0.055 : size * 0.02)
                    let cosA = cos(angle * .pi / 180)
                    let sinA = sin(angle * .pi / 180)

                    Path { path in
                        path.move(to: CGPoint(x: center.x + innerRadius * cosA, y: center.y + innerRadius * sinA))
                        path.addLine(to: CGPoint(x: center.x + outerRadius * cosA, y: center.y + outerRadius * sinA))
                    }
                    .stroke(
                        isMajor ? Color(red: 0.86, green: 0.90, blue: 0.96) : Color.white.opacity(0.18),
                        style: StrokeStyle(lineWidth: isMajor ? 2.4 : 0.8, lineCap: .round)
                    )
                    .shadow(color: isMajor ? Color(red: 0.40, green: 0.62, blue: 1.0).opacity(0.22) : .clear, radius: 3)
                }

                // THRAWN — elegant serif with royal blue glow
                Text("THRAWN")
                    .font(.custom("Didot", size: size * 0.082) != Font.custom("", size: 0) ? .custom("Didot", size: size * 0.082) : .system(size: size * 0.082, weight: .light, design: .serif))
                    .tracking(size * 0.018)
                    .foregroundColor(Color(red: 0.88, green: 0.93, blue: 0.99))
                    .shadow(color: Color(red: 0.28, green: 0.45, blue: 1.0).opacity(0.75), radius: 14)
                    .shadow(color: Color(red: 0.28, green: 0.45, blue: 1.0).opacity(0.35), radius: 28)
                    .offset(y: -size * 0.04)

                // COMMAND CENTER — compact, restrained
                Text("COMMAND CENTER")
                    .font(.system(size: size * 0.028, weight: .medium, design: .default))
                    .tracking(size * 0.012)
                    .foregroundColor(Color(red: 0.48, green: 0.60, blue: 0.82).opacity(0.85))
                    .frame(maxWidth: size * 0.55)
                    .offset(y: size * 0.08)

                // Clock hands
                ClockHand(angle: hourAngle, length: size * 0.20, width: 5.2, color: Color(red: 0.84, green: 0.88, blue: 0.94), center: center, tailLength: size * 0.045)
                    .shadow(color: .black.opacity(0.55), radius: 3)
                ClockHand(angle: minuteAngle, length: size * 0.30, width: 3.2, color: Color(red: 0.76, green: 0.82, blue: 0.92), center: center, tailLength: size * 0.065)
                    .shadow(color: .black.opacity(0.55), radius: 2)
                ClockHand(angle: secondAngle, length: size * 0.33, width: 1.4, color: Color(red: 0.30, green: 0.55, blue: 1.0), center: center, tailLength: size * 0.08)
                    .shadow(color: Color(red: 0.30, green: 0.55, blue: 1.0).opacity(0.75), radius: 10)

                // Center jewel
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color(red: 0.30, green: 0.52, blue: 1.0)],
                            center: .center,
                            startRadius: 1,
                            endRadius: size * 0.03
                        )
                    )
                    .frame(width: size * 0.058, height: size * 0.058)
                    .shadow(color: Color(red: 0.30, green: 0.52, blue: 1.0).opacity(0.70), radius: 10)
            }
        }
        .onReceive(timer) { _ in currentTime = Date() }
    }

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.timeZone = timezone
        return cal
    }

    private var hourAngle: Double {
        let h = Double(calendar.component(.hour, from: currentTime) % 12)
        let m = Double(calendar.component(.minute, from: currentTime))
        let s = Double(calendar.component(.second, from: currentTime))
        return (h + m / 60.0 + s / 3600.0) * 30.0 - 90.0
    }

    private var minuteAngle: Double {
        let m = Double(calendar.component(.minute, from: currentTime))
        let s = Double(calendar.component(.second, from: currentTime))
        return (m + s / 60.0) * 6.0 - 90.0
    }

    private var secondAngle: Double {
        let s = Double(calendar.component(.second, from: currentTime))
        let ns = Double(calendar.component(.nanosecond, from: currentTime))
        return (s + ns / 1_000_000_000.0) * 6.0 - 90.0
    }
}

struct ClockHand: View {
    let angle: Double
    let length: CGFloat
    let width: CGFloat
    let color: Color
    let center: CGPoint
    let tailLength: CGFloat

    var body: some View {
        Path { path in
            let cosA = cos(angle * .pi / 180)
            let sinA = sin(angle * .pi / 180)
            path.move(to: CGPoint(x: center.x - tailLength * cosA, y: center.y - tailLength * sinA))
            path.addLine(to: CGPoint(x: center.x + length * cosA, y: center.y + length * sinA))
        }
        .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
