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

                Circle()
                    .fill(Color(red: 0.07, green: 0.08, blue: 0.11))
                    .frame(width: size * 0.94, height: size * 0.94)
                    .overlay(
                        Circle()
                            .stroke(Color(red: 0.40, green: 0.63, blue: 0.98).opacity(0.35), lineWidth: 2)
                    )
                    .shadow(color: Color(red: 0.30, green: 0.45, blue: 0.98).opacity(0.30), radius: 16)

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

                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    .frame(width: size * 0.82, height: size * 0.82)

                ForEach(0..<60) { i in
                    let angle = Double(i) * 6.0 - 90.0
                    let isMajor = i % 5 == 0
                    let outerRadius = size * 0.40
                    let innerRadius = outerRadius - (isMajor ? size * 0.055 : size * 0.02)
                    let width = isMajor ? 2.4 : 0.8
                    let color = isMajor ? Color(red: 0.86, green: 0.90, blue: 0.96) : Color.white.opacity(0.18)
                    let cosAngle = cos(angle * .pi / 180)
                    let sinAngle = sin(angle * .pi / 180)

                    Path { path in
                        path.move(to: CGPoint(x: center.x + innerRadius * cosAngle, y: center.y + innerRadius * sinAngle))
                        path.addLine(to: CGPoint(x: center.x + outerRadius * cosAngle, y: center.y + outerRadius * sinAngle))
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .shadow(color: isMajor ? Color(red: 0.40, green: 0.62, blue: 1.0).opacity(0.22) : .clear, radius: 3)
                }

                Text("THRAWN")
                    .font(.system(size: size * 0.09, weight: .bold, design: .serif))
                    .tracking(5)
                    .foregroundColor(Color(red: 0.82, green: 0.89, blue: 0.98))
                    .shadow(color: Color(red: 0.31, green: 0.47, blue: 1.0).opacity(0.55), radius: 10)
                    .offset(y: size * 0.02)

                Text("CHRONOMETRE COMMAND")
                    .font(.system(size: size * 0.032, weight: .medium, design: .serif))
                    .tracking(3)
                    .foregroundColor(Color(red: 0.52, green: 0.64, blue: 0.82))
                    .offset(y: size * 0.17)

                ClockHand(angle: hourAngle, length: size * 0.20, width: 5.2, color: Color(red: 0.84, green: 0.88, blue: 0.94), center: center, tailLength: size * 0.045)
                    .shadow(color: .black.opacity(0.55), radius: 3)
                ClockHand(angle: minuteAngle, length: size * 0.30, width: 3.2, color: Color(red: 0.76, green: 0.82, blue: 0.92), center: center, tailLength: size * 0.065)
                    .shadow(color: .black.opacity(0.55), radius: 2)
                ClockHand(angle: secondAngle, length: size * 0.33, width: 1.4, color: Color(red: 0.36, green: 0.60, blue: 1.0), center: center, tailLength: size * 0.08)
                    .shadow(color: Color(red: 0.36, green: 0.60, blue: 1.0).opacity(0.65), radius: 8)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color(red: 0.36, green: 0.60, blue: 1.0)],
                            center: .center,
                            startRadius: 1,
                            endRadius: size * 0.03
                        )
                    )
                    .frame(width: size * 0.06, height: size * 0.06)
                    .shadow(color: Color(red: 0.36, green: 0.60, blue: 1.0).opacity(0.6), radius: 8)
            }
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.timeZone = timezone
        return cal
    }

    private var hourAngle: Double {
        let hour = Double(calendar.component(.hour, from: currentTime) % 12)
        let minute = Double(calendar.component(.minute, from: currentTime))
        let second = Double(calendar.component(.second, from: currentTime))
        return (hour + minute / 60.0 + second / 3600.0) * 30.0 - 90.0
    }

    private var minuteAngle: Double {
        let minute = Double(calendar.component(.minute, from: currentTime))
        let second = Double(calendar.component(.second, from: currentTime))
        return (minute + second / 60.0) * 6.0 - 90.0
    }

    private var secondAngle: Double {
        let second = Double(calendar.component(.second, from: currentTime))
        let nanosecond = Double(calendar.component(.nanosecond, from: currentTime))
        return (second + nanosecond / 1_000_000_000.0) * 6.0 - 90.0
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
            let cosAngle = cos(angle * .pi / 180)
            let sinAngle = sin(angle * .pi / 180)
            let tailX = center.x - tailLength * cosAngle
            let tailY = center.y - tailLength * sinAngle
            let tipX = center.x + length * cosAngle
            let tipY = center.y + length * sinAngle
            path.move(to: CGPoint(x: tailX, y: tailY))
            path.addLine(to: CGPoint(x: tipX, y: tipY))
        }
        .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
