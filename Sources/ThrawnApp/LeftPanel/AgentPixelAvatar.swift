import SwiftUI
import AppKit

// MARK: - Agent Pixel Avatar
//
// Hand-crafted 12×12 pixel-art portraits — CryptoPunk-style homages to each
// agent's namesake. Offline-first, fully deterministic, no network required.
// Unknown agents fall back to a procedural pattern.
//
// Grid encoding: '.' = transparent background, all other chars look up a
// per-character color palette.

private struct ResourceImageAvatar: View {
    let resourceName: String
    let size: CGFloat

    private var nsImage: NSImage? {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        if let nsImage {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFill()
                .frame(width: size, height: size)
        } else {
            EmptyView()
        }
    }
}

// MARK: - Agent Pixel Avatar

struct AgentPixelAvatar: View {
    let agentId: String
    let agentName: String
    let state: AgentActivityState
    let size: CGFloat

    @State private var pulseActive = false

    private var isActive: Bool {
        state == .working || state == .handoff
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Character portrait
            avatarCanvas
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                        .stroke(
                            isActive ? state.chissColor.opacity(0.85) : state.chissColor.opacity(0.30),
                            lineWidth: isActive ? 1.5 : 1
                        )
                )
                .shadow(
                    color: isActive ? state.chissColor.opacity(0.55) : state.chissColor.opacity(0.15),
                    radius: isActive ? 8 : 3
                )

            // Active pulse ring
            if isActive {
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .stroke(state.chissColor.opacity(0.35), lineWidth: 1.5)
                    .frame(width: size, height: size)
                    .scaleEffect(pulseActive ? 1.25 : 1.0)
                    .opacity(pulseActive ? 0 : 0.7)
                    .animation(
                        Animation.easeOut(duration: 1.8).repeatForever(autoreverses: false),
                        value: pulseActive
                    )
            }

            // Status jewel — Discord-style corner dot
            StatusJewel(state: state, dotSize: size * 0.30)
                .offset(x: 2, y: 2)
        }
        .onChange(of: isActive) { active in
            pulseActive = false
            if active {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { pulseActive = true }
            }
        }
        .onAppear {
            if isActive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { pulseActive = true }
            }
        }
    }

    @ViewBuilder
    private var avatarCanvas: some View {
        if let resourceName = resourceAvatarName {
            ResourceImageAvatar(resourceName: resourceName, size: size)
        } else {
            FallbackPixelAvatar(agentId: agentId, size: size)
        }
    }

    private var resourceAvatarName: String? {
        switch agentId.lowercased() {
        case "thrawn":
            return "thrawn-agent-avatar"
        case "archivist":
            return "samwell-agent-avatar"
        case "sentinel":
            return "sir-davos-agent-avatar"
        case "dwight":
            return "dwight-agent-avatar"
        default:
            return nil
        }
    }
}

// MARK: - Status Jewel Dot

private struct StatusJewel: View {
    let state: AgentActivityState
    let dotSize: CGFloat

    var body: some View {
        Circle()
            .fill(state.chissColor)
            .frame(width: dotSize, height: dotSize)
            .overlay(
                Circle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: dotSize * 0.45, height: dotSize * 0.45)
                    .offset(x: -dotSize * 0.12, y: -dotSize * 0.12)
            )
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.55), lineWidth: 1.5)
            )
            .shadow(color: state.chissColor.opacity(0.70), radius: 3)
    }
}

// MARK: - Fallback Pixel Avatar
//
// Procedurally generated 8×8 pixel grid for agents without a character sprite.
// Pattern is deterministic from the agent ID — same agent always looks the same.

private struct FallbackPixelAvatar: View {
    let agentId: String
    let size: CGFloat

    private var grid: [[Bool]] {
        let seed = agentId.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        var rng = seed
        var result = [[Bool]](repeating: [Bool](repeating: false, count: 8), count: 8)
        for row in 0..<8 {
            for col in 0..<4 {
                rng = (rng &* 1664525 &+ 1013904223) & 0x7fffffff
                let on = (rng % 3) != 0
                result[row][col] = on
                result[row][7 - col] = on
            }
        }
        result[3][3] = true; result[3][4] = true
        result[4][3] = true; result[4][4] = true
        return result
    }

    private var baseColor: Color {
        let seed = agentId.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xff }
        let hue = Double(seed) / 255.0
        return Color(hue: hue, saturation: 0.65, brightness: 0.85)
    }

    var body: some View {
        Canvas { ctx, size in
            let cellW = size.width / 8
            let cellH = size.height / 8
            for (r, row) in grid.enumerated() {
                for (c, on) in row.enumerated() {
                    let rect = CGRect(x: CGFloat(c) * cellW, y: CGFloat(r) * cellH, width: cellW, height: cellH)
                    ctx.fill(Path(rect), with: .color(on ? baseColor : Color.black.opacity(0.6)))
                }
            }
        }
        .frame(width: size, height: size)
    }
}
