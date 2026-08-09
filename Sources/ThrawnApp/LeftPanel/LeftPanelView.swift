import SwiftUI

struct LeftPanelView: View {
    @EnvironmentObject var execution: ExecutionService
    @EnvironmentObject var bootstrap: ThrawnBootstrap
    @EnvironmentObject var ollama: OllamaClient

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 12) {
                // Provider status — always visible, sign-in CTA when not connected
                ProviderStatusCard()
                    .frame(width: 310)

                AgentRailView()
                    .frame(width: 310)
                    .frame(maxHeight: .infinity)

                // Operation mode is full by default; model selection remains here.
            }
            .frame(maxHeight: .infinity)

            // The analog clock is a permanent fixture. It sizes to the room
            // it actually has (up to its full 340pt) instead of clipping at
            // every supported window width.
            GeometryReader { geo in
                let side = max(180, min(340, min(geo.size.width, geo.size.height - 24)))
                VStack(spacing: 0) {
                    Spacer(minLength: 12)
                    AnalogClockView()
                        .frame(width: side, height: side)
                        .frame(maxWidth: .infinity)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }
}

// MARK: - Provider Status Card

struct ProviderStatusCard: View {
    @EnvironmentObject var ollama: OllamaClient
    @EnvironmentObject var openai: OpenAIClient
    @EnvironmentObject var openclaw: GatewayWSClient
    @EnvironmentObject var agentRuntime: AgentRuntimeCoordinator
    @EnvironmentObject var bootstrap: ThrawnBootstrap
    @EnvironmentObject var devOpsBrain: DevOpsBrainStore
    @EnvironmentObject var specStore: AgentSpecStore
    @State private var hovered = false
    @State private var glowPulse: CGFloat = 0.6

    private var isConnected: Bool {
        selectedStatus.state == .ready
    }

    private var selectedBackend: ProviderBackend {
        specStore.subscriptionGateway(forAgentId: "thrawn")
    }

    private var selectedStatus: ProviderStatus {
        agentRuntime.status(for: selectedBackend, agentID: "thrawn")
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

                        Text("THRAWN")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1)
                            .foregroundColor(Color.chissPrimary)
                    }

                    Text(statusSubtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer()

                // Refresh models
                Button {
                    Task {
                        await agentRuntime.refresh(
                            agentID: "thrawn",
                            backend: selectedBackend
                        )
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.chissPrimary.opacity(0.5))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Refresh model list")
            }

            HStack(spacing: 8) {
                AgentGatewayPicker(agentID: "thrawn", style: .rail)

                if selectedBackend == .codex {
                    // The model stays a sub-selection of the OpenAI brain.
                    Menu {
                        ForEach(agentRuntime.codexModels) { model in
                            Button {
                                agentRuntime.selectedCodexModelID = model.id
                                agentRuntime.selectedReasoningEffort = model.defaultReasoningEffort
                            } label: {
                                HStack {
                                    Text(model.displayName)
                                    if agentRuntime.selectedModel?.id == model.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "cpu")
                                .font(.system(size: 10, weight: .bold))
                            Text(agentRuntime.selectedModel?.displayName ?? "Live model")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(Color.chissPrimary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
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
                Spacer(minLength: 0)
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

    private var statusSubtitle: String {
        if selectedStatus.state == .ready {
            return selectedStatus.account?.displayName ?? selectedBackend.gatewayDisplayName
        }
        if selectedStatus.state == .starting {
            return "Checking \(selectedBackend.gatewayDisplayName)"
        }
        return selectedStatus.detail
    }

    // MARK: - Disconnected State (Big CTA)

    private var disconnectedView: some View {
        Button {
            // The most prominent signed-out surface in the app must actually
            // sign the user in — a bare status refresh strands them offline.
            Task {
                do {
                    try await agentRuntime.beginSignIn(
                        agentID: "thrawn",
                        backend: selectedBackend
                    )
                } catch {
                    await agentRuntime.refresh(
                        agentID: "thrawn",
                        backend: selectedBackend
                    )
                }
            }
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
                    Text("THRAWN BRAIN OFFLINE")
                        .font(.system(size: 11, weight: .black))
                        .tracking(2)
                        .foregroundColor(Color.chissPrimary)

                    Text(selectedStatus.detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.50))
                        .lineLimit(2)
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
