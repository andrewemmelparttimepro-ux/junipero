import SwiftUI

// MARK: - Agent Pixel Avatar
//
// Hand-crafted 12×12 pixel-art portraits — CryptoPunk-style homages to each
// agent's Star Wars namesake. Offline-first, fully deterministic, no network
// required. Unknown agents fall back to a procedural pattern.
//
// Grid encoding: '.' = transparent background, all other chars look up a
// per-character color palette.

// MARK: - Sprite Data

private struct CharacterSprite {
    let rows: [String]             // exactly 12 characters per row, 12 rows
    let palette: [Character: Color]
    let background: Color
}

// MARK: - Character Library

private enum CharacterSpriteLibrary {

    // ── THRAWN ───────────────────────────────────────────────────────────────
    // Grand Admiral Thrawn. Blue Chiss skin, glowing red eyes, black angular
    // hair, Imperial gray uniform, white collar pip.
    static let thrawn = CharacterSprite(
        rows: [
            "....KKKK....",   // black angular hair
            "...KBBBBBK..",   // hair framing blue face
            "..KBBBBBBK..",   // Chiss blue face
            "..KBRBBRBK..",   // face — red Imperial eyes
            "..KBBBBBBK..",   // lower face
            "...KBBBBK...",   // chin
            "....WWWW....",   // white collar
            "...GGGGGG...",   // Imperial gray uniform
            "..GGGGGGGG..",   // uniform
            ".GGGGGGGGGG.",   // uniform
            "GGGGGGGGGGGG",   // uniform base
            "GGGGGGGGGGGG",   // uniform base
        ],
        palette: [
            "K": Color(red: 0.07, green: 0.09, blue: 0.11),   // near-black
            "B": Color(red: 0.11, green: 0.31, blue: 0.85),   // Chiss blue
            "R": Color(red: 0.93, green: 0.15, blue: 0.15),   // glowing red eyes
            "W": Color(red: 0.96, green: 0.97, blue: 0.98),   // white collar
            "G": Color(red: 0.24, green: 0.30, blue: 0.38),   // Imperial gray
        ],
        background: Color(red: 0.05, green: 0.08, blue: 0.16)
    )

    // ── R2-D2 ────────────────────────────────────────────────────────────────
    // Astromech droid. White dome with blue panel decorations, matching body,
    // stubby outer legs.
    static let r2d2 = CharacterSprite(
        rows: [
            "....WWWW....",   // dome top
            "..WBWWWWBW..",   // dome — blue panel hints
            "..BBWWWWBB..",   // blue panel band
            "..WWWWWWWW..",   // dome lower
            ".WWWWWWWWWW.",   // body top
            ".WBBWWWWBBW.",   // body — blue panels
            ".WWWWWWWWWW.",   // body middle
            ".WBBWBBWBBW.",   // body — blue detail grid
            "..WWWWWWWW..",   // body bottom
            "..WWWWWWWW..",   // leg area
            "..WW....WW..",   // outer legs
            "..WW....WW..",   // feet
        ],
        palette: [
            "W": Color(red: 0.90, green: 0.92, blue: 0.94),   // white/silver
            "B": Color(red: 0.14, green: 0.39, blue: 0.92),   // R2 blue
        ],
        background: Color(red: 0.06, green: 0.07, blue: 0.10)
    )

    // ── C-3PO ────────────────────────────────────────────────────────────────
    // Protocol droid. All-gold plating, round head, dark eye sockets,
    // humanoid silhouette.
    static let c3po = CharacterSprite(
        rows: [
            "....gggg....",   // gold head top
            "..gggggggg..",   // head
            "..ggKggKgg..",   // face — dark eye sockets
            "..ggKggKgg..",   // eye sockets continued
            "..gggggggg..",   // lower face
            "....gggg....",   // chin / neck
            "..gggggggg..",   // chest
            ".gggggggggg.",   // torso
            ".gggggggggg.",   // torso
            "..gg....gg..",   // waist gap
            "..gg....gg..",   // legs
            "..gg....gg..",   // feet
        ],
        palette: [
            "g": Color(red: 0.85, green: 0.58, blue: 0.10),   // warm amber gold
            "K": Color(red: 0.07, green: 0.06, blue: 0.04),   // dark eye sockets
        ],
        background: Color(red: 0.08, green: 0.06, blue: 0.02)
    )

