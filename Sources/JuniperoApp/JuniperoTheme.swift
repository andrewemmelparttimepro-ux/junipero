import SwiftUI

// MARK: - Junipero v2 Dark Luxury Color Palette
// Black + copper, high-end watch aesthetic

enum JuniperoTheme {

    // MARK: — Backgrounds
    static let backgroundPrimary = Color(red: 0.05, green: 0.05, blue: 0.06)       // Near-black
    static let backgroundSecondary = Color(red: 0.09, green: 0.09, blue: 0.10)     // Dark charcoal
    static let backgroundSurface = Color(red: 0.13, green: 0.13, blue: 0.14)       // Card surface
    static let backgroundElevated = Color(red: 0.16, green: 0.16, blue: 0.17)      // Elevated surface

    // MARK: — Copper Accent Palette
    static let copper = Color(red: 0.72, green: 0.45, blue: 0.20)                  // Primary copper #B87333
    static let copperLight = Color(red: 0.83, green: 0.59, blue: 0.42)             // Lighter copper
    static let copperDark = Color(red: 0.55, green: 0.35, blue: 0.17)              // Darker copper
    static let copperGlow = Color(red: 0.72, green: 0.45, blue: 0.20).opacity(0.3) // Glow/shadow
    static let copperSubtle = Color(red: 0.72, green: 0.45, blue: 0.20).opacity(0.12) // Very subtle copper tint
    static let roseGold = Color(red: 0.88, green: 0.68, blue: 0.55)                // Rose gold highlight

    // MARK: — Text
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.60)
    static let textTertiary = Color.white.opacity(0.38)
    static let textCopper = Color(red: 0.83, green: 0.59, blue: 0.42)

    // MARK: — Status
    static let statusOnline = Color(red: 0.30, green: 0.85, blue: 0.45)
    static let statusWarning = Color(red: 0.95, green: 0.70, blue: 0.20)
    static let statusError = Color(red: 0.85, green: 0.25, blue: 0.20)
    static let statusThinking = Color(red: 0.72, green: 0.45, blue: 0.20)

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

    static let copperGradient = LinearGradient(
        colors: [copperLight, copper, copperDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let surfaceGradient = LinearGradient(
        colors: [backgroundSurface, backgroundSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: — User / Assistant Bubble
    static let userBubble = Color(red: 0.18, green: 0.15, blue: 0.12)              // Warm dark
    static let assistantBubble = Color(red: 0.13, green: 0.13, blue: 0.14)         // Cool dark

    // MARK: — Divider
    static let divider = Color.white.opacity(0.08)

    // MARK: — Tab bar
    static let tabInactive = Color.white.opacity(0.45)
    static let tabActive = copper
}
