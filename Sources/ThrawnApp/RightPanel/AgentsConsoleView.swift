import AVFoundation
import SwiftUI

// MARK: - Agents Console (Right Panel — V2 Roster)

struct AgentsConsoleView: View {
    @EnvironmentObject var roster: AgentRosterStore
    @EnvironmentObject var specStore: AgentSpecStore
    @EnvironmentObject var loadoutStore: StandardLoadoutStore
    @EnvironmentObject var rankEvaluator: RankEvaluator
    @EnvironmentObject var nav: ConsoleNavigationStore
    @EnvironmentObject var scheduler: AgentScheduler
    @EnvironmentObject var agentRuntime: AgentRuntimeCoordinator

    @State private var showSpawn = false
    @State private var showEditLoadout = false
    @State private var showAutonomy = false
    @State private var selectedRosterAgentId: String?
    @State private var accountActionInFlight = false
    @State private var accountActionError: String?
    @StateObject private var autonomyStore = AgentAutonomyStore()

    private var coreAgents: [AgentStatus] {
        roster.agents.filter { coreAgentIds.contains($0.id) }
    }

    private var v2Agents: [AgentStatus] {
        roster.agents.filter { !coreAgentIds.contains($0.id) }
    }

    private var allAgents: [AgentStatus] {
        coreAgents + v2Agents
    }

    private var selectedAgent: AgentStatus? {
        if let selectedRosterAgentId,
           let agent = allAgents.first(where: { $0.id == selectedRosterAgentId }) {
            return agent
        }
        return allAgents.first
    }

