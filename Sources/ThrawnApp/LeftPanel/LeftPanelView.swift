import SwiftUI

struct LeftPanelView: View {
    @EnvironmentObject var execution: ExecutionService
    @EnvironmentObject var bootstrap: ThrawnBootstrap
    @EnvironmentObject var ollama: OllamaClient

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 12) {
                // Provider status — always visible, sign-in CTA when not connected
                ProviderStatusCard()
                    .frame(width: 310)

                AgentRailView()
                    .frame(width: 310)

                // Unleashed toggle moved into the agent rail's dropdown menu
                // (hidden by default — "unleashed is just standard now")
            }

            VStack(spacing: 0) {
                Spacer(minLength: 12)

                AnalogClockView()
                    .frame(width: 340, height: 340)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }
}

// MARK: - Provider Status Card

struct ProviderStatusCard: View {
    @EnvironmentObject var ollama: OllamaClient
    @EnvironmentObject var bootstrap: ThrawnBootstrap
    @State private var hovered = false
    @State private var glowPulse: CGFloat = 0.6

    private var isConnected: Bool {
        ollama.connected
    }

    var body: some View {
        if isConnected {
            connectedView
        } else {
            disconnectedView
        }
    }

    // MARK: - Connected State

    private var connectedView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Ollama icon with pulse
                ZStack {
                    Circle()
                        .fill(Color(red: 0.3, green: 0.85, blue: 0.55).opacity(0.15))
                        .frame(width: 36, height: 36)
                        .shadow(color: Color(red: 0.3, green: 0.85, blue: 0.55).opacity(0.3 * glowPulse), radius: 8)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(red: 0.3, green: 0.85, blue: 0.55))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("CONNECTED")
                            .font(.system(size: 10, weight: .black))
                            .tracking(2)
                            .foregroundColor(Color(red: 0.3, green: 0.85, blue: 0.55))

                        Text("·")
                            .foregroundColor(.white.opacity(0.25))

                        Text("OLLAMA")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1)
                            .foregroundColor(Color.chissPrimary)
                    }

                    Text("\(ollama.models.count) models available")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer()

                // Refresh models
                Button {
                    Task { await ollama.fetchModels() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.chissPrimary.opacity(0.5))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Refresh model list")
            }

            // Model dropdown
            if !ollama.models.isEmpty {
                Menu {
                    ForEach(ollama.models, id: \.self) { model in
                        Button {
                            ollama.selectModel(model)
                        } label: {
                            HStack {
                                Text(model)
                                if model == ollama.selectedModel {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10, weight: .bold))
                        Text(ollama.selectedModel)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(Color.chissPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.chissPrimary.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.chissPrimary.opacity(0.18), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.3, green: 0.85, blue: 0.55).opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(red: 0.3, green: 0.85, blue: 0.55).opacity(0.15), lineWidth: 1)
                )
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                glowPulse = 1.0
            }
        }
    }

    // MARK: - Disconnected State (Big CTA)

    private var disconnectedView: some View {
        Button {
            ollama.connect()
        } label: {
            VStack(spacing: 14) {
                // Large icon with animated pulse
                ZStack {
                    // Outer pulse ring
                    Circle()
                        .stroke(Color.chissPrimary.opacity(0.15 * glowPulse), lineWidth: 1.5)
                        .frame(width: 56, height: 56)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.chissPrimary.opacity(0.25 * glowPulse),
                                    Color.chissPrimary.opacity(0.05)
                                ],
                                center: .center,
                                startRadius: 2,
                                endRadius: 24
                            )
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Color.chissPrimary)
                        .shadow(color: Color.chissPrimary.opacity(0.5), radius: 8)
                }

                VStack(spacing: 4) {
                    Text("OLLAMA NOT RUNNING")
                        .font(.system(size: 11, weight: .black))
                        .tracking(2)
                        .foregroundColor(Color.chissPrimary)

                    Text("Start Ollama on localhost:11434")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.50))
                }

                // Retry button
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .bold))
                    Text("Retry Connection")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .foregroundColor(Color.chissPrimary.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.chissPrimary.opacity(0.08))
                        .overlay(
                            Capsule()
                                .stroke(Color.chissPrimary.opacity(0.20), lineWidth: 0.5)
                        )
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.chissPrimary.opacity(hovered ? 0.06 : 0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.chissPrimary.opacity(hovered ? 0.35 : 0.18),
                                        Color.chissPrimary.opacity(hovered ? 0.15 : 0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: Color.chissPrimary.opacity(hovered ? 0.15 : 0.05), radius: hovered ? 12 : 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { hovered = hovering }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowPulse = 1.0
            }
        }
    }
}

// MARK: - Safety Toggle Card

struct SafetyToggleView: View {
    @EnvironmentObject var execution: ExecutionService
    @State private var hovered = false
    @State private var pulseActive = false

    private var isUnleashed: Bool { execution.accessMode.isUnleashed }

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.28)) {
                execution.toggleAccess()
            }
        }) {
            HStack(spacing: 12) {
                // Icon with state-based treatment
                ZStack {
                    Circle()
                        .fill(isUnleashed ? Color.sithRed.opacity(0.15) : Color.chissPrimary.opacity(0.08))
                        .frame(width: 32, height: 32)

                    Image(systemName: execution.accessMode.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isUnleashed ? Color.sithGlow : Color.chissPrimary.opacity(0.7))
                        .shadow(color: isUnleashed ? Color.sithGlow.opacity(0.5) : .clear, radius: 6)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(isUnleashed ? "UNLEASHED" : "RESTRICTED")
                            .font(.system(size: 11, weight: .black))
                            .tracking(2.0)
                            .foregroundColor(isUnleashed ? Color.sithGlow : Color.chissPrimary.opacity(0.75))

                        if isUnleashed {
                            Text("⚡")
                                .font(.system(size: 10))
                        }
                    }

                    Text(isUnleashed ? "Full computer access active" : "Computer access disabled")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                }

                Spacer()

                // Toggle indicator
                ZStack {
                    Capsule()
                        .fill(isUnleashed ? Color.sithRed.opacity(0.35) : Color.white.opacity(0.08))
                        .frame(width: 36, height: 20)
                        .overlay(
                            Capsule()
                                .stroke(isUnleashed ? Color.sithGlow.opacity(0.3) : Color.white.opacity(0.12), lineWidth: 1)
                        )

                    Circle()
                        .fill(isUnleashed ? Color.sithGlow : Color.chissPrimary.opacity(0.5))
                        .frame(width: 14, height: 14)
                        .shadow(color: isUnleashed ? Color.sithGlow.opacity(0.6) : .clear, radius: 4)
                        .offset(x: isUnleashed ? 8 : -8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isUnleashed
                        ? Color.sithRed.opacity(hovered ? 0.08 : 0.04)
                        : Color.white.opacity(hovered ? 0.05 : 0.025)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                isUnleashed
                                    ? Color.sithGlow.opacity(hovered ? 0.4 : 0.2)
                                    : Color.chissPrimary.opacity(hovered ? 0.25 : 0.12),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: isUnleashed ? Color.sithGlow.opacity(0.15) : .clear, radius: hovered ? 12 : 6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { hovered = hovering }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isUnleashed)
    }
}
