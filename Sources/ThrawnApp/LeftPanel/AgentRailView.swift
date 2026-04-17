import SwiftUI
import UniformTypeIdentifiers

// MARK: - Core Squad Definition
// These six are fixed and permanent — the original devops crew.
// Any agent not in this set is a V2 agent and gets the amber treatment.
let coreAgentIds: Set<String> = ["thrawn", "r2d2", "c3po", "quigon", "lando", "boba"]

// MARK: - Agent Rail View

struct AgentRailView: View {
    @EnvironmentObject var roster: AgentRosterStore
    @EnvironmentObject var nav: ConsoleNavigationStore
    @EnvironmentObject var execution: ExecutionService
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
            HStack {
                Text("AGENTS")
                    .font(.system(size: 11, weight: .bold, design: .default))
                    .tracking(2.5)
                    .foregroundColor(Color.chissPrimary.opacity(0.90))
                Spacer()

                // Unleashed mode — hidden in a dropdown
                if ThrawnPreferencesStore.load().canToggleAccess {
                    Menu {
                        Button {
                            withAnimation(.spring(response: 0.28)) {
                                execution.toggleAccess()
                            }
                        } label: {
                            HStack {
                                Text(execution.accessMode.isUnleashed
                                     ? "Restrict Access"
                                     : "Unleash Access")
                                if execution.accessMode.isUnleashed {
                                    Image(systemName: "bolt.fill")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if execution.accessMode.isUnleashed {
                                Text("\u{26A1}")
                                    .font(.system(size: 9))
                                    .foregroundColor(Color.sithGlow.opacity(0.85))
                            }
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color.chissPrimary.opacity(0.50))
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 4) {
                        Text("Fleet")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color.chissPrimary.opacity(0.55))
                        if execution.accessMode.isUnleashed {
                            Text("\u{26A1}")
                                .font(.system(size: 9))
                                .foregroundColor(Color.sithGlow.opacity(0.85))
                        }
                    }
                }
            }

            VStack(spacing: 8) {
                // ── Core Squad ────────────────────────────────────────────
                ForEach(coreAgents) { agent in
                    AgentRailCard(
                        agent: agent,
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
                            isSelected: nav.selectedAgentId == agent.id,
                            isCore: false,
                            onTap: { selectAgent(agent) }
                        )
                    }
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
            }
            .onDrop(of: [UTType.plainText], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }

            Spacer()
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
}

// MARK: - Agent Rail Card

private struct AgentRailCard: View {
    let agent: AgentStatus
    let isSelected: Bool
    let isCore: Bool
    let onTap: () -> Void
    var onRemove: (() -> Void)? = nil

    // OG squad: Chiss blue stripe. V2: amber stripe.
    private var accentColor: Color {
        isCore
            ? Color.chissPrimary
            : Color(red: 0.98, green: 0.72, blue: 0.18)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .leading) {
                // Card background
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected
                          ? agent.state.chissColor.opacity(0.10)
                          : Color.white.opacity(0.038))

                // Left accent stripe — clipped to the rounded rect shape
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(accentColor.opacity(isSelected ? 0.85 : 0.50))
                        .frame(width: 3)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Border overlay
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected
                            ? agent.state.chissColor.opacity(0.55)
                            : agent.state.chissColor.opacity(0.20),
                        lineWidth: isSelected ? 1.5 : 1
                    )

                // Content — left-padded to clear the accent stripe
                HStack(alignment: .top, spacing: 10) {
                    AgentPixelAvatar(
                        agentId: agent.id,
                        agentName: agent.name,
                        state: agent.state,
                        size: 40
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(agent.name)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.92))
                                .lineLimit(1)
                                .minimumScaleFactor(0.80)
                            Spacer(minLength: 6)
                            Text(agent.role)
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(agent.state.chissColor.opacity(0.85))
                                .lineLimit(1)
                        }
                        HStack(spacing: 8) {
                            Text(agent.state.label.uppercased())
                                .font(.system(size: 8.5, weight: .heavy))
                                .tracking(1.6)
                                .foregroundColor(agent.state.chissColor.opacity(0.75))
                            HeartbeatCountdownBadge(owner: agent.id, compact: true)
                        }
                        Text(agent.detail)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.50))
                            .lineLimit(2)
                    }
                }
                .padding(.leading, 13)   // clears the accent stripe
                .padding(.trailing, 10)
                .padding(.vertical, 10)
            }
            .shadow(
                color: isSelected ? agent.state.chissColor.opacity(0.30) : .clear,
                radius: isSelected ? 8 : 0
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
