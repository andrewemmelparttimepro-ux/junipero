import SwiftUI
import UniformTypeIdentifiers

// MARK: - Core Definition
// V2 starts clean: Thrawn is core command, every other durable role is added
// deliberately and treated as a v2 operational agent.
let coreAgentIds: Set<String> = ["thrawn"]

// MARK: - Agent Rail View

struct AgentRailView: View {
    @EnvironmentObject var roster: AgentRosterStore
    @EnvironmentObject var nav: ConsoleNavigationStore
    @EnvironmentObject var execution: ExecutionService
    @EnvironmentObject var voice: VoiceService
    @EnvironmentObject var specStore: AgentSpecStore
    @State private var isDropTargeted = false

    private var coreAgents: [AgentStatus] {
        roster.agents.filter { coreAgentIds.contains($0.id) }
    }

    private var v2Agents: [AgentStatus] {
        roster.agents.filter { !coreAgentIds.contains($0.id) }
    }

    /// Pinned agents that aren't already visible in the core/V2 lists
    private var extraPinnedAgents: [AgentStatus] {
        let visibleIds = Set(roster.agents.map(\.id))
        return nav.pinnedLeftPanelAgents.compactMap { pinnedId in
            guard !visibleIds.contains(pinnedId) else { return nil }
            return roster.agents.first(where: { $0.id == pinnedId })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Text("AGENTS")
                    .font(.system(size: 11, weight: .bold, design: .default))
                    .tracking(2.5)
                    .foregroundColor(Color.chissPrimary.opacity(0.90))
                Spacer()

                // Big mute toggle — primary "I'm on a Zoom call" button.
                // When unmuted: subtle speaker icon, low-emphasis.
                // When muted: solid red chip, IMMEDIATELY readable at a glance.
                MuteToggleButton(muted: voice.muted) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        voice.muted.toggle()
                    }
                }

