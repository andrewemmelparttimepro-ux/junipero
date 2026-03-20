import SwiftUI

// MARK: - Junipero v2 — Monochrome Luxury
// Black + brushed silver/white. No gold. No copper.

enum JuniperoTheme {

    // MARK: — Backgrounds
    static let backgroundPrimary = Color(red: 0.05, green: 0.05, blue: 0.06)       // Near-black
    static let backgroundSecondary = Color(red: 0.09, green: 0.09, blue: 0.10)     // Dark charcoal
    static let backgroundSurface = Color(red: 0.13, green: 0.13, blue: 0.14)       // Card surface
    static let backgroundElevated = Color(red: 0.16, green: 0.16, blue: 0.17)      // Elevated surface

    // MARK: — Accent (Silver / White Steel)
    static let accent = Color(red: 0.78, green: 0.80, blue: 0.82)                  // Brushed silver
    static let accentLight = Color(red: 0.90, green: 0.91, blue: 0.93)             // Bright silver
    static let accentDark = Color(red: 0.50, green: 0.52, blue: 0.54)              // Muted steel
    static let accentGlow = Color.white.opacity(0.15)                               // Subtle glow
    static let accentSubtle = Color.white.opacity(0.06)                             // Barely there

    // MARK: — Text
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.32)

    // MARK: — Status
    static let statusOnline = Color(red: 0.30, green: 0.85, blue: 0.45)
    static let statusWarning = Color(red: 0.95, green: 0.70, blue: 0.20)
    static let statusError = Color(red: 0.85, green: 0.25, blue: 0.20)
    static let statusThinking = Color.white.opacity(0.60)

    // MARK: — Gradients
    static let backgroundGradient = LinearGradient(
        colors: [backgroundPrimary, backgroundSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let headerGradient = LinearGradient(
        colors: [
            Color(red: 0.10, green: 0.10, blue: 0.11),
            Color(red: 0.07, green: 0.07, blue: 0.08),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let accentGradient = LinearGradient(
        colors: [accentLight, accent, accentDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let surfaceGradient = LinearGradient(
        colors: [backgroundSurface, backgroundSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: — User / Assistant Bubble
    static let userBubble = Color(red: 0.14, green: 0.14, blue: 0.16)
    static let assistantBubble = Color(red: 0.10, green: 0.10, blue: 0.11)

    // MARK: — Divider
    static let divider = Color.white.opacity(0.06)

    // MARK: — Legacy aliases (keeps existing code compiling during migration)
    static let copper = accent
    static let copperLight = accentLight
    static let copperDark = accentDark
    static let copperGlow = accentGlow
    static let copperSubtle = accentSubtle
    static let roseGold = accentLight
    static let textCopper = accentLight
    static let copperGradient = accentGradient
    static let tabInactive = Color.white.opacity(0.40)
    static let tabActive = accent
}