    // ── QUI-GON JINN ─────────────────────────────────────────────────────────
    // Jedi Master. Long dark hair, tan skin, medium-brown beard, earthy brown
    // Jedi robes.
    static let quigon = CharacterSprite(
        rows: [
            "..nnnnnnnn..",   // long dark brown hair
            ".nTTTTTTTTn.",   // hair framing tan face
            ".nTTTTTTTTn.",   // tan face
            ".nTTwTTwTTn.",   // face — dark eyes
            ".nTTTTTTTTn.",   // lower face
            "..bbTTTTbb..",   // beard edges (medium brown)
            "..bbbbbbbb..",   // beard
            "...tttttt...",   // Jedi robes
            "..tttttttt..",   // robes
            ".tttttttttt.",   // robes wide
            "tttttttttttt",   // robes base
            "tttttttttttt",   // robes base
        ],
        palette: [
            "n": Color(red: 0.20, green: 0.14, blue: 0.09),   // dark brown hair
            "T": Color(red: 0.84, green: 0.70, blue: 0.54),   // tan/warm skin
            "w": Color(red: 0.10, green: 0.08, blue: 0.06),   // dark eyes
            "b": Color(red: 0.45, green: 0.31, blue: 0.18),   // medium brown beard
            "t": Color(red: 0.36, green: 0.22, blue: 0.08),   // Jedi brown robes
        ],
        background: Color(red: 0.04, green: 0.08, blue: 0.05)
    )

    // ── LANDO CALRISSIAN ─────────────────────────────────────────────────────
    // Smuggler-Baron Administrator. Warm dark skin, bold purple cape,
    // gold/yellow shirt underneath. Confidence personified.
    static let lando = CharacterSprite(
        rows: [
            "....KKKK....",   // stylish black hair
            "...KDDDDDK..",   // hair framing dark face
            "..KDDDDDDDK.",   // warm dark face
            "..KDwDDwDDK.",   // face — dark eyes
            "..KDDDDDDDK.",   // lower face / smile
            "...KDDDDDK..",   // chin
            "...cccccccc.",   // purple cape begins
            ".ccccYYYccc.",   // cape + gold shirt
            ".ccYYYYYYcc.",   // shirt visible
            ".ccYYYYYYcc.",   // shirt
            "ccccYYYccccc",   // cape flowing wide
            "cccccccccccc",   // cape base
        ],
        palette: [
            "K": Color(red: 0.07, green: 0.07, blue: 0.09),   // black hair
            "D": Color(red: 0.38, green: 0.22, blue: 0.14),   // warm dark skin
            "w": Color(red: 0.07, green: 0.07, blue: 0.09),   // eyes
            "c": Color(red: 0.44, green: 0.18, blue: 0.86),   // vivid purple cape
            "Y": Color(red: 0.97, green: 0.82, blue: 0.22),   // gold shirt
        ],
        background: Color(red: 0.06, green: 0.04, blue: 0.12)
    )

    // ── BOBA FETT ────────────────────────────────────────────────────────────
    // Mandalorian bounty hunter. Beskar green armor, black T-visor (the
    // signature horizontal slit), dark red trim, jetpack orange detail.
    static let boba = CharacterSprite(
        rows: [
            "....EEEE....",   // green helmet top
            "...EEEEEEEE.",   // helmet
            "..EEEEEEEEEE",   // helmet wide
            "..EKKKKKKKKE",   // ████ T-visor ████ — the iconic Mandalorian slit
            "..EEEEEEEEEE",   // lower helmet
            "...EEEEEEEE.",   // chin guard
            "..EErrrrrrEE",   // body armor — dark red trim
            "..EErrEErrEE",   // armor detail
            "..EEEEEEEEEo",   // lower armor — jetpack flare (orange)
            "...EEEEEEEE.",   // lower body
            "....EE..EE..",   // legs
            "....EE..EE..",   // boots
        ],
        palette: [
            "E": Color(red: 0.04, green: 0.56, blue: 0.38),   // Mandalorian green
            "K": Color(red: 0.05, green: 0.06, blue: 0.07),   // visor black
            "r": Color(red: 0.50, green: 0.09, blue: 0.09),   // dark red trim
            "o": Color(red: 0.92, green: 0.45, blue: 0.08),   // jetpack orange
        ],
        background: Color(red: 0.04, green: 0.07, blue: 0.05)
    )

    // ── BART SIMPSON ─────────────────────────────────────────────────────────
    // V2 agent. Brilliant punk kid. Three iconic hair spikes, vivid yellow
    // skin, trademark smirk, red polo shirt, blue shorts. Don't have a cow.
    static let bart = CharacterSprite(
        rows: [
            ".K..K..K....",   // three spiky hair tips
            "KKKKKKKK....",   // hair base
            ".KYYYYYYY...",   // hair edge + yellow face
            ".KYwYYYwYK..",   // face — beady eyes
            ".KYYYYYYYK..",   // face
            ".KYYmYYYYK..",   // smirk — Bart's trademark
            "..KYYYYYK...",   // chin
            "...RRRRRR...",   // red polo shirt
            "..RRRRRRRR..",   // shirt
            "..RRRRRRRR..",   // shirt
            "..BBBBBBBB..",   // blue shorts
            "..BB....BB..",   // legs
        ],
        palette: [
            "K": Color(red: 0.07, green: 0.07, blue: 0.09),   // black hair
            "Y": Color(red: 0.99, green: 0.87, blue: 0.15),   // Bart yellow
            "w": Color(red: 0.07, green: 0.07, blue: 0.09),   // eyes
            "m": Color(red: 0.88, green: 0.18, blue: 0.18),   // red mouth/smirk
            "R": Color(red: 0.80, green: 0.10, blue: 0.10),   // red shirt
            "B": Color(red: 0.18, green: 0.42, blue: 0.88),   // blue shorts
        ],
        background: Color(red: 0.08, green: 0.10, blue: 0.18)
    )