    var body: some View {
        ZStack {
            Color.obsidian.ignoresSafeArea()
            LinearGradient(
                colors: [
                    Color.black.opacity(0.28),
                    Color(red: 0.03, green: 0.05, blue: 0.05).opacity(0.72),
                    Color.obsidian.opacity(0.95),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    fleetHeader
                    controlsRow

                    if let selectedAgent {
                        gatewayControl(for: selectedAgent)

                        AgentDossierCard(
                            agent: selectedAgent,
                            spec: spec(for: selectedAgent),
                            score: rankEvaluator.scores[selectedAgent.id],
                            resolvedTools: specStore.resolvedTools(forAgentId: selectedAgent.id),
                            isPinned: nav.pinnedLeftPanelAgents.contains(selectedAgent.id),
                            onOpen: { openAgent(selectedAgent) },
                            onPinToggle: { togglePin(selectedAgent) },
                            onAutonomy: { showAutonomy = true }
                        )
                        .onDrag { NSItemProvider(object: selectedAgent.id as NSString) }
                    }

                    sectionDivider("ROSTER", color: Color.ndaiGreen)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 14)], spacing: 14) {
                        ForEach(allAgents) { agent in
                            AgentRosterTile(
                                agent: agent,
                                spec: spec(for: agent),
                                score: rankEvaluator.scores[agent.id],
                                resolvedTools: specStore.resolvedTools(forAgentId: agent.id),
                                isSelected: selectedAgent?.id == agent.id,
                                isPinned: nav.pinnedLeftPanelAgents.contains(agent.id),
                                onSelect: { selectRosterAgent(agent) },
                                onOpen: { openAgent(agent) }
                            )
                            .onDrag { NSItemProvider(object: agent.id as NSString) }
                        }
                    }
                }
                .padding(18)
            }
        }
        .onAppear {
            if selectedRosterAgentId == nil {
                selectedRosterAgentId = nav.selectedAgentId ?? allAgents.first?.id
            }
            refreshSelectedAgentAccount()
        }
        .onChange(of: selectedRosterAgentId) { _ in
            accountActionError = nil
            refreshSelectedAgentAccount()
        }
        .sheet(isPresented: $showSpawn) {
            SpawnAgentSheet(isPresented: $showSpawn)
                .environmentObject(specStore)
                .environmentObject(roster)
                .environmentObject(scheduler)
        }
        .sheet(isPresented: $showEditLoadout) {
            EditLoadoutSheet(isPresented: $showEditLoadout)
                .environmentObject(loadoutStore)
        }
        .sheet(isPresented: $showAutonomy) {
            if let selectedAgent {
                AgentAutonomySheet(isPresented: $showAutonomy, agent: selectedAgent)
                    .environmentObject(autonomyStore)
            }
        }
    }

    // MARK: Subscription Gateway

    private func gatewayControl(for agent: AgentStatus) -> some View {
        let backend = gatewayBackend(for: agent.id)
        let status = agentRuntime.status(for: backend, agentID: agent.id)
        let isSteven = agent.id == "steven"
        let isSignedIn = status.state == .ready
        let isBusy = accountActionInFlight || status.state == .starting
        let actionTitle = isSignedIn ? "SIGN OUT" : "SIGN IN"
        let actionForeground = isSignedIn
            ? Color.orange.opacity(0.92)
            : Color.black.opacity(0.82)
        let actionFill = isSignedIn
            ? Color.orange.opacity(0.10)
            : Color.chissPrimary.opacity(0.90)
        let actionStroke = isSignedIn
            ? Color.orange.opacity(0.30)
            : Color.chissPrimary.opacity(0.30)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.chissPrimary.opacity(0.10))
                        .frame(width: 40, height: 40)
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color.chissPrimary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("AGENT ACCOUNT PROFILE")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .tracking(1.7)
                        .foregroundColor(.white.opacity(0.40))
                    Text("Sign in or out without deleting this agent's local context.")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.54))
                }

                Spacer()

                AgentGatewayPicker(agentID: agent.id, style: .account)

                if isSteven {
                    Text("LOCKED")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .tracking(1.2)
                        .foregroundColor(Color.orange.opacity(0.86))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.09))
                                .overlay(Capsule().stroke(Color.orange.opacity(0.24), lineWidth: 1))
                        )
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.075))
                .frame(height: 1)

            HStack(spacing: 10) {
                Circle()
                    .fill(isSignedIn ? Color.green : (isBusy ? Color.orange : Color.white.opacity(0.25)))
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isSignedIn ? "SIGNED IN" : (isBusy ? "SIGN-IN IN PROGRESS" : "SIGNED OUT"))
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .tracking(1.2)
                        .foregroundColor(isSignedIn ? Color.green.opacity(0.9) : .white.opacity(0.58))
                    Text(accountDescription(status))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.76))
                        .lineLimit(1)
                    Text(status.detail)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.38))
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    refreshAccount(agentID: agent.id, backend: backend)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.54))
                .disabled(isBusy)
                .help("Refresh this agent's account status")

                Button {
                    performAccountAction(
                        signedIn: isSignedIn,
                        agentID: agent.id,
                        backend: backend
                    )
                } label: {
                    Text(actionTitle)
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .tracking(1.0)
                        .foregroundColor(actionForeground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(actionFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(actionStroke, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }

            if let accountActionError {
                Text(accountActionError)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(Color.red.opacity(0.86))
                    .lineLimit(2)
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                )
        )
    }

    private func accountDescription(_ status: ProviderStatus) -> String {
        guard let account = status.account else {
            return "No provider account connected to this agent"
        }
        if let email = account.email, !email.isEmpty {
            return "\(account.displayName) · \(email)"
        }
        return account.displayName
    }

    private func refreshSelectedAgentAccount() {
        guard let agent = selectedAgent else { return }
        refreshAccount(agentID: agent.id, backend: gatewayBackend(for: agent.id))
    }

    private func refreshAccount(agentID: String, backend: ProviderBackend) {
        Task {
            await agentRuntime.refresh(agentID: agentID, backend: backend)
        }
    }

    private func performAccountAction(
        signedIn: Bool,
        agentID: String,
        backend: ProviderBackend
    ) {
        accountActionInFlight = true
        accountActionError = nil
        Task {
            do {
                if signedIn {
                    try await agentRuntime.signOut(agentID: agentID, backend: backend)
                } else {
                    try await agentRuntime.beginSignIn(agentID: agentID, backend: backend)
                }
            } catch {
                accountActionError = error.localizedDescription
            }
            accountActionInFlight = false
        }
    }

    private func gatewayBackend(for agentID: String) -> ProviderBackend {
        specStore.subscriptionGateway(forAgentId: agentID)
    }

    // MARK: Fleet Header

    private var fleetHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.ndaiGreen.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: "person.3.sequence.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.ndaiGreen)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("NDAI AGENT SELECT")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(chromeGradient)
                    .lineLimit(1)
                Text("Choose a role, inspect readiness, then open the agent session.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.46))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(roster.agents.count)")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.90))
                Text("ACTIVE")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.ndaiGreen.opacity(0.78))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.08).opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    // MARK: Controls Row

    private var controlsRow: some View {
        HStack(spacing: 10) {
            Button { showSpawn = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                    Text("SPAWN").tracking(0.8)
                }
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(Color(red: 0.03, green: 0.08, blue: 0.05))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.ndaiGreen)
                        .shadow(color: Color.ndaiGreen.opacity(0.25), radius: 10)
                )
            }
            .buttonStyle(.plain)

            Button { showEditLoadout = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3")
                    Text("LOADOUT").tracking(0.8)
                }
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)

            Button { rankEvaluator.evaluateAll() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("SCORE").tracking(0.8)
                }
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(.white.opacity(0.50))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.04)))
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: Section Divider

    private func sectionDivider(_ title: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(color.opacity(0.15)).frame(height: 1)
            Text(title)
                .font(.system(size: 9, weight: .black))
                .tracking(2.5)
                .foregroundColor(color.opacity(0.70))
            Rectangle().fill(color.opacity(0.15)).frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private func selectRosterAgent(_ agent: AgentStatus) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            selectedRosterAgentId = agent.id
        }
    }

    private func openAgent(_ agent: AgentStatus) {
        withAnimation(.spring(response: 0.28)) {
            nav.selectedAgentId = agent.id
        }
    }

    private func togglePin(_ agent: AgentStatus) {
        if nav.pinnedLeftPanelAgents.contains(agent.id) {
            nav.unpinAgent(agent.id)
        } else {
            nav.pinAgent(agent.id)
        }
    }

    private func spec(for agent: AgentStatus) -> AgentSpec? {
        specStore.specs.first(where: { $0.id == agent.id })
    }

    private var chromeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white,
                Color(red: 0.82, green: 0.84, blue: 0.88),
                Color(red: 0.55, green: 0.57, blue: 0.63),
                Color(red: 0.86, green: 0.87, blue: 0.90),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Roster Dossier

private struct AgentDossierCard: View {
    let agent: AgentStatus
    let spec: AgentSpec?
    let score: AgentScore?
    let resolvedTools: [String]
    let isPinned: Bool
    let onOpen: () -> Void
    let onPinToggle: () -> Void
    let onAutonomy: () -> Void

