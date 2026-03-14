import SwiftUI

struct AgentRailView: View {
    @EnvironmentObject var roster: AgentRosterStore

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
                    AgentRailCard(agent: agent)
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

    var body: some View {
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
                .fill(Color.white.opacity(0.038))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(agent.state.chissColor.opacity(0.20), lineWidth: 1)
                )
        )
    }

    private var jewel: some View {
        let isActive = agent.state == .handoff || agent.state == .working
        return ZStack {
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
        }
        .padding(.top, 2)
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