    // ── HUNTER ─────────────────────────────────────────────────────────────
    // OSINT tracker. Sharp-featured, dark ponytail, olive/black tactical
    // vest, utility collar. Eyes locked on target.
    static let hunter = CharacterSprite(
        rows: [
            "....KKKK....",   // dark hair pulled back
            "...KTTTTK...",   // hair framing face
            "..KTTTTTTK..",   // tanned face
            "..KTwTTwTK..",   // face — sharp dark eyes
            "..KTTTTTTK..",   // lower face
            "...KTTTTK...",   // jaw
            "...GGGGGG...",   // tactical collar
            "..OGOOOOGO..",   // olive vest + dark gear straps
            "..OOOOOOOO..",   // vest
            ".OOOOOOOOOO.",   // vest wide
            "OOOOOOOOOOOO",   // vest base
            "OOOOOOOOOOOO",   // base
        ],
        palette: [
            "K": Color(red: 0.07, green: 0.07, blue: 0.09),   // black hair
            "T": Color(red: 0.72, green: 0.56, blue: 0.42),   // tanned skin
            "w": Color(red: 0.07, green: 0.07, blue: 0.09),   // dark eyes
            "G": Color(red: 0.22, green: 0.22, blue: 0.24),   // dark gear collar
            "O": Color(red: 0.28, green: 0.32, blue: 0.18),   // olive drab tactical
        ],
        background: Color(red: 0.05, green: 0.06, blue: 0.04)
    )

    // ── AL BORLAND ───────────────────────────────────────────────────────
    // Life Ops. Pure red and black buffalo plaid — the flannel shirt as avatar.
    // No face, no features. Just the shirt. That's the whole personality.
    static let alborland = CharacterSprite(
        rows: [
            "RRKKRRKKRRKK",   // buffalo plaid row 1
            "RRKKRRKKRRKK",   // buffalo plaid row 2
            "KKDDKKDDKKDD",   // plaid cross-hatch (dark red overlap)
            "KKDDKKDDKKDD",   // cross-hatch row 2
            "RRKKRRKKRRKK",   // plaid row 3
            "RRKKRRKKRRKK",   // plaid row 4
            "KKDDKKDDKKDD",   // cross-hatch row 3
            "KKDDKKDDKKDD",   // cross-hatch row 4
            "RRKKRRKKRRKK",   // plaid row 5
            "RRKKRRKKRRKK",   // plaid row 6
            "KKDDKKDDKKDD",   // cross-hatch row 5
            "KKDDKKDDKKDD",   // cross-hatch row 6
        ],
        palette: [
            "R": Color(red: 0.78, green: 0.10, blue: 0.10),   // flannel red
            "K": Color(red: 0.08, green: 0.08, blue: 0.08),   // black
            "D": Color(red: 0.38, green: 0.06, blue: 0.06),   // dark red overlap
        ],
        background: Color(red: 0.06, green: 0.04, blue: 0.04)
    )

    static func sprite(for agentId: String) -> CharacterSprite? {
        switch agentId.lowercased() {
        case "thrawn":                          return thrawn
        case "r2d2", "r2-d2":                  return r2d2
        case "c3po", "c-3po":                  return c3po
        case "quigon", "qui-gon":              return quigon
        case "lando":                           return lando
        case "boba", "bobafett":               return boba
        case "bart":                            return bart
        case "hunter":                          return hunter
        case "alborland", "al borland", "al":  return alborland
        default:                                return nil
        }
    }
}

// MARK: - Sprite Renderer

private struct SpritePixelAvatar: View {
    let sprite: CharacterSprite
    let size: CGFloat

    var body: some View {
        Canvas { ctx, canvasSize in
            let cols = 12
            let rowCount = sprite.rows.count
            let cellW = canvasSize.width / CGFloat(cols)
            let cellH = canvasSize.height / CGFloat(rowCount)

            // Background
            ctx.fill(
                Path(CGRect(origin: .zero, size: canvasSize)),
                with: .color(sprite.background)
            )

            // Pixel grid — transparent pixels ('.' or unmapped) are skipped
            for (rowIdx, rowStr) in sprite.rows.enumerated() {
                for (colIdx, char) in rowStr.enumerated() {
                    guard char != ".", let color = sprite.palette[char] else { continue }
                    let rect = CGRect(
                        x: CGFloat(colIdx) * cellW,
                        y: CGFloat(rowIdx) * cellH,
                        width: cellW,
                        height: cellH
                    )
                    ctx.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: size, height: size)
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
        if let sprite = CharacterSpriteLibrary.sprite(for: agentId) {
            SpritePixelAvatar(sprite: sprite, size: size)
        } else {
            FallbackPixelAvatar(agentId: agentId, size: size)
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