    private var accentColor: Color { agent.id == "thrawn" ? .chissPrimary : .ndaiGreen }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                AgentPortraitStage(agent: agent, size: 172, accent: accentColor)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(agent.name.uppercased())
                                .font(.system(size: 36, weight: .black, design: .rounded))
                                .foregroundStyle(chromeGradient)
                                .lineLimit(1)
                                .minimumScaleFactor(0.68)
                            Text(agent.role.uppercased())
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .tracking(2.4)
                                .foregroundColor(accentColor.opacity(0.86))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            statePill
                            if isPinned { smallPill("PINNED", color: accentColor) }
                        }
                    }

                    Text(spec?.purpose ?? agent.detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.66))
                        .lineSpacing(3)
                        .lineLimit(3)

                    if let spec {
                        Text(spec.persona)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.42))
                            .lineSpacing(2)
                            .lineLimit(2)
                    }

                    HStack(spacing: 10) {
                        dossierStat("RANK", spec?.rank.displayName ?? "-", color: accentColor)
                        dossierStat("SCORE", score.map { "\($0.score)" } ?? "--", color: scoreColor(score?.score))
                        dossierStat("TASKS", "\(spec?.tasksCompleted ?? 0)", color: .white.opacity(0.80))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text("GATEWAY")
                                    .font(.system(size: 8, weight: .black, design: .monospaced))
                                    .tracking(1.4)
                                    .foregroundColor(.white.opacity(0.34))
                                if agent.id == "steven" {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundColor(Color.orange.opacity(0.75))
                                }
                            }
                            AgentGatewayPicker(agentID: agent.id, style: .dossier)
                        }
                        .frame(minWidth: 78, alignment: .leading)
                    }

                    HStack(spacing: 8) {
                        Button(action: onOpen) {
                            Label("OPEN SESSION", systemImage: "arrow.up.right.square.fill")
                                .font(.system(size: 10, weight: .black))
                                .tracking(1)
                                .foregroundColor(Color(red: 0.03, green: 0.08, blue: 0.05))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.ndaiGreen))
                        }
                        .buttonStyle(.plain)

                        Button(action: onPinToggle) {
                            Label(isPinned ? "UNPIN" : "PIN LEFT", systemImage: isPinned ? "pin.slash.fill" : "pin.fill")
                                .font(.system(size: 10, weight: .black))
                                .tracking(1)
                                .foregroundColor(.white.opacity(0.72))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.white.opacity(0.055)).overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Text("DRAG TO LEFT PANEL")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(1.6)
                            .foregroundColor(.white.opacity(0.24))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("LOADOUT")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(2.2)
                    .foregroundColor(.white.opacity(0.38))
                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(resolvedTools.prefix(5), id: \.self) { tool in
                        toolCapsule(tool)
                    }
                    if resolvedTools.count > 5 {
                        toolCapsule("+\(resolvedTools.count - 5)")
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.075, green: 0.075, blue: 0.075).opacity(0.94))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accentColor.opacity(0.85))
                .frame(width: 3)
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: onAutonomy) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(9)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.055))
                            .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .help("Autonomy — set how far \(agent.name) can reach")
            .padding(12)
        }
    }

    private var statePill: some View {
        HStack(spacing: 6) {
            Circle().fill(agent.state.chissColor).frame(width: 7, height: 7)
            Text(agent.state.label.uppercased())
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(1.4)
        }
        .foregroundColor(agent.state.chissColor.opacity(0.92))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(agent.state.chissColor.opacity(0.10)).overlay(Capsule().stroke(agent.state.chissColor.opacity(0.22), lineWidth: 1)))
    }

    private func smallPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .tracking(1.2)
            .foregroundColor(color.opacity(0.75))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.08)).overlay(Capsule().stroke(color.opacity(0.20), lineWidth: 1)))
    }

    private func dossierStat(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.34))
            Text(value.uppercased())
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(minWidth: 78, alignment: .leading)
    }

    private func tierLabel(_ spec: AgentSpec?) -> String {
        guard let spec else { return "-" }
        switch spec.tier {
        case .inherit: return "INHERIT"
        case .explicit(let tier): return tier.rawValue
        }
    }

    private func scoreColor(_ score: Int?) -> Color {
        guard let score else { return .white.opacity(0.45) }
        if score >= 90 { return .green }
        if score >= 75 { return .chissPrimary }
        if score >= 55 { return .orange }
        return .sithGlow
    }

    private func toolCapsule(_ tool: String) -> some View {
        Text(tool)
            .font(.system(size: 8.5, weight: .black, design: .monospaced))
            .foregroundColor(Color.white.opacity(0.62))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.055))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            )
    }

    private var chromeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white,
                Color(red: 0.78, green: 0.80, blue: 0.86),
                Color(red: 0.47, green: 0.49, blue: 0.56),
                Color(red: 0.86, green: 0.87, blue: 0.90),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Roster Tile

private struct AgentRosterTile: View {
    let agent: AgentStatus
    let spec: AgentSpec?
    let score: AgentScore?
    let resolvedTools: [String]
    let isSelected: Bool
    let isPinned: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    private var accentColor: Color {
        agent.id == "thrawn" ? .chissPrimary : .ndaiGreen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                AgentPortraitStage(agent: agent, size: 92, accent: accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.name)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.94))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(agent.role.uppercased())
                        .font(.system(size: 8.5, weight: .black, design: .monospaced))
                        .tracking(1.2)
                        .foregroundColor(accentColor.opacity(0.72))
                        .lineLimit(1)
                    AgentGatewayPicker(agentID: agent.id, style: .rail)
                    Text(agent.detail)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.46))
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }

            HStack(spacing: 9) {
                miniStat("R", spec?.rank.displayName ?? "-")
                miniStat("S", score.map { "\($0.score)" } ?? "--")
                miniStat("T", "\(resolvedTools.count)")
                Spacer()
                if isPinned { flag("PIN") }
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(Color.ndaiGreen.opacity(0.85))
                        .frame(width: 25, height: 25)
                        .background(Circle().fill(Color.ndaiGreen.opacity(0.10)).overlay(Circle().stroke(Color.ndaiGreen.opacity(0.24), lineWidth: 1)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(minHeight: 152, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.070) : Color.white.opacity(0.036))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? accentColor.opacity(0.62) : Color.white.opacity(0.10), lineWidth: isSelected ? 1.5 : 1)
                )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(isSelected ? accentColor : Color.white.opacity(0.10))
                .frame(height: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: onSelect)
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.32))
            Text(value)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.78))
        }
    }

    private func flag(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundColor(accentColor.opacity(0.76))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(accentColor.opacity(0.08)))
    }
}

private struct AgentPortraitStage: View {
    let agent: AgentStatus
    let size: CGFloat
    let accent: Color

    var body: some View {
        AgentPixelAvatar(
            agentId: agent.id,
            agentName: agent.name,
            state: agent.state,
            size: size
        )
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .stroke(accent.opacity(0.32), lineWidth: 1)
        )
        .shadow(color: accent.opacity(0.18), radius: 18, x: 0, y: 8)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Spawn Sheet

struct SpawnAgentSheet: View {
    @EnvironmentObject var specStore: AgentSpecStore
    @EnvironmentObject var roster: AgentRosterStore
    @EnvironmentObject var scheduler: AgentScheduler
    @Binding var isPresented: Bool