                HStack(spacing: 4) {
                    Text("Solo")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.chissPrimary.opacity(0.55))
                    Text("V2")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1)
                        .foregroundColor(Color.ndaiGreen.opacity(0.85))
                }
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    // ── Core Squad ────────────────────────────────────────────
                    ForEach(coreAgents) { agent in
                        AgentRailCard(
                            agent: agent,
                            spec: specStore.specs.first(where: { $0.id == agent.id }),
                            isSelected: nav.selectedAgentId == agent.id,
                            isCore: true,
                            onTap: { selectAgent(agent) }
                        )
                    }

                    // ── V2 Divider ────────────────────────────────────────────
                    if !v2Agents.isEmpty {
                        HStack(spacing: 8) {
                            Rectangle()
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 1)
                            Text("V2")
                                .font(.system(size: 8, weight: .black))
                                .tracking(2.5)
                                .foregroundColor(Color(red: 0.98, green: 0.72, blue: 0.18).opacity(0.50))
                            Rectangle()
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 1)
                        }
                        .padding(.vertical, 4)

                        // ── V2 Agents ─────────────────────────────────────────
                        ForEach(v2Agents) { agent in
                            AgentRailCard(
                                agent: agent,
                                spec: specStore.specs.first(where: { $0.id == agent.id }),
                                isSelected: nav.selectedAgentId == agent.id,
                                isCore: false,
                                onTap: { selectAgent(agent) }
                            )
                        }
                    }

                    // ── Deployed Wing ─────────────────────────────────────────
                    // Field operators living inside NDAI's shipped apps. These
                    // are not Thrawn personas: @ARI reaches the actual agent
                    // the SPAS 360 floor uses, with his data and his memory.
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 1)
                        Text("DEPLOYED")
                            .font(.system(size: 8, weight: .black))
                            .tracking(2.5)
                            .foregroundColor(Color.ndaiGreen.opacity(0.55))
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 1)
                    }
                    .padding(.vertical, 4)

                    ForEach(DeployedAgentHub.shared.agents) { agent in
                        DeployedAgentRailRow(
                            agent: agent,
                            isSelected: nav.selectedAgentId == agent.id,
                            onTap: { selectDeployed(agent) }
                        )
                    }

                    // ── Extra Pinned Slots ────────────────────────────────────
                    // Drop zone: drag agents from the right-panel roster to pin
                    // additional agents here beyond the standard roster.
                    if !extraPinnedAgents.isEmpty {
                        HStack(spacing: 8) {
                            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                            Text("PINNED")
                                .font(.system(size: 8, weight: .black))
                                .tracking(2.5)
                                .foregroundColor(Color.chissPrimary.opacity(0.35))
                            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                        }
                        .padding(.vertical, 4)

                        ForEach(extraPinnedAgents) { agent in
                            AgentRailCard(
                                agent: agent,
                                spec: specStore.specs.first(where: { $0.id == agent.id }),
                                isSelected: nav.selectedAgentId == agent.id,
                                isCore: false,
                                onTap: { selectAgent(agent) },
                                onRemove: {
                                    withAnimation(.spring(response: 0.28)) {
                                        nav.unpinAgent(agent.id)
                                    }
                                }
                            )
                        }
                    }

                    // Empty drop slot when there's room for more pinned agents
                    if nav.pinnedLeftPanelAgents.count < 2 || extraPinnedAgents.count < 2 {
                        EmptyAgentSlot(isHighlighted: isDropTargeted)
                    }

                    // Bottom breathing room so the last card doesn't kiss the rail's edge
                    Color.clear.frame(height: 4)
                }
                .onDrop(of: [UTType.plainText], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.obsidianMid.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            isDropTargeted
                                ? Color.chissPrimary.opacity(0.45)
                                : Color.chissPrimary.opacity(0.14),
                            lineWidth: isDropTargeted ? 1.5 : 1
                        )
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { string, _ in
            guard let agentId = string as? String else { return }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.28)) {
                    nav.pinAgent(agentId)
                }
            }
        }
        return true
    }

    private func selectAgent(_ agent: AgentStatus) {
        withAnimation(.spring(response: 0.28)) {
            if nav.selectedAgentId == agent.id {
                nav.dismissAgent()
            } else {
                nav.selectedAgentId = agent.id
            }
        }
    }

    private func selectDeployed(_ agent: DeployedAgentConfig) {
        withAnimation(.spring(response: 0.28)) {
            if nav.selectedAgentId == agent.id {
                nav.dismissAgent()
            } else {
                nav.selectedAgentId = agent.id
            }
        }
    }
}

// MARK: - Deployed Agent Row
//
// Same geometry as a V2 `AgentRailCard` (3pt stripe, 14pt corners, 40pt
// avatar, identical type sizes) so the rail reads as one column — the
// differences are informational: a green DEPLOYED accent, a presence line fed
// by the agent's live status card, and the app he lives in where the gateway
// picker would be. No gateway picker, because Thrawn does not choose a
// deployed agent's model — his own app does (until the control plane lands).

private struct DeployedAgentRailRow: View {
    let agent: DeployedAgentConfig
    let isSelected: Bool
    let onTap: () -> Void

    @ObservedObject private var hub = DeployedAgentHub.shared
    @State private var isHovering = false

    private var presence: DeployedAgentPresence { hub.presence(for: agent) }
    private var accentColor: Color { Color.ndaiGreen }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.obsidianMid.opacity(isSelected ? 0.98 : (isHovering ? 0.92 : 0.80)))

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(accentColor.opacity(isSelected ? 0.85 : 0.50))
                        .frame(width: 3)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? accentColor.opacity(0.55) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )

                HStack(alignment: .top, spacing: 10) {
                    AgentPixelAvatar(
                        agentId: agent.id,
                        agentName: agent.name,
                        state: presence.activityState,
                        size: 40
                    )
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(agent.name)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.92))
                                .lineLimit(1)
                            Text(presence.isUp ? "LIVE" : presence == .unknown ? "CHECKING" : "DOWN")
                                .font(.system(size: 8.5, weight: .heavy))
                                .tracking(1.6)
                                .foregroundColor(presence.activityState.chissColor.opacity(0.75))
                            Text(presence.detailLine)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.50))
                                .lineLimit(2)
                        }
                        Spacer(minLength: 4)
                        Text(agent.appName)
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(accentColor.opacity(0.85))
                            .frame(width: 96, alignment: .trailing)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
                .padding(.leading, 13)
                .padding(.trailing, 10)
                .padding(.vertical, 10)
            }
            .shadow(
                color: isSelected ? accentColor.opacity(0.30) : .clear,
                radius: isSelected ? 8 : 0
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.16)) {
                isHovering = hovering
            }
        }
        .help("The real \(agent.name) — deployed inside \(agent.appName). Live data, his memory, his audit trail.")
    }
}

