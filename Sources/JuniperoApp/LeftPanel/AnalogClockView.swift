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
                // Outer bezel — brushed steel angular gradient
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                Color(white: 0.38),
                                Color(white: 0.28),
                                Color(white: 0.42),
                                Color(white: 0.22),
                                Color(white: 0.36),
                                Color(white: 0.30),
                                Color(white: 0.38),
                            ],
                            center: .center
                        )
                    )
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.50), radius: 14, x: 0, y: 6)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )

                // Inner bezel ring — dark steel
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(white: 0.18),
                                Color(white: 0.12),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.92, height: size * 0.92)

                // Clock face — deep black
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.06, green: 0.06, blue: 0.07),
                                Color(red: 0.03, green: 0.03, blue: 0.04),
                                Color(red: 0.02, green: 0.02, blue: 0.02),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.44
                        )
                    )
                    .frame(width: size * 0.88, height: size * 0.88)

                // Minute tick marks
                ForEach(0..<60, id: \.self) { i in
                    if i % 5 != 0 {
                        let angle = Double(i) * 6.0 - 90.0
                        let outerRadius = size * 0.40
                        let innerRadius = outerRadius - size * 0.015

                        let cosAngle = cos(angle * .pi / 180)
                        let sinAngle = sin(angle * .pi / 180)

                        Path { path in
                            path.move(to: CGPoint(
                                x: center.x + innerRadius * cosAngle,
                                y: center.y + innerRadius * sinAngle
                            ))
                            path.addLine(to: CGPoint(
                                x: center.x + outerRadius * cosAngle,
                                y: center.y + outerRadius * sinAngle
                            ))
                        }
                        .stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: 0.5, lineCap: .round))
                    }
                }

                // Hour markers
                ForEach(0..<12, id: \.self) { i in
                    let angle = Double(i) * 30.0 - 90.0
                    let isMainHour = i % 3 == 0
                    let markerLength: CGFloat = isMainHour ? size * 0.07 : size * 0.04
                    let markerWidth: CGFloat = isMainHour ? 2.5 : 1.2
                    let outerRadius = size * 0.40
                    let innerRadius = outerRadius - markerLength

                    let cosAngle = cos(angle * .pi / 180)
                    let sinAngle = sin(angle * .pi / 180)

                    Path { path in
                        path.move(to: CGPoint(
                            x: center.x + innerRadius * cosAngle,
                            y: center.y + innerRadius * sinAngle
                        ))
                        path.addLine(to: CGPoint(
                            x: center.x + outerRadius * cosAngle,
                            y: center.y + outerRadius * sinAngle
                        ))
                    }
                    .stroke(
                        isMainHour
                            ? Color.white.opacity(0.85)
                            : Color.white.opacity(0.35),
                        style: StrokeStyle(lineWidth: markerWidth, lineCap: .round)
                    )
                }

                // Brand text "JUNIPERO" — luxury watch dial inscription
                Text("JUNIPERO")
                    .font(.system(size: size * 0.078, weight: .light, design: .serif))
                    .tracking(6)
                    .foregroundColor(Color.white.opacity(0.55))
                    .offset(y: -size * 0.18)

                // Sub text
                Text("SAN JUNIPERO")
                    .font(.system(size: size * 0.035, weight: .ultraLight, design: .default))
                    .tracking(4)
                    .foregroundColor(Color.white.opacity(0.25))
                    .offset(y: size * 0.21)

                // Hour hand — white
                ClockHand(
                    angle: hourAngle,
                    length: size * 0.22,
                    width: 4.0,
                    color: Color.white.opacity(0.90),
                    center: center,
                    tailLength: size * 0.05
                )
                .shadow(color: .black.opacity(0.60), radius: 3, x: 1, y: 1)

                // Minute hand — white, thinner
                ClockHand(
                    angle: minuteAngle,
                    length: size * 0.32,
                    width: 2.5,
                    color: Color.white.opacity(0.85),
                    center: center,
                    tailLength: size * 0.07
                )
                .shadow(color: .black.opacity(0.50), radius: 2, x: 1, y: 1)

                // Second hand — red accent (the only color)
                ClockHand(
                    angle: secondAngle,
                    length: size * 0.35,
                    width: 1.0,
                    color: Color(red: 0.85, green: 0.18, blue: 0.15),
                    center: center,
                    tailLength: size * 0.08
                )
                .shadow(color: Color(red: 0.85, green: 0.18, blue: 0.15).opacity(0.30), radius: 4)

                // Center cap — brushed steel
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(white: 0.55),
                                Color(white: 0.25),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.025
                        )
                    )
                    .frame(width: size * 0.045, height: size * 0.045)
                    .shadow(color: .black.opacity(0.40), radius: 2)

                // Inner center dot — red
                Circle()
                    .fill(Color(red: 0.85, green: 0.18, blue: 0.15))
                    .frame(width: size * 0.012, height: size * 0.012)
            }
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }

    // MARK: - Time Calculations

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

// MARK: - Clock Hand Shape

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
