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
                // Outer ring — powder blue periwinkle plastic bezel
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                Color(red: 0.72, green: 0.82, blue: 0.96),
                                Color(red: 0.80, green: 0.88, blue: 0.98),
                                Color(red: 0.65, green: 0.77, blue: 0.93),
                                Color(red: 0.78, green: 0.86, blue: 0.97),
                                Color(red: 0.72, green: 0.82, blue: 0.96),
                            ],
                            center: .center
                        )
                    )
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.30), radius: 12, x: 0, y: 6)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.50), lineWidth: 2)
                    )

                // Bezel inner shadow ring
                Circle()
                    .fill(Color(red: 0.55, green: 0.68, blue: 0.86))
                    .frame(width: size * 0.91, height: size * 0.91)

                // Clock face — deep navy/black
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.07, green: 0.10, blue: 0.22),
                                Color(red: 0.03, green: 0.05, blue: 0.15),
                                Color(red: 0.01, green: 0.02, blue: 0.09),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.44
                        )
                    )
                    .frame(width: size * 0.87, height: size * 0.87)

                // --- NEON CRUSTACEAN ARTWORK ---
                Canvas { ctx, canvasSize in
                    let cx = canvasSize.width / 2
                    let cy = canvasSize.height / 2
                    let r = min(canvasSize.width, canvasSize.height) / 2
                    let scale = r * 0.74  // art fills ~74% of face

                    // Glow helper: draw path multiple times with increasing alpha + width
                    func glowStroke(ctx: inout GraphicsContext, path: Path, color: Color, glowRadius: CGFloat, lineWidth: CGFloat) {
                        for i in stride(from: glowRadius, through: 0, by: -2) {
                            var glowCtx = ctx
                            glowCtx.stroke(path, with: .color(color.opacity(0.04 + 0.02 * (glowRadius - i) / glowRadius)),
                                           lineWidth: lineWidth + i * 1.5)
                        }
                        ctx.stroke(path, with: .color(color), lineWidth: lineWidth)
                    }

                    let cyan = Color(red: 0.0, green: 0.92, blue: 0.96)
                    let red  = Color(red: 1.0, green: 0.28, blue: 0.28)

                    // === BODY — central oval ===
                    let bodyPath = Path(ellipseIn: CGRect(
                        x: cx - scale * 0.18, y: cy - scale * 0.22,
                        width: scale * 0.36, height: scale * 0.44
                    ))
                    var bodyCtx = ctx
                    bodyCtx.stroke(bodyPath, with: .color(cyan.opacity(0.9)), lineWidth: 2.2)
                    // body glow
                    bodyCtx.stroke(bodyPath, with: .color(cyan.opacity(0.15)), lineWidth: 10)
                    ctx.stroke(bodyPath, with: .color(cyan.opacity(0.9)), lineWidth: 2.2)

                    // === SEGMENTED BELLY LINES ===
                    for i in 0..<4 {
                        let yt = cy - scale * 0.10 + CGFloat(i) * scale * 0.09
                        let hw = scale * 0.13 * (1 - CGFloat(i) * 0.10)
                        var seg = Path()
                        seg.move(to: CGPoint(x: cx - hw, y: yt))
                        seg.addCurve(to: CGPoint(x: cx + hw, y: yt),
                                     control1: CGPoint(x: cx - hw * 0.5, y: yt + scale * 0.03),
                                     control2: CGPoint(x: cx + hw * 0.5, y: yt + scale * 0.03))
                        ctx.stroke(seg, with: .color(cyan.opacity(0.55)), lineWidth: 1.2)
                    }

                    // === CLAWS — big outer (left & right) ===
                    for side in [-1.0, 1.0] {
                        // Upper big claw
                        var claw = Path()
                        let cx1 = cx + side * scale * 0.14
                        let cy1 = cy - scale * 0.08
                        claw.move(to: CGPoint(x: cx1, y: cy1))
                        claw.addCurve(
                            to: CGPoint(x: cx + side * scale * 0.52, y: cy - scale * 0.38),
                            control1: CGPoint(x: cx + side * scale * 0.30, y: cy - scale * 0.05),
                            control2: CGPoint(x: cx + side * scale * 0.46, y: cy - scale * 0.20)
                        )
                        ctx.stroke(claw, with: .color(cyan.opacity(0.85)), lineWidth: 2.8)
                        ctx.stroke(claw, with: .color(cyan.opacity(0.12)), lineWidth: 12)

                        // Claw pincer — top jaw
                        var pincer1 = Path()
                        pincer1.move(to: CGPoint(x: cx + side * scale * 0.52, y: cy - scale * 0.38))
                        pincer1.addCurve(
                            to: CGPoint(x: cx + side * scale * 0.65, y: cy - scale * 0.48),
                            control1: CGPoint(x: cx + side * scale * 0.56, y: cy - scale * 0.42),
                            control2: CGPoint(x: cx + side * scale * 0.62, y: cy - scale * 0.44)
                        )
                        ctx.stroke(pincer1, with: .color(cyan.opacity(0.80)), lineWidth: 2.2)

                        // Claw pincer — bottom jaw
                        var pincer2 = Path()
                        pincer2.move(to: CGPoint(x: cx + side * scale * 0.52, y: cy - scale * 0.38))
                        pincer2.addCurve(
                            to: CGPoint(x: cx + side * scale * 0.60, y: cy - scale * 0.28),
                            control1: CGPoint(x: cx + side * scale * 0.57, y: cy - scale * 0.34),
                            control2: CGPoint(x: cx + side * scale * 0.60, y: cy - scale * 0.31)
                        )
                        ctx.stroke(pincer2, with: .color(cyan.opacity(0.80)), lineWidth: 2.2)

                        // Mid walking legs (3 per side)
                        for leg in 0..<3 {
                            var legPath = Path()
                            let ly = cy + CGFloat(leg) * scale * 0.10
                            let lx = cx + side * scale * 0.15
                            legPath.move(to: CGPoint(x: lx, y: ly))
                            legPath.addCurve(
                                to: CGPoint(x: cx + side * scale * (0.45 + CGFloat(leg) * 0.04), y: ly + scale * 0.14),
                                control1: CGPoint(x: cx + side * scale * 0.28, y: ly + scale * 0.02),
                                control2: CGPoint(x: cx + side * scale * 0.38, y: ly + scale * 0.08)
                            )
                            ctx.stroke(legPath, with: .color(cyan.opacity(0.65)), lineWidth: 1.6)
                        }
                    }

                    // === ANTENNAE (2 per side) ===
                    for side in [-1.0, 1.0] {
                        // Long antenna
                        var ant = Path()
                        ant.move(to: CGPoint(x: cx + side * scale * 0.06, y: cy - scale * 0.22))
                        ant.addCurve(
                            to: CGPoint(x: cx + side * scale * 0.55, y: cy - scale * 0.70),
                            control1: CGPoint(x: cx + side * scale * 0.15, y: cy - scale * 0.40),
                            control2: CGPoint(x: cx + side * scale * 0.38, y: cy - scale * 0.60)
                        )
                        ctx.stroke(ant, with: .color(cyan.opacity(0.75)), lineWidth: 1.3)
                        ctx.stroke(ant, with: .color(cyan.opacity(0.08)), lineWidth: 6)

                        // Short inner antenna
                        var ant2 = Path()
                        ant2.move(to: CGPoint(x: cx + side * scale * 0.04, y: cy - scale * 0.22))
                        ant2.addCurve(
                            to: CGPoint(x: cx + side * scale * 0.30, y: cy - scale * 0.55),
                            control1: CGPoint(x: cx + side * scale * 0.10, y: cy - scale * 0.35),
                            control2: CGPoint(x: cx + side * scale * 0.22, y: cy - scale * 0.46)
                        )
                        ctx.stroke(ant2, with: .color(cyan.opacity(0.55)), lineWidth: 0.9)
                    }

                    // === SPIKY CROWN ===
                    let crownPoints: [(CGFloat, CGFloat)] = [
                        (-0.12, -0.22), (-0.22, -0.38), (-0.08, -0.28),
                        (0.0, -0.42),
                        (0.08, -0.28), (0.22, -0.38), (0.12, -0.22)
                    ]
                    var crown = Path()
                    crown.move(to: CGPoint(x: cx + crownPoints[0].0 * scale, y: cy + crownPoints[0].1 * scale))
                    for (i, pt) in crownPoints.enumerated() {
                        if i == 0 { continue }
                        crown.addLine(to: CGPoint(x: cx + pt.0 * scale, y: cy + pt.1 * scale))
                    }
                    ctx.stroke(crown, with: .color(cyan.opacity(0.80)), lineWidth: 2.0)
                    ctx.stroke(crown, with: .color(cyan.opacity(0.12)), lineWidth: 8)

                    // === GLOWING EYES (RED) ===
                    let eyeOffX = scale * 0.07
                    let eyeY = cy - scale * 0.04
                    let eyeR = scale * 0.055
                    for side in [-1.0, 1.0] {
                        let ex = cx + side * eyeOffX
                        let eyePath = Path(ellipseIn: CGRect(x: ex - eyeR, y: eyeY - eyeR * 0.7,
                                                              width: eyeR * 2, height: eyeR * 1.4))
                        // Red glow layers
                        ctx.stroke(eyePath, with: .color(red.opacity(0.08)), lineWidth: 10)
                        ctx.stroke(eyePath, with: .color(red.opacity(0.18)), lineWidth: 6)
                        ctx.stroke(eyePath, with: .color(red.opacity(0.50)), lineWidth: 3)
                        ctx.stroke(eyePath, with: .color(red.opacity(0.95)), lineWidth: 1.5)
                        // Eye fill
                        ctx.fill(eyePath, with: .color(red.opacity(0.35)))
                    }

                    // === SCORPION TAIL (curves up/down from body) ===
                    var tail = Path()
                    tail.move(to: CGPoint(x: cx, y: cy + scale * 0.22))
                    tail.addCurve(
                        to: CGPoint(x: cx + scale * 0.20, y: cy + scale * 0.55),
                        control1: CGPoint(x: cx + scale * 0.12, y: cy + scale * 0.30),
                        control2: CGPoint(x: cx + scale * 0.25, y: cy + scale * 0.42)
                    )
                    tail.addCurve(
                        to: CGPoint(x: cx - scale * 0.05, y: cy + scale * 0.66),
                        control1: CGPoint(x: cx + scale * 0.18, y: cy + scale * 0.63),
                        control2: CGPoint(x: cx + scale * 0.05, y: cy + scale * 0.68)
                    )
                    // Stinger tip
                    tail.addLine(to: CGPoint(x: cx - scale * 0.10, y: cy + scale * 0.62))
                    ctx.stroke(tail, with: .color(cyan.opacity(0.80)), lineWidth: 2.0)
                    ctx.stroke(tail, with: .color(cyan.opacity(0.10)), lineWidth: 8)

                }
                .frame(width: size * 0.87, height: size * 0.87)

                // Hour markers (on top of art)
                ForEach(0..<12) { i in
                    let angle = Double(i) * 30.0 - 90.0
                    let isMainHour = i % 3 == 0
                    let markerLength: CGFloat = isMainHour ? size * 0.065 : size * 0.035
                    let markerWidth: CGFloat = isMainHour ? 2.5 : 1.2
                    let outerRadius = size * 0.40
                    let innerRadius = outerRadius - markerLength
                    let cosA = cos(angle * .pi / 180)
                    let sinA = sin(angle * .pi / 180)

                    Path { path in
                        path.move(to: CGPoint(
                            x: center.x + innerRadius * cosA,
                            y: center.y + innerRadius * sinA
                        ))
                        path.addLine(to: CGPoint(
                            x: center.x + outerRadius * cosA,
                            y: center.y + outerRadius * sinA
                        ))
                    }
                    .stroke(
                        isMainHour
                            ? Color.white.opacity(0.92)
                            : Color.white.opacity(0.40),
                        style: StrokeStyle(lineWidth: markerWidth, lineCap: .round)
                    )
                    .shadow(color: isMainHour ? Color.white.opacity(0.35) : .clear, radius: 2)
                }

                // "JUNIPERO" label at top
                Text("JUNIPERO")
                    .font(.system(size: size * 0.088, weight: .semibold, design: .serif))
                    .tracking(4)
                    .foregroundColor(.white)
                    .shadow(color: Color(red: 0.0, green: 0.92, blue: 0.96).opacity(0.30), radius: 4)
                    .offset(y: -size * 0.245)

                // "powered by openclaw" label at bottom
                Text("powered by openclaw")
                    .font(.system(size: size * 0.038, weight: .regular, design: .default))
                    .tracking(2)
                    .foregroundColor(Color.white.opacity(0.55))
                    .offset(y: size * 0.245)

                // Hour hand
                ClockHand(
                    angle: hourAngle,
                    length: size * 0.22,
                    width: 4.5,
                    color: Color.white.opacity(0.95),
                    center: center,
                    tailLength: size * 0.05
                )
                .shadow(color: .black.opacity(0.5), radius: 3, x: 1, y: 1)

                // Minute hand
                ClockHand(
                    angle: minuteAngle,
                    length: size * 0.32,
                    width: 3.0,
                    color: Color.white.opacity(0.88),
                    center: center,
                    tailLength: size * 0.07
                )
                .shadow(color: .black.opacity(0.5), radius: 2, x: 1, y: 1)

                // Second hand — red
                ClockHand(
                    angle: secondAngle,
                    length: size * 0.35,
                    width: 1.2,
                    color: Color(red: 0.95, green: 0.28, blue: 0.28),
                    center: center,
                    tailLength: size * 0.08
                )
                .shadow(color: Color(red: 0.95, green: 0.28, blue: 0.28).opacity(0.4), radius: 3)

                // Center cap — gray pivot
                Circle()
                    .fill(Color(red: 0.65, green: 0.68, blue: 0.72))
                    .frame(width: size * 0.048, height: size * 0.048)
                    .shadow(color: .black.opacity(0.3), radius: 2)

                // Center dot — orange/red
                Circle()
                    .fill(Color(red: 0.92, green: 0.30, blue: 0.26))
                    .frame(width: size * 0.016, height: size * 0.016)
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