    @State private var id: String = ""
    @State private var name: String = ""
    @State private var role: String = ""
    @State private var persona: String = ""
    @State private var purpose: String = ""
    @State private var selectedTemplate: AgentBuildTemplate = .operatorRole
    @State private var selectedTools: Set<String> = ["file_read", "log_read", "task_write"]
    @State private var explicitTier: ModelTier = .premium
    @State private var rank: AgentRank = .b
    @State private var lifecycleMode: AgentLifecycleMode = .persistent
    @State private var taskBudget: Double = 5
    @State private var scheduleEnabled = true
    @State private var heartbeatMinute: Double = 20
    @State private var autonomy: Double = 0.48
    @State private var evidence: Double = 0.74
    @State private var review: Double = 0.62
    @State private var speechRate: Double = 0.48
    @State private var speechPitch: Double = 1.0
    @State private var voiceMuted = false
    @State private var voiceIdentifier: String = ""
    @State private var reviewStandard = "Every meaningful claim cites a file, log, screenshot, proof path, or task link."
    @State private var outputContract = "Write concise heartbeat summaries, update assigned tasks through pending updates, and keep raw evidence immutable."
    @State private var boundaryNotes = "Do not mutate production systems or delete evidence unless Thrawn explicitly assigns that work."
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            builderHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        identityPanel.frame(minWidth: 360)
                        controlTowerPanel.frame(width: 330)
                    }
                    templateRail
                    HStack(alignment: .top, spacing: 16) {
                        toolMatrix.frame(minWidth: 360)
                        voiceAndLifecycle.frame(width: 330)
                    }
                    contractPanel
                    launchPreview
                }
                .padding(18)
            }

            footer
        }
        .frame(width: 880, height: 760)
        .background(Color.obsidian)
        .onAppear {
            applyTemplate(.operatorRole, overwriteText: false)
            if voiceIdentifier.isEmpty {
                voiceIdentifier = Self.availableVoices.first?.identifier ?? ""
            }
        }
    }

    private var builderHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.ndaiGreen.opacity(0.16))
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 23, weight: .black))
                    .foregroundColor(.ndaiGreen)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text("AGENT BUILDER")
                    .font(.system(size: 27, weight: .black, design: .rounded))
                    .foregroundStyle(builderChrome)
                Text("Identity, tools, cadence, voice, review rules, and operating contract in one pass.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.48))
            }
            Spacer()
            BuilderMeter(label: "READY", value: readiness, color: readiness > 0.8 ? .ndaiGreen : .orange)
        }
        .padding(18)
        .background(Color.black.opacity(0.24))
    }

    private var identityPanel: some View {
        BuilderPanel(title: "IDENTITY", icon: "person.text.rectangle") {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.10), lineWidth: 1))
                    VStack(spacing: 8) {
                        AgentPixelAvatar(
                            agentId: generatedId.isEmpty ? "new-agent" : generatedId,
                            agentName: name.isEmpty ? "New Agent" : name,
                            state: .idle,
                            size: 116
                        )
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Text(generatedId.isEmpty ? "ID PENDING" : generatedId.uppercased())
                            .font(.system(size: 8.5, weight: .black, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(.white.opacity(0.42))
                    }
                }
                .frame(width: 146, height: 166)

                VStack(alignment: .leading, spacing: 10) {
                    builderField("CALLSIGN") {
                        TextField("Sir Whoever", text: $name)
                            .textFieldStyle(.plain)
                            .onChange(of: name) { newValue in
                                if id.isEmpty || id == slug(newValue.dropLast().description) {
                                    id = slug(newValue)
                                }
                            }
                    }
                    builderField("STABLE ID") {
                        TextField("sir-whoever", text: $id)
                            .textFieldStyle(.plain)
                            .onChange(of: id) { id = slug($0) }
                    }
                    builderField("TITLE / ROLE") {
                        TextField("Field Inspector", text: $role)
                            .textFieldStyle(.plain)
                    }
                }
            }

            builderField("PERSONA") {
                TextField("Plainspoken, practical, evidence-first.", text: $persona)
                    .textFieldStyle(.plain)
            }
            builderField("MISSION") {
                TextField("Own a clear operational job.", text: $purpose)
                    .textFieldStyle(.plain)
            }
        }
    }

    private var controlTowerPanel: some View {
        BuilderPanel(title: "CONTROL TOWER", icon: "dial.high") {
            HStack(spacing: 18) {
                KnobControl(title: "AUTONOMY", value: $autonomy, color: .ndaiGreen)
                KnobControl(title: "EVIDENCE", value: $evidence, color: .chissPrimary)
                KnobControl(title: "REVIEW", value: $review, color: .orange)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("MODEL ROUTE")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.36))
                Picker("", selection: $explicitTier) {
                    ForEach(ModelTier.allCases, id: \.self) { tier in
                        Text(tier.rawValue.uppercased()).tag(tier)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $scheduleEnabled) {
                    Text("HEARTBEAT ENABLED")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .tracking(1.2)
                }
                .toggleStyle(.switch)

                HStack(spacing: 16) {
                    MinuteDial(value: $heartbeatMinute)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(":\(Int(heartbeatMinute).formatted(.number.precision(.integerLength(2))))")
                            .font(.system(size: 33, weight: .black, design: .rounded))
                            .foregroundColor(scheduleEnabled ? .ndaiGreen : .white.opacity(0.28))
                        Text(scheduleEnabled ? "hourly wake minute" : "manual only")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.42))
                    }
                }
                .opacity(scheduleEnabled ? 1 : 0.45)
            }
        }
    }

    private var templateRail: some View {
        BuilderPanel(title: "ARCHETYPE", icon: "square.grid.3x2.fill") {
            HStack(spacing: 10) {
                ForEach(AgentBuildTemplate.allCases, id: \.self) { template in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            selectedTemplate = template
                            applyTemplate(template, overwriteText: true)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: template.icon)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(selectedTemplate == template ? .black : template.color)
                            Text(template.title)
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .tracking(1)
                                .lineLimit(1)
                            Text(template.subtitle)
                                .font(.system(size: 9, weight: .medium))
                                .lineLimit(2)
                                .foregroundColor(selectedTemplate == template ? .black.opacity(0.64) : .white.opacity(0.40))
                        }
                        .foregroundColor(selectedTemplate == template ? .black : .white.opacity(0.80))
                        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
                        .padding(11)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedTemplate == template ? template.color : Color.white.opacity(0.045))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(template.color.opacity(selectedTemplate == template ? 0.35 : 0.18), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var toolMatrix: some View {
        BuilderPanel(title: "TOOL LOADOUT", icon: "wrench.and.screwdriver.fill") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 152), spacing: 8)], spacing: 8) {
                ForEach(ToolRegistry.all, id: \.id) { tool in
                    ToolTile(
                        tool: tool,
                        isSelected: selectedTools.contains(tool.id),
                        action: { toggleTool(tool.id) }
                    )
                }
            }
        }
    }

    private var voiceAndLifecycle: some View {
        BuilderPanel(title: "VOICE + LIFE", icon: "waveform") {
            VStack(alignment: .leading, spacing: 8) {
                Text("SYSTEM VOICE")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.36))
                Picker("", selection: $voiceIdentifier) {
                    Text("System Default").tag("")
                    ForEach(Self.availableVoices, id: \.identifier) { voice in
                        Text("\(voice.name) · \(voice.language)").tag(voice.identifier)
                    }
                }
                .labelsHidden()
            }

            Toggle(isOn: $voiceMuted) {
                Text("MUTE AGENT VOICE")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1.1)
            }

            VStack(alignment: .leading, spacing: 10) {
                SliderRow(label: "RATE", value: $speechRate, range: 0.30...0.65, color: .chissPrimary)
                SliderRow(label: "PITCH", value: $speechPitch, range: 0.70...1.35, color: .ndaiGreen)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("LIFECYCLE")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.36))
                Picker("", selection: $lifecycleMode) {
                    ForEach(AgentLifecycleMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if lifecycleMode == .ephemeral {
                    SliderRow(label: "TASK CAP", value: $taskBudget, range: 1...20, color: .orange, integer: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("INITIAL RANK")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.36))
                Picker("", selection: $rank) {
                    ForEach(AgentRank.allCases, id: \.self) { rank in
                        Text(rank.displayName).tag(rank)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var contractPanel: some View {
        BuilderPanel(title: "OPERATING CONTRACT", icon: "scroll.fill") {
            HStack(alignment: .top, spacing: 12) {
                textBox("REVIEW STANDARD", text: $reviewStandard)
                textBox("OUTPUT CONTRACT", text: $outputContract)
                textBox("BOUNDARIES", text: $boundaryNotes)
            }
        }
    }

    private var launchPreview: some View {
        BuilderPanel(title: "LAUNCH CARD", icon: "checkmark.seal.fill") {
            HStack(spacing: 12) {
                BuilderMeter(label: "AUTONOMY", value: autonomy, color: .ndaiGreen)
                BuilderMeter(label: "EVIDENCE", value: evidence, color: .chissPrimary)
                BuilderMeter(label: "REVIEW", value: review, color: .orange)
                Divider().background(Color.white.opacity(0.16))
                VStack(alignment: .leading, spacing: 5) {
                    Text(name.isEmpty ? "Unnamed Agent" : name)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                    Text(role.isEmpty ? "Role pending" : role)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1.4)
                        .foregroundColor(.ndaiGreen.opacity(0.75))
                    Text("\(selectedTools.count) tools · \(explicitTier.rawValue) model · \(scheduleEnabled ? "hourly :\(Int(heartbeatMinute).formatted(.number.precision(.integerLength(2))))" : "manual")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.48))
                }
                Spacer()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.sithGlow)
            }
            Spacer()
            Button("Cancel") { isPresented = false }
                .buttonStyle(.bordered)
            Button {
                spawn()
            } label: {
                Label("Launch Agent", systemImage: "bolt.fill")
                    .font(.system(size: 12, weight: .black))
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(readiness < 0.78)
        }
        .padding(14)
        .background(Color.black.opacity(0.30))
    }

    private func builderField<V: View>(_ label: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(.white.opacity(0.36))
            content()
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.88))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.055))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.10), lineWidth: 1))
                )
        }
    }

    private func textBox(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                .tracking(1.3)
                .foregroundColor(.white.opacity(0.36))
            TextEditor(text: text)
                .font(.system(size: 11.5, weight: .medium))
                .scrollContentBackground(.hidden)
                .foregroundColor(.white.opacity(0.82))
                .padding(8)
                .frame(height: 86)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.10), lineWidth: 1))
                )
        }
    }

    private var generatedId: String {
        id.isEmpty ? slug(name) : slug(id)
    }

    private var readiness: Double {
        var score = 0.0
        if !generatedId.isEmpty { score += 0.18 }
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { score += 0.18 }
        if !role.trimmingCharacters(in: .whitespaces).isEmpty { score += 0.12 }
        if !persona.trimmingCharacters(in: .whitespaces).isEmpty { score += 0.13 }
        if !purpose.trimmingCharacters(in: .whitespaces).isEmpty { score += 0.15 }
        if !selectedTools.isEmpty { score += 0.12 }
        if !reviewStandard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 0.06 }
        if !outputContract.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 0.06 }
        return min(score, 1)
    }

    private static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { lhs, rhs in
                if lhs.quality.rawValue != rhs.quality.rawValue { return lhs.quality.rawValue > rhs.quality.rawValue }
                return lhs.name < rhs.name
            }
    }

    private func toggleTool(_ id: String) {
        if selectedTools.contains(id) {
            selectedTools.remove(id)
        } else {
            selectedTools.insert(id)
        }
    }

    private func applyTemplate(_ template: AgentBuildTemplate, overwriteText: Bool) {
        selectedTools = Set(template.tools)
        explicitTier = template.tier
        autonomy = template.autonomy
        evidence = template.evidence
        review = template.review
        scheduleEnabled = template.scheduleEnabled
        heartbeatMinute = Double(template.minute)
        if overwriteText || purpose.isEmpty { purpose = template.purpose }
        if overwriteText || persona.isEmpty { persona = template.persona }
        if overwriteText || role.isEmpty { role = template.defaultRole }
        if overwriteText || reviewStandard.isEmpty { reviewStandard = template.reviewStandard }
        if overwriteText || outputContract.isEmpty { outputContract = template.outputContract }
        if overwriteText || boundaryNotes.isEmpty { boundaryNotes = template.boundaryNotes }
    }

    private func slug(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func spawn() {
        let cleanId = generatedId
        guard !cleanId.isEmpty, !name.isEmpty else {
            errorText = "Callsign and ID are required."
            return
        }
        guard !specStore.specs.contains(where: { $0.id == cleanId }) else {
            errorText = "An agent with this ID already exists."
            return
        }

        let lifecycle: AgentLifecycle = lifecycleMode == .ephemeral
            ? .ephemeral(taskBudget: Int(taskBudget.rounded()))
            : .persistent
        let spec = AgentSpec(
            id: cleanId,
            name: name,
            role: role,
            persona: persona,
            purpose: purpose,
            tools: .explicit(ToolRegistry.all.map(\.id).filter { selectedTools.contains($0) }),
            tier: .explicit(explicitTier),
            rank: rank,
            pinned: true,
            lifecycle: lifecycle,
            knowledgeDir: "workspace/agents/\(cleanId)/knowledge",
            tasksCompleted: 0,
            createdAt: Date(),
            voiceIdentifier: voiceIdentifier.isEmpty ? nil : voiceIdentifier,
            speechRate: Float(speechRate),
            speechPitch: Float(speechPitch),
            voiceMuted: voiceMuted
        )
        specStore.upsert(spec)
        AgentSpecStore.ensureKnowledgeDirs(for: [spec])
        roster.upsert(AgentStatus(
            id: cleanId,
            name: name,
            role: role,
            state: .idle,
            detail: "\(role.isEmpty ? "Agent" : role) standing by",
            sessionKey: "agent:specialist:\(cleanId)"
        ))
        scheduler.upsertConfig(AgentHeartbeatConfig(
            id: cleanId,
            name: name,
            minuteOffset: Int(heartbeatMinute.rounded()) % 60,
            heartbeatFile: "\(cleanId).HEARTBEAT.md",
            agentFile: "\(cleanId).md",
            outputFile: "\(cleanId).json",
            enabled: scheduleEnabled
        ))
        writeAgentFiles(id: cleanId)
        isPresented = false
    }

    private func writeAgentFiles(id: String) {
        let agentsDir = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/agents", isDirectory: true)
        let heartbeatsDir = ThrawnPaths.appSupportDir.appendingPathComponent("workspace/ops/heartbeats", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: heartbeatsDir, withIntermediateDirectories: true)
            try agentContract(id: id).write(to: agentsDir.appendingPathComponent("\(id).md"), atomically: true, encoding: .utf8)
            try heartbeatContract(id: id).write(to: heartbeatsDir.appendingPathComponent("\(id).HEARTBEAT.md"), atomically: true, encoding: .utf8)
        } catch {
            FlightRecorder.logError(source: "agent-builder:write-files", message: error.localizedDescription)
        }
    }

    private func agentContract(id: String) -> String {
        """
        # \(name) (\(role))

        ## Mission
        \(purpose)

        ## Persona
        \(persona)

        ## Operating Profile
        - Autonomy: \(Int(autonomy * 100))%
        - Evidence standard: \(Int(evidence * 100))%
        - Review pressure: \(Int(review * 100))%
        - Model tier: \(explicitTier.rawValue)
        - Lifecycle: \(lifecycleMode.label)
        - Heartbeat: \(scheduleEnabled ? "hourly at :\(Int(heartbeatMinute.rounded()))" : "manual only")

        ## Tools
        \(selectedTools.sorted().map { "- `\($0)`" }.joined(separator: "\n"))

        ## Review Standard
        \(reviewStandard)

        ## Output Contract
        \(outputContract)

        ## Operating Authority
        \(boundaryNotes)
        """
    }

    private func heartbeatContract(id: String) -> String {
        """
        # \(name) Heartbeat

        You are \(name), \(role).

        ## Mission
        \(purpose)

        ## On each wake
        1. Read your agent contract at `workspace/agents/\(id).md`.
        2. Read `workspace/ops/TASK_BOARD.md`.
        3. Work only on tasks explicitly assigned to `\(name)` with status `Ready`.
        4. Use bash fences for real local work; Thrawn executes them through the shared full-operation runtime.
        5. Write task updates only to the update file provided in your preamble. Do not edit `TASK_BOARD.md` directly.

        ## Standards
        - Autonomy target: \(Int(autonomy * 100))%. \(autonomyHint)
        - Evidence target: \(Int(evidence * 100))%. \(reviewStandard)
        - Review target: \(Int(review * 100))%. \(reviewHint)
        - Output: \(outputContract)
        - Operating authority: \(boundaryNotes)

        If no task is assigned to you, reply HEARTBEAT_OK after your spoken open/close lines.
        """
    }

    private var autonomyHint: String {
        autonomy > 0.7 ? "Proceed through well-bounded work without asking for permission." :
        autonomy > 0.4 ? "Act independently inside the task, but escalate unclear scope." :
        "Prefer analysis, notes, and escalation before action."
    }

    private var reviewHint: String {
        review > 0.7 ? "Route meaningful outputs back to Thrawn for review." :
        review > 0.4 ? "Ask for review when external impact or uncertainty is present." :
        "Ship small internal updates without ceremony when proof is clear."
    }

    private var builderChrome: LinearGradient {
        LinearGradient(
            colors: [.white, Color(red: 0.82, green: 0.84, blue: 0.88), Color.ndaiGreen.opacity(0.82)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private enum AgentLifecycleMode: String, CaseIterable {
    case persistent
    case ephemeral

    var label: String {
        switch self {
        case .persistent: return "Persistent"
        case .ephemeral: return "Task Cap"
        }
    }
}

private enum AgentBuildTemplate: CaseIterable {
    case inspector
    case steward
    case maker
    case operatorRole
    case researcher
    case custom

    var title: String {
        switch self {
        case .inspector: return "INSPECT"
        case .steward: return "STEWARD"
        case .maker: return "MAKER"
        case .operatorRole: return "OPERATOR"
        case .researcher: return "RESEARCH"
        case .custom: return "CUSTOM"
        }
    }

    var subtitle: String {
        switch self {
        case .inspector: return "checks systems and returns proof"
        case .steward: return "memory, notes, synthesis"
        case .maker: return "creates assets or code"
        case .operatorRole: return "keeps workflows moving"
        case .researcher: return "finds, verifies, briefs"
        case .custom: return "blank operating shell"
        }
    }

    var icon: String {
        switch self {
        case .inspector: return "checkmark.shield.fill"
        case .steward: return "building.columns.fill"
        case .maker: return "hammer.fill"
        case .operatorRole: return "switch.2"
        case .researcher: return "magnifyingglass"
        case .custom: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .inspector: return .ndaiGreen
        case .steward: return Color(red: 0.82, green: 0.63, blue: 0.25)
        case .maker: return .chissPrimary
        case .operatorRole: return Color(red: 0.65, green: 0.72, blue: 0.78)
        case .researcher: return Color(red: 0.52, green: 0.76, blue: 0.95)
        case .custom: return Color.white.opacity(0.76)
        }
    }

    var defaultRole: String {
        switch self {
        case .inspector: return "Inspector"
        case .steward: return "Steward"
        case .maker: return "Builder"
        case .operatorRole: return "Operations Lead"
        case .researcher: return "Research Analyst"
        case .custom: return ""
        }
    }

    var persona: String {
        switch self {
        case .inspector: return "Plainspoken, practical, field-tested, allergic to theory without proof."
        case .steward: return "Patient, exacting, evidence-first, and good at turning chaos into memory."
        case .maker: return "Fast, tasteful, careful with existing systems, and focused on usable outputs."
        case .operatorRole: return "Calm, procedural, reliable, and sharp about follow-through."
        case .researcher: return "Curious, skeptical, citation-driven, and good at separating signal from noise."
        case .custom: return ""
        }
    }

    var purpose: String {
        switch self {
        case .inspector: return "Inspect assigned products or systems, capture proof, and report risks with receipts."
        case .steward: return "Maintain operating memory, summaries, notes, and source-linked briefs."
        case .maker: return "Produce assigned code, design, media, or document deliverables to a reviewable standard."
        case .operatorRole: return "Monitor queues, move tasks forward, prepare handoffs, and keep operating rhythm intact."
        case .researcher: return "Research assigned questions, verify sources, and brief Thrawn with concrete recommendations."
        case .custom: return ""
        }
    }

    var tools: [String] {
        switch self {
        case .inspector: return ["file_read", "log_read", "proof_read", "proof_write", "task_write"]
        case .steward: return ["file_read", "log_read", "memory_read", "memory_write", "summary_write", "task_write"]
        case .maker: return ["file_read", "task_write", "deliverable_write"]
        case .operatorRole: return ["file_read", "log_read", "task_write", "summary_write"]
        case .researcher: return ["file_read", "web_search", "web_scrape", "summary_write", "task_write"]
        case .custom: return ["file_read", "task_write"]
        }
    }

    var tier: ModelTier {
        switch self {
        case .inspector, .steward, .maker: return .premium
        case .operatorRole, .researcher: return .cheap
        case .custom: return .local
        }
    }

    var autonomy: Double {
        switch self {
        case .inspector: return 0.58
        case .steward: return 0.48
        case .maker: return 0.54
        case .operatorRole: return 0.62
        case .researcher: return 0.52
        case .custom: return 0.40
        }
    }

    var evidence: Double {
        switch self {
        case .inspector: return 0.86
        case .steward: return 0.92
        case .maker: return 0.70
        case .operatorRole: return 0.66
        case .researcher: return 0.88
        case .custom: return 0.60
        }
    }

    var review: Double {
        switch self {
        case .inspector: return 0.70
        case .steward: return 0.62
        case .maker: return 0.76
        case .operatorRole: return 0.54
        case .researcher: return 0.68
        case .custom: return 0.60
        }
    }

    var scheduleEnabled: Bool { self != .custom }

    var minute: Int {
        switch self {
        case .inspector: return 10
        case .steward: return 55
        case .maker: return 25
        case .operatorRole: return 35
        case .researcher: return 45
        case .custom: return 20
        }
    }

    var reviewStandard: String {
        switch self {
        case .inspector: return "Every finding cites a screenshot, command log, verdict, URL, or proof path."
        case .steward: return "Every summary cites the raw proof, log, source note, or task that supports it."
        case .maker: return "Every output includes where it lives, how it was verified, and what still needs review."
        case .operatorRole: return "Every action names the queue, owner, status change, and blocker it resolved or surfaced."
        case .researcher: return "Every claim cites source URLs or local files and distinguishes fact from inference."
        case .custom: return "Every meaningful claim cites a file, log, screenshot, proof path, or task link."
        }
    }

    var outputContract: String {
        switch self {
        case .inspector: return "Create immutable proof bundles, summarize status, and route gaps to Thrawn."
        case .steward: return "Update memory and briefs without rewriting raw evidence."
        case .maker: return "Create reviewable deliverables and register them when they are meant to be shown."
        case .operatorRole: return "Move assigned work forward through pending updates and leave a short operations note."
        case .researcher: return "Return a concise brief with sources, confidence, opportunities, and recommended next action."
        case .custom: return "Write concise heartbeat summaries, update assigned tasks through pending updates, and keep raw evidence immutable."
        }
    }

    var boundaryNotes: String {
        "Do not delete evidence, do not edit the task board directly, and escalate external-impact work to Thrawn."
    }
}

private struct BuilderPanel<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(.ndaiGreen)
                Text(title)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.76))
            }
            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.09), lineWidth: 1))
        )
    }
}

