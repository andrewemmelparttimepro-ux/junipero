import SwiftUI

// MARK: - Agents Console (Right Panel — Full Fleet Roster)
//
// Scrollable roster of all agents, matching the left panel's card
// aesthetics. OG dev-ops squad as larger featured cards at top,
// V2/pool agents below. Cards are draggable to left panel slots.

struct AgentsConsoleView: View {
    @EnvironmentObject var roster: AgentRosterStore
    @EnvironmentObject var specStore: AgentSpecStore
    @EnvironmentObject var loadoutStore: StandardLoadoutStore
    @EnvironmentObject var rankEvaluator: RankEvaluator
    @EnvironmentObject var nav: ConsoleNavigationStore

    @State private var showSpawn = false
    @State private var showEditLoadout = false

    private var coreAgents: [AgentStatus] {
        roster.agents.filter { coreAgentIds.contains($0.id) }
    }

    private var v2Agents: [AgentStatus] {
        roster.agents.filter { !coreAgentIds.contains($0.id) }
    }

    var body: some View {
        ZStack {
            Color.obsidian.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    fleetHeader
                    controlsRow

                    // ── DEV-OPS SQUAD ─────────────────────────────
                    sectionDivider("DEV-OPS SQUAD", color: .chissPrimary)

                    VStack(spacing: 10) {
                        ForEach(coreAgents) { agent in
                            FeaturedAgentCard(
                                agent: agent,
                                spec: specStore.specs.first(where: { $0.id == agent.id }),
                                score: rankEvaluator.scores[agent.id],
                                resolvedTools: specStore.resolvedTools(forAgentId: agent.id),
                                isPinned: nav.pinnedLeftPanelAgents.contains(agent.id),
                                onTap: { selectAgent(agent) }
                            )
                            .onDrag { NSItemProvider(object: agent.id as NSString) }
                        }
                    }

                    // ── AGENT POOL ─────────────────────────────────
                    if !v2Agents.isEmpty {
                        sectionDivider("AGENT POOL", color: Color(red: 0.98, green: 0.72, blue: 0.18))

                        VStack(spacing: 8) {
                            ForEach(v2Agents) { agent in
                                PoolAgentCard(
                                    agent: agent,
                                    spec: specStore.specs.first(where: { $0.id == agent.id }),
                                    isPinned: nav.pinnedLeftPanelAgents.contains(agent.id),
                                    onTap: { selectAgent(agent) }
                                )
                                .onDrag { NSItemProvider(object: agent.id as NSString) }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .sheet(isPresented: $showSpawn) {
            SpawnAgentSheet(isPresented: $showSpawn)
                .environmentObject(specStore)
        }
        .sheet(isPresented: $showEditLoadout) {
            EditLoadoutSheet(isPresented: $showEditLoadout)
                .environmentObject(loadoutStore)
        }
    }

    // MARK: Fleet Header

    private var fleetHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.chissPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("AGENT FLEET")
                    .font(.system(size: 13, weight: .heavy, design: .serif))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.90))
                Text("Drag agents to the left panel for quick access")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.40))
            }
            Spacer()
            Text("\(roster.agents.count)")
                .font(.system(size: 18, weight: .black, design: .monospaced))
                .foregroundColor(Color.chissPrimary.opacity(0.55))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.obsidianMid.opacity(0.80))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.chissPrimary.opacity(0.15), lineWidth: 1)
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
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(LinearGradient(colors: [.chissPrimary, .chissDeep], startPoint: .top, endPoint: .bottom))
                        .shadow(color: Color.chissPrimary.opacity(0.25), radius: 6)
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
                .foregroundColor(color.opacity(0.55))
            Rectangle().fill(color.opacity(0.15)).frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private func selectAgent(_ agent: AgentStatus) {
        withAnimation(.spring(response: 0.28)) {
            nav.selectedAgentId = agent.id
        }
    }
}

// MARK: - Featured Agent Card (OG Dev-Ops — Larger)

private struct FeaturedAgentCard: View {
    let agent: AgentStatus
    let spec: AgentSpec?
    let score: AgentScore?
    let resolvedTools: [String]
    let isPinned: Bool
    let onTap: () -> Void

    private var accentColor: Color { Color.chissPrimary }

    var body: some View {
        ZStack(alignment: .leading) {
            // Card background
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.038))

            // Left accent stripe
            HStack(spacing: 0) {
                Rectangle()
                    .fill(accentColor.opacity(0.55))
                    .frame(width: 3)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Border
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(agent.state.chissColor.opacity(0.25), lineWidth: 1)

            // Content
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    AgentPixelAvatar(
                        agentId: agent.id,
                        agentName: agent.name,
                        state: agent.state,
                        size: 52
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(agent.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color.white.opacity(0.95))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(agent.role)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(agent.state.chissColor.opacity(0.85))
                                .lineLimit(1)
                        }
                        HStack(spacing: 8) {
                            Text(agent.state.label.uppercased())
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(1.6)
                                .foregroundColor(agent.state.chissColor.opacity(0.75))
                            HeartbeatCountdownBadge(owner: agent.id, compact: true)
                            Spacer()
                            if isPinned {
                                pinnedBadge(color: .chissPrimary)
                            }
                        }
                        Text(agent.detail)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.50))
                            .lineLimit(2)
                    }
                }

                // Persona — only on featured cards
                if let spec = spec {
                    Text(spec.persona)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.38))
                        .lineLimit(2)
                }

                // Tools & score row
                HStack(spacing: 6) {
                    ForEach(resolvedTools.prefix(5), id: \.self) { tool in
                        toolCapsule(tool)
                    }
                    Spacer()
                    if let score = score {
                        Text("\(score.score)")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(scoreColor(score.score))
                    }
                    // Drag handle hint
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.15))
                }
            }
            .padding(.leading, 15)
            .padding(.trailing, 12)
            .padding(.vertical, 14)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onTap)
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 90 { return .green }
        if score >= 75 { return .chissPrimary }
        if score >= 55 { return .orange }
        return .sithGlow
    }

    private func toolCapsule(_ tool: String) -> some View {
        Text(tool)
            .font(.system(size: 8, weight: .heavy, design: .monospaced))
            .foregroundColor(Color.white.opacity(0.55))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.04))
                    .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
            )
    }

    private func pinnedBadge(color: Color) -> some View {
        Text("PINNED")
            .font(.system(size: 7.5, weight: .black))
            .tracking(1.5)
            .foregroundColor(color.opacity(0.55))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color.opacity(0.08))
                    .overlay(Capsule().stroke(color.opacity(0.20), lineWidth: 0.5))
            )
    }
}

