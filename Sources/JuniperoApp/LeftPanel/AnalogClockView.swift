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

            if let reference = ClockReferenceLoader.load() {
                Image(nsImage: reference)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .scaleEffect(ClockReferenceLoader.zoom(for: reference))
                    .clipShape(Circle())
                    .clipped()
                    .shadow(color: Color.black.opacity(0.20), radius: 10, x: 0, y: 4)
            } else {
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
                    }

                    ClockHand(
                        angle: hourAngle,
                        length: size * 0.22,
                        width: 4.5,
                        color: Color(red: 0.86, green: 0.94, blue: 1.0),
                        center: center,
                        tailLength: size * 0.05
                    )

                    ClockHand(
                        angle: minuteAngle,
                        length: size * 0.32,
                        width: 3.0,
                        color: Color(red: 0.80, green: 0.90, blue: 0.98),
                        center: center,
                        tailLength: size * 0.07
                    )

                    ClockHand(
                        angle: secondAngle,
                        length: size * 0.35,
                        width: 1.2,
                        color: Color(red: 0.94, green: 0.30, blue: 0.32),
                        center: center,
                        tailLength: size * 0.08
                    )
                }
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

    static func zoom(for image: NSImage) -> CGFloat {
        let width = image.size.width
        let height = image.size.height
        guard width > 0, height > 0 else { return 1.0 }
        let ratio = width / height

        // Heavier center crop for wide/tall source images so the clock art fills the widget.
        if ratio > 1.25 || ratio < 0.80 {
            return 2.0
        }
        if ratio > 1.10 || ratio < 0.90 {
            return 1.5
        }
        return 1.2
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
