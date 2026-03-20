import SwiftUI

struct AnalogClockView: View {
    @State private var currentTime = Date()

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    private let timezone = TimeZone(identifier: "America/Chicago")!

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let _ = size / 2 // radius available if needed

            ZStack {
                // Outer ring — blue chrome
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                Color(red: 0.55, green: 0.70, blue: 0.93),
                                Color(red: 0.62, green: 0.76, blue: 0.96),
                                Color(red: 0.50, green: 0.66, blue: 0.90),
                                Color(red: 0.60, green: 0.74, blue: 0.95),
                                Color(red: 0.55, green: 0.70, blue: 0.93),
                            ],
                            center: .center
                        )
                    )
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
                    .overlay(
                        Circle()
                            .stroke(Color(red: 0.42, green: 0.88, blue: 0.98).opacity(0.28), lineWidth: 2)
                    )

                // Inner bezel
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.19, green: 0.32, blue: 0.58),
                                Color(red: 0.11, green: 0.22, blue: 0.45),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.92, height: size * 0.92)

                // Clock face — deep obsidian
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.08, green: 0.13, blue: 0.30),
                                Color(red: 0.03, green: 0.06, blue: 0.20),
                                Color(red: 0.01, green: 0.03, blue: 0.12),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.44
                        )
                    )
                    .frame(width: size * 0.88, height: size * 0.88)

                // Hour markers
                ForEach(0..<12) { i in
                    let angle = Double(i) * 30.0 - 90.0
                    let isMainHour = i % 3 == 0
                    let markerLength: CGFloat = isMainHour ? size * 0.07 : size * 0.04
                    let markerWidth: CGFloat = isMainHour ? 3.0 : 1.5
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
                            ? Color(red: 0.80, green: 0.95, blue: 1.0)
                            : Color(red: 0.50, green: 0.66, blue: 0.88),
                        style: StrokeStyle(lineWidth: markerWidth, lineCap: .round)
                    )
                    .shadow(color: isMainHour ? Color(red: 0.50, green: 0.90, blue: 1.0).opacity(0.28) : .clear, radius: 2)
                }

                // Minute tick marks
                ForEach(0..<60) { i in
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
                        .stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 0.5, lineCap: .round))
                    }
                }

                // "O'BRIEN" text at top
                Text("JUNIPERO")
                    .font(.system(size: size * 0.09, weight: .semibold, design: .serif))
                    .tracking(5)
                    .foregroundColor(Color(red: 0.76, green: 0.90, blue: 0.98))
                    .offset(y: -size * 0.18)

                // "CHICAGO" text at bottom
                Text("SAN JUNIPERO")
                    .font(.system(size: size * 0.042, weight: .regular, design: .default))
                    .tracking(5)
                    .foregroundColor(Color(red: 0.52, green: 0.66, blue: 0.84))
                    .offset(y: size * 0.21)

                // Hour hand
                ClockHand(
                    angle: hourAngle,
                    length: size * 0.22,
                    width: 4.5,
                    color: Color(red: 0.86, green: 0.94, blue: 1.0),
                    center: center,
                    tailLength: size * 0.05
                )
                .shadow(color: .black.opacity(0.5), radius: 3, x: 1, y: 1)

                // Minute hand
                ClockHand(
                    angle: minuteAngle,
                    length: size * 0.32,
                    width: 3.0,
                    color: Color(red: 0.80, green: 0.90, blue: 0.98),
                    center: center,
                    tailLength: size * 0.07
                )
                .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 1)

                // Second hand
                ClockHand(
                    angle: secondAngle,
                    length: size * 0.35,
                    width: 1.2,
                    color: Color(red: 0.92, green: 0.30, blue: 0.26),
                    center: center,
                    tailLength: size * 0.08
                )
                .shadow(color: Color(red: 0.92, green: 0.30, blue: 0.26).opacity(0.3), radius: 2)

                // Center cap
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.80, green: 0.92, blue: 1.0),
                                Color(red: 0.48, green: 0.64, blue: 0.86),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.025
                        )
                    )
                    .frame(width: size * 0.05, height: size * 0.05)
                    .shadow(color: .black.opacity(0.3), radius: 2)

                // Inner center dot
                Circle()
                    .fill(Color(red: 0.92, green: 0.30, blue: 0.26))
                    .frame(width: size * 0.015, height: size * 0.015)
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

            // Tail (opposite direction)
            let tailX = center.x - tailLength * cosAngle
            let tailY = center.y - tailLength * sinAngle

            // Tip
            let tipX = center.x + length * cosAngle
            let tipY = center.y + length * sinAngle

            path.move(to: CGPoint(x: tailX, y: tailY))
            path.addLine(to: CGPoint(x: tipX, y: tipY))
        }
        .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
