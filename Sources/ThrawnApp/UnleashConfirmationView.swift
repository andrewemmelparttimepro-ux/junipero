import SwiftUI

// MARK: - Unleash Confirmation Dialog
//
// Dramatic, full-screen confirmation sheet that appears when the user
// toggles from restricted → unleashed mode.
// Uses Sith-red visual treatment from the existing Chiss palette.

struct UnleashConfirmationView: View {
    @EnvironmentObject var execution: ExecutionService

    @State private var pulseActive = false
    @State private var iconScale: CGFloat = 0.8
    @State private var showContent = false
    @State private var hoverUnleash = false
    @State private var hoverStaySafe = false

    var body: some View {
        ZStack {
            // Sith-red backdrop
            Color.obsidian
                .ignoresSafeArea()

            // Dramatic radial glow
            RadialGradient(
                colors: [
                    Color.sithRed.opacity(0.35),
                    Color.sithGlow.opacity(0.12),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 400
            )
            .ignoresSafeArea()

            // Subtle grain
            ObsidianGrainTexture()
                .blendMode(.screen)
                .opacity(0.02)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Pulsing icon
                ZStack {
                    // Outer pulse ring
                    Circle()
                        .stroke(Color.sithGlow.opacity(0.35), lineWidth: 2)
                        .frame(width: 90, height: 90)
                        .scaleEffect(pulseActive ? 2.0 : 1.0)
                        .opacity(pulseActive ? 0 : 0.6)

                    // Mid pulse
                    Circle()
                        .stroke(Color.sithRed.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 90, height: 90)
                        .scaleEffect(pulseActive ? 1.5 : 1.0)
                        .opacity(pulseActive ? 0 : 0.4)

                    // Icon core
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.sithGlow.opacity(0.5),
                                        Color.sithRed.opacity(0.3),
                                        Color.obsidian
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 50
                                )
                            )
                            .frame(width: 80, height: 80)

                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.sithGlow, Color(red: 1.0, green: 0.45, blue: 0.15)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: Color.sithGlow.opacity(0.6), radius: 12)
                    }
                    .scaleEffect(iconScale)
                }
                .padding(.bottom, 32)

                // Header
                Text("FULL ACCESS MODE")
                    .font(.system(size: 20, weight: .black, design: .default))
                    .tracking(4.0)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.sithGlow, Color(red: 1.0, green: 0.5, blue: 0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 10)
                    .padding(.bottom, 18)

                // Body text
                VStack(spacing: 14) {
                    Text("You're about to unleash the full power of OpenClaw.")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                        .multilineTextAlignment(.center)

                    Text("THRAWN and all agents will have unrestricted access to your computer — shell commands, file system, network, and system processes.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .frame(maxWidth: 460)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 8)
                .padding(.bottom, 28)

                // Capability list
                VStack(alignment: .leading, spacing: 10) {
                    capabilityRow(icon: "bolt.fill", text: "Shell command execution", color: Color(red: 1.0, green: 0.6, blue: 0.1))
                    capabilityRow(icon: "folder.fill", text: "File system read / write", color: Color(red: 0.95, green: 0.45, blue: 0.15))
                    capabilityRow(icon: "globe", text: "Network requests & API calls", color: Color(red: 0.9, green: 0.35, blue: 0.2))
                    capabilityRow(icon: "gearshape.2.fill", text: "Process spawning & management", color: Color.sithGlow)
                    capabilityRow(icon: "wrench.and.screwdriver.fill", text: "System configuration access", color: Color.sithRed)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.sithRed.opacity(0.18), lineWidth: 1)
                        )
                )
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 6)
                .padding(.bottom, 36)

                // Action buttons
                HStack(spacing: 16) {
                    // Stay Safe button
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            execution.showUnleashConfirmation = false
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 13))
                            Text("Stay Safe")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(hoverStaySafe ? 0.08 : 0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                        )
                        .scaleEffect(hoverStaySafe ? 1.03 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.15)) { hoverStaySafe = hovering }
                    }

                    // Unleash button
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            execution.confirmUnleash()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.shield.fill")
                                .font(.system(size: 13))
                            Text("Unleash THRAWN")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.sithGlow.opacity(hoverUnleash ? 0.8 : 0.6),
                                            Color(red: 0.85, green: 0.3, blue: 0.05).opacity(hoverUnleash ? 0.7 : 0.5)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.sithGlow.opacity(0.4), lineWidth: 1)
                                )
                        )
                        .shadow(color: Color.sithGlow.opacity(hoverUnleash ? 0.5 : 0.25), radius: hoverUnleash ? 16 : 8)
                        .scaleEffect(hoverUnleash ? 1.05 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.15)) { hoverUnleash = hovering }
                    }
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 4)

                Spacer()
            }
            .padding(48)
        }
        .frame(minWidth: 560, minHeight: 520)
        .onAppear {
            // Entrance animations
            withAnimation(.easeOut(duration: 0.6)) {
                iconScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                showContent = true
            }
            withAnimation(
                .easeOut(duration: 2.0)
                .repeatForever(autoreverses: false)
                .delay(0.4)
            ) {
                pulseActive = true
            }
        }
    }

    private func capabilityRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(color)
                .frame(width: 20)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
        }
    }
}
