import SwiftUI

struct AgentRailView: View {
    @EnvironmentObject var roster: AgentRosterStore
    @EnvironmentObject var nav: ConsoleNavigationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AGENTS")
                    .font(.system(size: 11, weight: .bold, design: .default))
                    .tracking(2.5)
                    .foregroundColor(Color.chissPrimary.opacity(0.90))
                Spacer()
                Text("Fleet")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.chissPrimary.opacity(0.55))
            }

            VStack(spacing: 8) {
                ForEach(roster.agents) { agent in
                    AgentRailCard(
                        agent: agent,
                        isSelected: nav.selectedAgentId == agent.id,
                        onTap: {
                            withAnimation(.spring(response: 0.28)) {
                                if nav.selectedAgentId == agent.id {
                                    nav.dismissAgent()
                                } else {
                                    nav.selectedAgentId = agent.id
                                }
                            }
                        }
                    )
                }
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
                        .stroke(Color.chissPrimary.opacity(0.14), lineWidth: 1)
                )
        )
    }
}

private struct AgentRailCard: View {
    let agent: AgentStatus
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                jewel
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
                    Text(agent.state.label.uppercased())
                        .font(.system(size: 8.5, weight: .heavy))
                        .tracking(1.6)
                        .foregroundColor(agent.state.chissColor.opacity(0.75))
                    Text(agent.detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.50))
                        .lineLimit(2)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? agent.state.chissColor.opacity(0.10) : Color.white.opacity(0.038))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? agent.state.chissColor.opacity(0.55) : agent.state.chissColor.opacity(0.20), lineWidth: isSelected ? 1.5 : 1)
                    )
            )
            .shadow(color: isSelected ? agent.state.chissColor.opacity(0.30) : .clear, radius: isSelected ? 8 : 0)
        }
        .buttonStyle(.plain)
    }

    @State private var pulseActive = false

    private var isActive: Bool {
        agent.state == .handoff || agent.state == .working
    }

    private var jewel: some View {
        ZStack {
            Circle()
                .fill(agent.state.chissColor.opacity(0.15))
                .frame(width: 22, height: 22)
                .blur(radius: 7)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.92),
                            agent.state.chissColor.opacity(0.90),
                            agent.state.chissColor.opacity(0.50),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 10
                    )
                )
                .frame(width: 13, height: 13)
                .shadow(color: agent.state.chissColor.opacity(isActive ? 0.90 : 0.45), radius: isActive ? 10 : 4)

            // Pulse ring for active agents
            if isActive {
                Circle()
                    .stroke(agent.state.chissColor.opacity(0.40), lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                    .scaleEffect(pulseActive ? 1.6 : 1.0)
                    .opacity(pulseActive ? 0 : 0.8)
                    .animation(
                        Animation.easeOut(duration: 1.5).repeatForever(autoreverses: false),
                        value: pulseActive
                    )
            }
        }
        .padding(.top, 2)
        .onChange(of: isActive) { active in
            // Reset and retrigger pulse when state changes
            pulseActive = false
            if active {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    pulseActive = true
                }
            }
        }
        .onAppear {
            if isActive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    pulseActive = true
                }
            }
        }
    }
}

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
