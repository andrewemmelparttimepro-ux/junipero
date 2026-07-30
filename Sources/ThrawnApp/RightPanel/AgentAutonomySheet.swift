import SwiftUI

// MARK: - Agent Autonomy Sheet (Earned Delegation)
//
// Opened from the gear on an agent card. Cyclops-style permission ladder:
// each capability row carries an Observe / Suggest / Prepare / Execute
// selector; hard-locked levels render with a lock and cannot be chosen.

struct AgentAutonomySheet: View {
    @Binding var isPresented: Bool
    let agent: AgentStatus

    @EnvironmentObject var autonomy: AgentAutonomyStore

    private var accentColor: Color { agent.id == "thrawn" ? .chissPrimary : .ndaiGreen }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 26)
                .padding(.top, 24)
                .padding(.bottom, 18)

            Divider().overlay(Color.white.opacity(0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ladderKicker
                    ForEach(AutonomyCatalog.capabilities) { cap in
                        capabilityRow(cap)
                    }
                    auditFootnote
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 18)
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack {
                Spacer()
                Button(action: { isPresented = false }) {
                    Text("DONE")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.4)
                        .foregroundColor(Color(red: 0.03, green: 0.08, blue: 0.05))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.ndaiGreen))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
        }
        .frame(width: 760, height: 640)
        .background(Color.obsidian)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("EARNED DELEGATION")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(2.6)
                    .foregroundColor(accentColor.opacity(0.85))

                Text("You decide how far \(agent.name) can reach.")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Text("\(agent.name) starts by observing. It earns broader permission through visible, reversible, audited work. These controls set the ceiling for every heartbeat.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .lineSpacing(2)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 5) {
                Label("Human authority intact", systemImage: "shield.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.ndaiGreen)
                Text("External sends, deployments, and money movement are locked.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(width: 218, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.ndaiGreen.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.ndaiGreen.opacity(0.25), lineWidth: 1))
            )
        }
    }

    private var ladderKicker: some View {
        HStack {
            Text("PERMISSION LADDER")
                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                .tracking(2.4)
                .foregroundColor(.white.opacity(0.42))
            Spacer()
            Label("EVERY ACTION AUDITED", systemImage: "eye")
                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.34))
        }
        .padding(.bottom, 2)
    }

    // MARK: Capability Row

    private func capabilityRow(_ cap: AutonomyCapability) -> some View {
        let current = autonomy.level(agentId: agent.id, capability: cap.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cap.title)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(.white.opacity(0.92))
                    Text(cap.blurb)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.52))
                }
                Spacer()
                levelSelector(cap, current: current)
            }

            Label(cap.guardrail, systemImage: "shield")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.white.opacity(0.40))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.030))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
        )
    }

    private func levelSelector(_ cap: AutonomyCapability, current: AutonomyLevel) -> some View {
        HStack(spacing: 4) {
            ForEach(AutonomyLevel.allCases) { level in
                let locked = level > cap.maxLevel
                let selected = level == current
                Button {
                    guard !locked else { return }
                    autonomy.setLevel(agentId: agent.id, capability: cap.id, level: level)
                } label: {
                    VStack(spacing: 2) {
                        HStack(spacing: 3) {
                            if locked {
                                Image(systemName: "lock.fill").font(.system(size: 7, weight: .black))
                            }
                            Text(level.label)
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .tracking(0.8)
                        }
                        Text(level.blurb)
                            .font(.system(size: 7, weight: .medium))
                            .opacity(0.7)
                    }
                    .foregroundColor(
                        locked ? .white.opacity(0.22)
                        : selected ? accentColor
                        : .white.opacity(0.55)
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minWidth: 84)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selected ? accentColor.opacity(0.12) : Color.white.opacity(0.035))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(selected ? accentColor.opacity(0.55) : Color.white.opacity(0.10), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(locked)
                .help(locked ? "Hard-locked: \(cap.guardrail)" : level.blurb)
            }
        }
    }

    private var auditFootnote: some View {
        Text("Ceilings are injected into every heartbeat prompt for \(agent.name) and logged to the flight recorder when changed. Lowering a level takes effect on the next wake.")
            .font(.system(size: 9.5, weight: .medium))
            .foregroundColor(.white.opacity(0.35))
            .padding(.top, 4)
    }
}