// MARK: - Agent Rail Card

private struct AgentRailCard: View {
    let agent: AgentStatus
    let spec: AgentSpec?
    let isSelected: Bool
    let isCore: Bool
    let onTap: () -> Void
    var onRemove: (() -> Void)? = nil

    @State private var isHovering = false

    // OG squad: Chiss blue stripe. V2: amber stripe.
    private var accentColor: Color {
        isCore
            ? Color.chissPrimary
            : Color(red: 0.98, green: 0.72, blue: 0.18)
    }

    private var isCommandCard: Bool {
        isCore || agent.id.lowercased() == "thrawn"
    }

    private var cardCornerRadius: CGFloat {
        isCommandCard ? 16 : 14
    }

    private var avatarSize: CGFloat {
        isCommandCard ? 46 : 40
    }

    private var verticalPadding: CGFloat {
        isCommandCard ? 12 : 10
    }

    private var glowOpacity: Double {
        guard isCommandCard else { return isSelected ? 0.30 : 0.0 }
        if isSelected { return 0.60 }
        return isHovering ? 0.48 : 0.38
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .leading) {
                // Card background
                cardBackground

                // Left accent stripe — clipped to the rounded rect shape
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(accentColor.opacity(isCommandCard ? (isSelected ? 0.96 : 0.82) : (isSelected ? 0.85 : 0.50)))
                        .frame(width: isCommandCard ? 4.5 : 3)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))

                // Border overlay
                borderLayer

                // Content — left-padded to clear the accent stripe
                HStack(alignment: .top, spacing: 10) {
                    AgentPixelAvatar(
                        agentId: agent.id,
                        agentName: agent.name,
                        state: agent.state,
                        size: avatarSize
                    )
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(agent.name)
                                .font(.system(size: isCommandCard ? 13.8 : 12.5, weight: isCommandCard ? .bold : .semibold))
                                .foregroundColor(Color.white.opacity(isCommandCard ? 0.98 : 0.92))
                                .lineLimit(1)
                                .minimumScaleFactor(0.80)
                            HStack(spacing: 8) {
                                Text(agent.state.label.uppercased())
                                    .font(.system(size: isCommandCard ? 9 : 8.5, weight: .heavy))
                                    .tracking(1.6)
                                    .foregroundColor(agent.state.chissColor.opacity(isCommandCard ? 0.92 : 0.75))
                                HeartbeatCountdownBadge(owner: agent.id, compact: true)
                            }
                            Text(agent.detail)
                                .font(.system(size: isCommandCard ? 10.4 : 10, weight: .medium))
                                .foregroundColor(Color.white.opacity(isCommandCard ? 0.62 : 0.50))
                                .lineLimit(2)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 4) {
                            AgentGatewayPicker(agentID: agent.id, style: .rail)
                            Text(agent.role)
                                .font(.system(size: isCommandCard ? 9.8 : 9.5, weight: .bold))
                                .foregroundColor(agent.state.chissColor.opacity(isCommandCard ? 0.96 : 0.85))
                                .frame(width: isCommandCard ? 100 : 96, alignment: .trailing)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }
                }
                .padding(.leading, isCommandCard ? 14 : 13)   // clears the accent stripe
                .padding(.trailing, isCommandCard ? 11 : 10)
                .padding(.vertical, verticalPadding)
            }
            .shadow(
                color: isCommandCard ? Color.chissPrimary.opacity(glowOpacity) : (isSelected ? agent.state.chissColor.opacity(0.30) : .clear),
                radius: isCommandCard ? 18 : (isSelected ? 8 : 0),
                x: 0,
                y: 0
            )
            .shadow(
                color: isCommandCard ? Color(red: 0.35, green: 0.62, blue: 1.0).opacity(glowOpacity * 0.42) : .clear,
                radius: isCommandCard ? 9 : 0,
                x: 0,
                y: 5
            )
            .overlay(alignment: .topTrailing) {
                if let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.20))
                            .background(Circle().fill(Color.obsidianMid).padding(-1))
                    }
                    .buttonStyle(.plain)
                    .offset(x: -6, y: 6)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, isCommandCard ? -2 : 0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.16)) {
                isHovering = hovering
            }
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if isCommandCard {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.chissDeep.opacity(isSelected ? 0.48 : 0.36),
                            Color.obsidianMid.opacity(0.92),
                            Color.white.opacity(0.050)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.chissPrimary.opacity(isSelected ? 0.30 : 0.22),
                                    Color(red: 0.25, green: 0.48, blue: 1.0).opacity(0.09),
                                    Color.clear
                                ],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 155
                            )
                        )
                        .blendMode(.screen)
                )
        } else {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(isSelected
                      ? agent.state.chissColor.opacity(0.10)
                      : Color.white.opacity(0.038))
        }
    }

    @ViewBuilder
    private var borderLayer: some View {
        if isCommandCard {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.44),
                            agent.state.chissColor.opacity(isSelected ? 0.88 : 0.62),
                            Color.chissPrimary.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isSelected ? 1.8 : 1.35
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cardCornerRadius - 2, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                        .padding(2.5)
                )
        } else {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(
                    isSelected
                        ? agent.state.chissColor.opacity(0.55)
                        : agent.state.chissColor.opacity(0.20),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
    }
}

