import SwiftUI

struct AgentRailView: View {
    @EnvironmentObject var roster: AgentRosterStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AGENTS")
                    .font(.system(size: 12, weight: .bold, design: .serif))
                    .tracking(2)
                    .foregroundColor(Color.white.opacity(0.9))
                Spacer()
                Text("Fleet")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.60, green: 0.78, blue: 1.0))
            }

            VStack(spacing: 10) {
                ForEach(roster.agents) { agent in
                    AgentRailCard(agent: agent)
                }
            }

            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct AgentRailCard: View {
    let agent: AgentStatus

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            jewel
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(agent.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.96))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Spacer(minLength: 8)
                    Text(agent.role)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(agent.state.color.opacity(0.9))
                        .lineLimit(1)
                }
                Text(agent.detail)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.62))
                    .lineLimit(2)
                Text(agent.state.label.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundColor(agent.state.color)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(agent.state.color.opacity(0.22), lineWidth: 1)
                )
        )
    }

    private var jewel: some View {
        ZStack {
            Circle()
                .fill(agent.state.color.opacity(0.18))
                .frame(width: 24, height: 24)
                .blur(radius: 8)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            agent.state.color.opacity(0.95),
                            agent.state.color.opacity(0.55)
                        ],
                        center: .center,
                        startRadius: 1,
                        endRadius: 11
                    )
                )
                .frame(width: 14, height: 14)
                .shadow(color: agent.state.color.opacity(agent.state == .handoff ? 0.95 : 0.55), radius: agent.state == .handoff ? 12 : 5)
        }
        .padding(.top, 2)
    }
}
