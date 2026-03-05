import SwiftUI
#if os(macOS)
import AppKit
#endif

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
                                Color(red: 0.67, green: 0.79, blue: 0.96),
                                Color(red: 0.56, green: 0.72, blue: 0.93),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .shadow(color: Color(red: 0.52, green: 0.74, blue: 0.98).opacity(0.35), radius: 12, x: 0, y: 6)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.22, green: 0.34, blue: 0.60),
                                Color(red: 0.12, green: 0.22, blue: 0.44),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.93, height: size * 0.93)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.08, green: 0.14, blue: 0.36),
                                Color(red: 0.03, green: 0.07, blue: 0.20),
                                Color(red: 0.01, green: 0.03, blue: 0.12),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.44
                        )
                    )
                    .frame(width: size * 0.88, height: size * 0.88)

                // If a reference image is dropped in ~/.junipero/clock-reference.(png|jpg|jpeg), use it for exact art.
                if let reference = ClockReferenceLoader.load() {
                    Image(nsImage: reference)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size * 0.68, height: size * 0.68)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.8))
                        .shadow(color: Color(red: 0.31, green: 0.92, blue: 0.96).opacity(0.30), radius: 8)
                } else {
                    NeonLobsterGlyph()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.34, green: 0.94, blue: 0.98),
                                    Color(red: 0.98, green: 0.34, blue: 0.48),
                                    Color(red: 0.34, green: 0.94, blue: 0.98),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: size * 0.58, height: size * 0.58)
                        .shadow(color: Color(red: 0.31, green: 0.92, blue: 0.96).opacity(0.55), radius: 6)
                        .shadow(color: Color(red: 0.98, green: 0.35, blue: 0.50).opacity(0.35), radius: 8)
                }

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
                            : Color(red: 0.56, green: 0.72, blue: 0.90),
                        style: StrokeStyle(lineWidth: markerWidth, lineCap: .round)
                    )
                    .shadow(color: isMainHour ? Color(red: 0.50, green: 0.90, blue: 1.0).opacity(0.45) : .clear, radius: 3)
                }

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

                Text("JUNIPERO")
                    .font(.system(size: size * 0.04, weight: .light, design: .serif))
                    .tracking(4)
                    .foregroundColor(Color(red: 0.84, green: 0.94, blue: 1.0))
                    .offset(y: -size * 0.20)

                Text("powered by openclaw")
                    .font(.system(size: size * 0.03, weight: .regular, design: .rounded))
                    .foregroundColor(Color(red: 0.66, green: 0.80, blue: 0.95).opacity(0.88))
                    .padding(.horizontal, size * 0.03)
                    .padding(.vertical, size * 0.01)
                    .background(
                        Capsule().fill(Color.black.opacity(0.22))
                    )
                    .offset(y: size * 0.19)

                ClockHand(
                    angle: hourAngle,
                    length: size * 0.22,
                    width: 4.5,
                    color: Color(red: 0.86, green: 0.94, blue: 1.0),
                    center: center,
                    tailLength: size * 0.05
                )
                .shadow(color: .black.opacity(0.5), radius: 3, x: 1, y: 1)

                ClockHand(
                    angle: minuteAngle,
                    length: size * 0.32,
                    width: 3.0,
                    color: Color(red: 0.80, green: 0.90, blue: 0.98),
                    center: center,
                    tailLength: size * 0.07
                )
                .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 1)

                ClockHand(
                    angle: secondAngle,
                    length: size * 0.35,
                    width: 1.2,
                    color: Color(red: 0.94, green: 0.30, blue: 0.32),
                    center: center,
                    tailLength: size * 0.08
                )
                .shadow(color: Color(red: 0.94, green: 0.30, blue: 0.32).opacity(0.3), radius: 2)

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

                Circle()
                    .fill(Color(red: 0.94, green: 0.30, blue: 0.32))
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

private enum ClockReferenceLoader {
    static func load() -> NSImage? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = home.appendingPathComponent(".junipero", isDirectory: true)
        let candidates = [
            "clock-reference.png",
            "clock-reference.jpg",
            "clock-reference.jpeg"
        ]
        for name in candidates {
            let path = base.appendingPathComponent(name).path
            if let image = NSImage(contentsOfFile: path) {
                return image
            }
        }

        if let bundledPath = Bundle.main.path(forResource: "clock-reference-default", ofType: "png"),
            let image = NSImage(contentsOfFile: bundledPath)
        {
            return image
        }
        return nil
    }
}

struct NeonLobsterGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let w = rect.width
        let h = rect.height

        p.addEllipse(in: CGRect(x: c.x - w * 0.12, y: c.y - h * 0.08, width: w * 0.24, height: h * 0.28))
        p.addRoundedRect(in: CGRect(x: c.x - w * 0.09, y: c.y + h * 0.08, width: w * 0.18, height: h * 0.28), cornerSize: CGSize(width: 6, height: 6))

        p.move(to: CGPoint(x: c.x - w * 0.08, y: c.y + h * 0.12))
        p.addLine(to: CGPoint(x: c.x + w * 0.08, y: c.y + h * 0.12))
        p.move(to: CGPoint(x: c.x - w * 0.08, y: c.y + h * 0.20))
        p.addLine(to: CGPoint(x: c.x + w * 0.08, y: c.y + h * 0.20))
        p.move(to: CGPoint(x: c.x - w * 0.08, y: c.y + h * 0.28))
        p.addLine(to: CGPoint(x: c.x + w * 0.08, y: c.y + h * 0.28))

        p.addArc(center: CGPoint(x: c.x - w * 0.22, y: c.y - h * 0.14), radius: w * 0.14, startAngle: .degrees(28), endAngle: .degrees(240), clockwise: false)
        p.addArc(center: CGPoint(x: c.x + w * 0.22, y: c.y - h * 0.14), radius: w * 0.14, startAngle: .degrees(-60), endAngle: .degrees(152), clockwise: false)

        p.addArc(center: CGPoint(x: c.x - w * 0.28, y: c.y - h * 0.22), radius: w * 0.10, startAngle: .degrees(20), endAngle: .degrees(220), clockwise: false)
        p.addArc(center: CGPoint(x: c.x + w * 0.28, y: c.y - h * 0.22), radius: w * 0.10, startAngle: .degrees(-40), endAngle: .degrees(160), clockwise: false)

        p.move(to: CGPoint(x: c.x - w * 0.08, y: c.y - h * 0.28))
        p.addLine(to: CGPoint(x: c.x - w * 0.02, y: c.y - h * 0.18))
        p.move(to: CGPoint(x: c.x + w * 0.08, y: c.y - h * 0.28))
        p.addLine(to: CGPoint(x: c.x + w * 0.02, y: c.y - h * 0.18))

        return p
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