// MARK: - Agent Model Badge

private struct AgentModelBadge: View {
    struct Route {
        let model: String
        let provider: String
        let reasoning: String?
    }

    let route: Route
    let isProminent: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(route.model)
                .font(.system(size: isProminent ? 11.0 : 10.5, weight: .black, design: .rounded))
                .tracking(isProminent ? 1.15 : 1.0)
                .foregroundColor(Color.white.opacity(0.96))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, isProminent ? 11 : 10)
                .frame(height: isProminent ? 21 : 20)
                .background {
                    ZStack {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.020, green: 0.045, blue: 0.070),
                                        Color(red: 0.060, green: 0.150, blue: 0.205)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Capsule()
                            .stroke(Color.chissPrimary.opacity(isProminent ? 0.92 : 0.78), lineWidth: isProminent ? 1.1 : 1)
                        Capsule()
                            .stroke(Color.white.opacity(isProminent ? 0.30 : 0.22), lineWidth: 0.5)
                            .padding(2)
                    }
                }
                .shadow(color: Color.chissPrimary.opacity(isProminent ? 0.62 : 0.42), radius: isProminent ? 6 : 4, x: 0, y: 0)

            Text(subtitle)
                .font(.system(size: isProminent ? 6.8 : 6.6, weight: .heavy))
                .tracking(0.9)
                .foregroundColor(Color.chissPrimary.opacity(isProminent ? 0.86 : 0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: isProminent ? 100 : 96, alignment: .trailing)
        .help("\(route.provider) \(route.model)\(route.reasoning.map { " \($0)" } ?? "")")
    }

    private var subtitle: String {
        if let reasoning = route.reasoning, !reasoning.isEmpty {
            return "\(route.provider) \(reasoning.uppercased())"
        }
        return route.provider
    }

    static func route(for spec: AgentSpec?) -> Route {
        guard let spec else {
            return Route(model: "ROUTE", provider: "UNKNOWN", reasoning: nil)
        }

        if let override = spec.modelOverride {
            return Route(
                model: displayModel(override.model),
                provider: displayProvider(override.provider),
                reasoning: override.reasoningEffort
            )
        }

        switch spec.tier {
        case .explicit(let tier):
            return route(for: tier)
        case .inherit:
            return Route(model: "LOADOUT", provider: "INHERIT", reasoning: nil)
        }
    }

    private static func route(for tier: ModelTier) -> Route {
        switch tier {
        case .local, .cheap, .premium:
            return Route(
                model: "LIVE MODEL",
                provider: "CODEX",
                reasoning: nil
            )
        }
    }

    private static func displayProvider(_ backend: ProviderBackend) -> String {
        switch backend {
        case .codex: return "CODEX"
        case .grok: return "GROK"
        case .claude: return "CLAUDE"
        case .xai: return "XAI"
        case .openclaw: return "OPENCLAW"
        case .openai: return "GLM"
        case .ollama: return "OLLAMA"
        }
    }

    private static func displayModel(_ model: String) -> String {
        let lower = model.lowercased()
        if lower.contains("grok-4.5") { return "GROK-4.5" }
        if lower.contains("gpt-5.4") { return "GPT-5.4" }
        if lower.contains("glm-5.2") { return "GLM-5.2" }
        if lower.contains("kimi") { return "KIMI" }
        if lower.contains("haiku") { return "HAIKU" }
        if lower.count > 8 { return String(model.prefix(8)).uppercased() }
        return model.uppercased()
    }
}