private struct BuilderMeter: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Gauge(value: value, in: 0...1) {
                EmptyView()
            } currentValueLabel: {
                Text("\(Int(value * 100))")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.86))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(color)
            Text(label)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.42))
        }
        .frame(width: 58)
    }
}

private struct KnobControl: View {
    let title: String
    @Binding var value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.045))
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                Circle()
                    .trim(from: 0, to: value)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Rectangle()
                    .fill(color)
                    .frame(width: 3, height: 24)
                    .offset(y: -19)
                    .rotationEffect(.degrees(value * 270 - 135))
                Text("\(Int(value * 100))")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.86))
            }
            .frame(width: 72, height: 72)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let center = CGPoint(x: 36, y: 36)
                    let dx = drag.location.x - center.x
                    let dy = drag.location.y - center.y
                    let radians = atan2(dy, dx)
                    var degrees = radians * 180 / .pi + 90
                    if degrees < 0 { degrees += 360 }
                    value = min(max(degrees / 360, 0), 1)
                }
            )
            Text(title)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.42))
        }
    }
}

private struct MinuteDial: View {
    @Binding var value: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.045))
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            ForEach(0..<12, id: \.self) { tick in
                Capsule()
                    .fill(Color.white.opacity(tick % 3 == 0 ? 0.45 : 0.22))
                    .frame(width: 2, height: tick % 3 == 0 ? 9 : 5)
                    .offset(y: -34)
                    .rotationEffect(.degrees(Double(tick) * 30))
            }
            Rectangle()
                .fill(Color.ndaiGreen)
                .frame(width: 3, height: 31)
                .offset(y: -15)
                .rotationEffect(.degrees((value / 60) * 360))
            Circle().fill(Color.ndaiGreen).frame(width: 8, height: 8)
        }
        .frame(width: 86, height: 86)
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { drag in
                let center = CGPoint(x: 43, y: 43)
                let dx = drag.location.x - center.x
                let dy = drag.location.y - center.y
                let radians = Double(atan2(dy, dx))
                var degrees = radians * 180 / Double.pi + 90
                if degrees < 0 { degrees += 360 }
                value = round((degrees / 360) * 59)
            }
        )
    }
}

private struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let color: Color
    var integer = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                .tracking(1.1)
                .foregroundColor(.white.opacity(0.38))
                .frame(width: 58, alignment: .leading)
            Slider(value: $value, in: range)
                .tint(color)
            Text(integer ? "\(Int(value.rounded()))" : String(format: "%.2f", value))
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.64))
                .frame(width: 38, alignment: .trailing)
        }
    }
}

private struct ToolTile: View {
    let tool: Tool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.ndaiGreen : Color.white.opacity(0.06))
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(isSelected ? .black : .white.opacity(0.58))
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.id)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.86))
                        .lineLimit(1)
                    Text(tool.description)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.38))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.ndaiGreen.opacity(0.12) : Color.white.opacity(0.035))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.ndaiGreen.opacity(0.42) : Color.white.opacity(0.09), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private var icon: String {
        if tool.id.contains("write") { return "square.and.pencil" }
        if tool.id.contains("read") { return "doc.text.magnifyingglass" }
        if tool.id.contains("web") { return "network" }
        if tool.id == "bash" { return "terminal.fill" }
        return "wrench.fill"
    }
}

// MARK: - Edit Loadout Sheet

struct EditLoadoutSheet: View {
    @EnvironmentObject var loadoutStore: StandardLoadoutStore
    @Binding var isPresented: Bool

