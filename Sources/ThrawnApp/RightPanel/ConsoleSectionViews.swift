import SwiftUI

struct ConsoleSectionSwitcher: View {
    @EnvironmentObject var nav: ConsoleNavigationStore

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ConsoleSection.allCases) { section in
                Button { nav.selectedSection = section; nav.dismissAgent() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: section.icon)
                            .font(.system(size: 10, weight: .bold))
                        Text(section.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(nav.selectedSection == section ? .white : Color.white.opacity(0.55))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(nav.selectedSection == section ? Color.chissDeep : Color.white.opacity(0.05))
                            .overlay(
                                Capsule().stroke(
                                    nav.selectedSection == section ? Color.chissPrimary.opacity(0.55) : Color.clear,
                                    lineWidth: 1
                                )
                            )
                    )
                    .shadow(color: nav.selectedSection == section ? Color.chissPrimary.opacity(0.20) : .clear, radius: 6)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ConsoleSectionBody: View {
    @EnvironmentObject var nav: ConsoleNavigationStore
    @EnvironmentObject var threadStore: ThreadStore
    @EnvironmentObject var roster: AgentRosterStore

    var body: some View {
        // If a specialist agent is selected, show their dedicated chat session
        if let agentId = nav.selectedAgentId,
           let agent = roster.agents.first(where: { $0.id == agentId }) {
            SpecialistChatView(agent: agent)
        } else {
            switch nav.selectedSection {
            case .command:
                CommandTabView()
            case .threads:
                ThreadListView()
            case .tasks:
                FlowBoardView(embedded: true)
            case .review:
                ReviewQueueView()
            case .approvals:
                ApprovalsView()
            case .deliverables:
                DeliverablesView()
            }
        }
    }
}

// MARK: - Specialist Agent Chat

struct SpecialistChatView: View {
    let agent: AgentStatus
    @EnvironmentObject var nav: ConsoleNavigationStore

    var body: some View {
        VStack(spacing: 0) {
            // Agent session header
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.28)) {
                        nav.dismissAgent()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text("Back")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Color.chissPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color.chissDeep.opacity(0.55))
                            .overlay(Capsule().stroke(Color.chissPrimary.opacity(0.35), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name.uppercased())
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .tracking(2)
                        .foregroundColor(Color.chissPrimary)
                        .shadow(color: Color.chissPrimary.opacity(0.40), radius: 8)
                    Text("\(agent.role) • \(agent.sessionKey)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.40))
                }

                Spacer()

                // Agent state badge
                Text(agent.state.label.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.2)
                    .foregroundColor(agent.state.chissColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(agent.state.chissColor.opacity(0.12))
                            .overlay(Capsule().stroke(agent.state.chissColor.opacity(0.35), lineWidth: 1))
                    )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.obsidianMid.opacity(0.92))
            .overlay(alignment: .bottom) {
                Rectangle().fill(agent.state.chissColor.opacity(0.15)).frame(height: 1)
            }

            // The chat view targeting this agent's session key
            PrimarySessionView(
                sessionKey: agent.sessionKey,
                agentName: agent.name,
                agentInitial: agentInitial(for: agent)
            )
        }
    }

    private func agentInitial(for agent: AgentStatus) -> String {
        switch agent.id {
        case "thrawn":  return "T"
        case "r2d2":    return "R2"
        case "c3po":    return "3P"
        case "quigon":  return "QG"
        case "lando":   return "L"
        case "boba":    return "BF"
        default:        return String(agent.name.prefix(1))
        }
    }
}

// MARK: - Command Tab: Recent Threads + Selected Thread Detail

struct CommandTabView: View {
    @EnvironmentObject var threadStore: ThreadStore

    private var recentThreads: [ChatThread] {
        Array(threadStore.threads.sorted { $0.updatedAt > $1.updatedAt }.prefix(10))
    }

    var body: some View {
        ZStack {
            Color.obsidian.ignoresSafeArea()

            if let selectedId = threadStore.selectedThreadId {
                ThreadDetailView(threadId: selectedId)
                    .padding(12)
                    .transition(.opacity)
            } else if recentThreads.isEmpty {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.chissDeep)
                            .frame(width: 64, height: 64)
                            .shadow(color: Color.chissPrimary.opacity(0.40), radius: 18)
                        Text("T")
                            .font(.system(size: 32, weight: .bold, design: .serif))
                            .foregroundColor(Color.chissPrimary)
                    }
                    Text("Thrawn Command Console")
                        .font(.system(size: 17, weight: .bold, design: .serif))
                        .tracking(2)
                        .foregroundColor(Color.chissPrimary)
                        .shadow(color: Color.chissPrimary.opacity(0.40), radius: 10)
                    Text("Click the Command button to start a conversation.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.40))
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(recentThreads) { thread in
                            ThreadCard(thread: thread)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        threadStore.selectedThreadId = thread.id
                                        threadStore.markThreadRead(thread.id)
                                    }
                                }
                                .contextMenu {
                                    if thread.state == .failed {
                                        Button("Retry") { threadStore.retryThread(thread.id) }
                                    }
                                    if thread.isLoading {
                                        Button("Cancel") { threadStore.cancelRequest(for: thread.id) }
                                    }
                                    Button("Delete") { threadStore.deleteThread(thread.id) }
                                }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: threadStore.selectedThreadId)
    }
}

private struct ConsoleInfoPanel: View {
    let title: String
    let subtitle: String
    let bullets: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundColor(.white.opacity(0.95))
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.white.opacity(0.68))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(bullets, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(Color(red: 0.32, green: 0.52, blue: 1.0)).frame(width: 7, height: 7).padding(.top, 5)
                        Text(item)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.84))
                    }
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
        .padding(12)
    }
}