// MARK: - Empty Agent Slot

private struct EmptyAgentSlot: View {
    var isHighlighted: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(
                        Color.chissPrimary.opacity(isHighlighted ? 0.45 : 0.12),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
                    .frame(width: 32, height: 32)
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.chissPrimary.opacity(isHighlighted ? 0.55 : 0.20))
            }

            Text("Drop agent here")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Color.white.opacity(isHighlighted ? 0.35 : 0.15))
            Spacer()
        }
        .padding(.leading, 13)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isHighlighted ? 0.04 : 0.01))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isHighlighted
                                ? Color.chissPrimary.opacity(0.30)
                                : Color.chissPrimary.opacity(0.06),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                )
        )
    }
}

// MARK: - AgentActivityState color extension

extension AgentActivityState {
    var chissColor: Color {
        switch self {
        case .idle:    return Color.chissPrimary.opacity(0.55)
        case .working: return Color.chissPrimary
        case .handoff: return Color(red: 0.55, green: 0.82, blue: 0.95)
        case .review:  return Color(red: 0.78, green: 0.88, blue: 0.98)
        case .blocked: return Color(red: 0.90, green: 0.40, blue: 0.38)
        }
    }
}

// MARK: - Mute Toggle Button
//
// "I'm on a Zoom call" button. Lives at the top of the agents panel so it's
// always one click away. When unmuted, it's a low-key speaker icon that
// doesn't draw attention. When muted, it switches to a solid red chip with
// a slashed speaker icon — IMMEDIATELY readable so you can tell at a glance
// that voice is silenced (and remember to flip it back on later).

private struct MuteToggleButton: View {
    let muted: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(iconColor)
                if muted {
                    Text("MUTED")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.0)
                        .foregroundColor(Color.white.opacity(0.95))
                }
            }
            .padding(.horizontal, muted ? 8 : 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(borderColor, lineWidth: muted ? 0 : 1)
            )
            .shadow(
                color: muted ? Color(red: 0.95, green: 0.20, blue: 0.18).opacity(0.45)
                             : .clear,
                radius: muted ? 4 : 0
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(muted ? "Voice is muted — click to unmute"
                    : "Mute agent voices (for calls / focus time)")
        .accessibilityLabel(muted ? "Unmute agent voices" : "Mute agent voices")
    }

    private var iconColor: Color {
        if muted { return Color.white }
        return isHovering
            ? Color.chissPrimary.opacity(0.95)
            : Color.chissPrimary.opacity(0.65)
    }

    private var backgroundFill: Color {
        if muted {
            // Sith-red, fully filled. Loud on purpose.
            return Color(red: 0.85, green: 0.18, blue: 0.16)
        }
        return isHovering
            ? Color.chissPrimary.opacity(0.12)
            : Color.chissPrimary.opacity(0.05)
    }

    private var borderColor: Color {
        isHovering
            ? Color.chissPrimary.opacity(0.40)
            : Color.chissPrimary.opacity(0.18)
    }
}