    @State private var selectedTools: Set<String> = []
    @State private var tier: ModelTier = .local
    @State private var defaultRank: AgentRank = .b

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("EDIT STANDARD LOADOUT")
                .font(.system(size: 16, weight: .heavy, design: .serif))
                .tracking(2)
                .foregroundColor(.chissPrimary)

            Text("Every agent with inherit-mode bindings follows this loadout live. Dev-ops squad is wired to inherit.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))

            VStack(alignment: .leading, spacing: 6) {
                Text("TOOLS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1)
                    .foregroundColor(.white.opacity(0.5))
                ForEach(ToolRegistry.all, id: \.id) { tool in
                    Toggle(isOn: Binding(
                        get: { selectedTools.contains(tool.id) },
                        set: { on in
                            if on { selectedTools.insert(tool.id) }
                            else { selectedTools.remove(tool.id) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tool.id).font(.system(size: 12, weight: .bold, design: .monospaced))
                            Text(tool.description).font(.system(size: 10)).foregroundColor(.white.opacity(0.55))
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("TIER").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundColor(.white.opacity(0.5))
                Picker("", selection: $tier) {
                    ForEach(ModelTier.allCases, id: \.self) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("DEFAULT RANK").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundColor(.white.opacity(0.5))
                Picker("", selection: $defaultRank) {
                    ForEach(AgentRank.allCases, id: \.self) { r in Text(r.displayName).tag(r) }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(22)
        .frame(width: 480)
        .background(Color.obsidian)
        .onAppear {
            selectedTools = Set(loadoutStore.loadout.toolIds)
            tier = loadoutStore.loadout.tier
            defaultRank = loadoutStore.loadout.defaultRank
        }
    }

    private func save() {
        // Preserve the original order from ToolRegistry so UI listings stay stable.
        let ordered = ToolRegistry.all.map(\.id).filter { selectedTools.contains($0) }
        loadoutStore.loadout = StandardLoadout(
            toolIds: ordered,
            tier: tier,
            defaultRank: defaultRank
        )
        isPresented = false
    }
}