// MARK: - Pool Agent Card (V2 — Normal Size)

private struct PoolAgentCard: View {
    let agent: AgentStatus
    let spec: AgentSpec?
    let isPinned: Bool
    let onTap: () -> Void

    private var accentColor: Color {
        Color(red: 0.98, green: 0.72, blue: 0.18)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Card background
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.032))

            // Left accent stripe — amber for V2
            HStack(spacing: 0) {
                Rectangle()
                    .fill(accentColor.opacity(0.45))
                    .frame(width: 3)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Border
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(agent.state.chissColor.opacity(0.18), lineWidth: 1)

            // Content
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
                            .foregroundColor(Color.white.opacity(0.90))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(agent.role)
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(agent.state.chissColor.opacity(0.80))
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        Text(agent.state.label.uppercased())
                            .font(.system(size: 8.5, weight: .heavy))
                            .tracking(1.6)
                            .foregroundColor(agent.state.chissColor.opacity(0.70))
                        HeartbeatCountdownBadge(owner: agent.id, compact: true)
                        Spacer()
                        if isPinned {
                            Text("PINNED")
                                .font(.system(size: 7, weight: .black))
                                .tracking(1.2)
                                .foregroundColor(accentColor.opacity(0.50))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(accentColor.opacity(0.06))
                                        .overlay(Capsule().stroke(accentColor.opacity(0.18), lineWidth: 0.5))
                                )
                        }
                        // Drag handle hint
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.12))
                    }
                    Text(agent.detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            .padding(.leading, 13)
            .padding(.trailing, 10)
            .padding(.vertical, 10)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Spawn Sheet

struct SpawnAgentSheet: View {
    @EnvironmentObject var specStore: AgentSpecStore
    @Binding var isPresented: Bool

    @State private var id: String = ""
    @State private var name: String = ""
    @State private var role: String = ""
    @State private var persona: String = ""
    @State private var purpose: String = ""
    @State private var ephemeral: Bool = false
    @State private var taskBudget: String = "5"
    @State private var inheritTools: Bool = true
    @State private var inheritTier: Bool = true
    @State private var explicitTier: ModelTier = .local

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SPAWN AGENT")
                .font(.system(size: 16, weight: .heavy, design: .serif))
                .tracking(2)
                .foregroundColor(.chissPrimary)

            Text("New agents inherit from the Standard Loadout by default. Change the loadout and inheriting agents follow automatically.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))

            Group {
                labeled("ID (stable, lowercase)") {
                    TextField("jane-doe", text: $id).textFieldStyle(.roundedBorder)
                }
                labeled("Display name") {
                    TextField("Jane Doe", text: $name).textFieldStyle(.roundedBorder)
                }
                labeled("Role") {
                    TextField("Growth Lead", text: $role).textFieldStyle(.roundedBorder)
                }
                labeled("Persona") {
                    TextField("Direct, data-driven, loves A/B tests.", text: $persona).textFieldStyle(.roundedBorder)
                }
                labeled("Purpose") {
                    TextField("Own acquisition funnel experiments.", text: $purpose).textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 14) {
                Toggle("Inherit tools from loadout", isOn: $inheritTools)
                Toggle("Inherit tier from loadout", isOn: $inheritTier)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.8))

            if !inheritTier {
                labeled("Tier override") {
                    Picker("", selection: $explicitTier) {
                        ForEach(ModelTier.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            HStack(spacing: 14) {
                Toggle("Ephemeral", isOn: $ephemeral)
                if ephemeral {
                    TextField("Task budget", text: $taskBudget)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.8))

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Spawn") { spawn() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(id.isEmpty || name.isEmpty)
            }
            .padding(.top, 8)
        }
        .padding(22)
        .frame(width: 520)
        .background(Color.obsidian)
    }

    private func labeled<V: View>(_ label: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1)
                .foregroundColor(.white.opacity(0.5))
            content()
        }
    }

    private func spawn() {
        let cleanId = id.lowercased().replacingOccurrences(of: " ", with: "-")
        let lifecycle: AgentLifecycle = ephemeral
            ? .ephemeral(taskBudget: Int(taskBudget) ?? 5)
            : .persistent
        let spec = AgentSpec(
            id: cleanId,
            name: name,
            role: role,
            persona: persona,
            purpose: purpose,
            tools: inheritTools ? .inherit : .explicit(["bash", "file_read", "task_write"]),
            tier: inheritTier ? .inherit : .explicit(explicitTier),
            rank: .c,
            pinned: false,
            lifecycle: lifecycle,
            knowledgeDir: "workspace/agents/\(cleanId)/knowledge",
            tasksCompleted: 0,
            createdAt: Date()
        )
        specStore.upsert(spec)
        AgentSpecStore.ensureKnowledgeDirs(for: [spec])
        isPresented = false
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
