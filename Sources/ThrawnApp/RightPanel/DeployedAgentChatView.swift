import SwiftUI

// MARK: - Deployed Agent Chat
//
// The direct line to a deployed agent — Phase 1: ARI at SPAS 360. Mirrors
// SpecialistChatView's chrome so the stable feels like one room, but the
// transcript is backed by the deployed app's own agent runtime instead of a
// local gateway session: every reply here came from the same brain, threads,
// and Citadel the SPAS 360 sales floor uses.

struct DeployedAgentChatView: View {
    let agent: DeployedAgentConfig

    @EnvironmentObject var nav: ConsoleNavigationStore
    @ObservedObject private var hub = DeployedAgentHub.shared

    @State private var draft = ""
    @State private var showIntelligence = false
    @FocusState private var composerFocused: Bool

    private var presence: DeployedAgentPresence { hub.presence(for: agent) }

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            composer
        }
        .background(Color.obsidian.ignoresSafeArea())
        .onAppear {
            hub.refreshPresence()
            composerFocused = true
        }
    }

    // MARK: Header — same chrome as SpecialistChatView

    private var header: some View {
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
                    .foregroundColor(Color.ndaiGreen)
                    .shadow(color: Color.ndaiGreen.opacity(0.40), radius: 8)
                Text("Deployed · \(agent.appName) · \(agent.baseURL.host ?? "")")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.40))
            }

            Spacer()

            // Where the intelligence is running right now — read live from
            // his status card, not assumed.
            Text(presence.detailLine.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.2)
                .foregroundColor(presence.activityState.chissColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(presence.activityState.chissColor.opacity(0.12))
                        .overlay(Capsule().stroke(presence.activityState.chissColor.opacity(0.35), lineWidth: 1))
                )

            // The control plane: which brain answers, and the pause switch.
            // Writes the same agent_config row api/chat.ts reads per request,
            // so a change here steers the deployed agent with no redeploy.
            Button {
                showIntelligence.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11, weight: .bold))
                    Text("INTELLIGENCE")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.2)
                }
                .foregroundColor(Color.ndaiGreen.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.ndaiGreen.opacity(0.10))
                        .overlay(Capsule().stroke(Color.ndaiGreen.opacity(0.35), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showIntelligence, arrowEdge: .bottom) {
                intelligencePanel
            }

            Menu {
                Button("New conversation") { hub.clearConversation(for: agent) }
                Link("Open \(agent.appName)", destination: agent.baseURL)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.55))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.obsidianMid.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle().fill(presence.activityState.chissColor.opacity(0.15)).frame(height: 1)
        }
    }

    // MARK: Intelligence panel

    private var intelligencePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(agent.name.uppercased())'S INTELLIGENCE")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(1.8)
                .foregroundColor(.secondary)

            ForEach(hub.intelligenceOptions(for: agent)) { option in
                let isCurrent = hub.control(for: agent)?.provider == option.provider
                    && hub.control(for: agent)?.model == option.model
                Button {
                    hub.setIntelligence(for: agent, option: option)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(isCurrent ? Color.ndaiGreen : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.label)
                                .font(.system(size: 12, weight: .semibold))
                            if let note = option.note {
                                Text(note)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!option.available)
                .opacity(option.available ? 1 : 0.45)
            }

            Divider()

            Toggle(isOn: Binding(
                get: { hub.control(for: agent)?.enabled ?? true },
                set: { hub.setEnabled(for: agent, enabled: $0) }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(agent.name) is on duty")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Off pauses him everywhere — the store, the site, and here.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if let error = hub.configError(for: agent) {
                Text(error)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Color(red: 0.95, green: 0.45, blue: 0.35))
            }

            Text("Changes apply to the next message — no redeploy.")
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(width: 280)
        .onAppear { hub.refreshPresence() }
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if hub.conversation(for: agent).isEmpty {
                        emptyState
                    }
                    ForEach(hub.conversation(for: agent)) { message in
                        bubble(for: message)
                            .id(message.id)
                    }
                    if hub.isThinking(agent) {
                        thinkingRow.id("thinking")
                    }
                }
                .padding(16)
            }
            .onChange(of: hub.conversation(for: agent).count) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    if let last = hub.conversation(for: agent).last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: hub.isThinking(agent)) { thinking in
                if thinking {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("thinking", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            AgentPixelAvatar(
                agentId: agent.id,
                agentName: agent.name,
                state: presence.activityState,
                size: 64
            )
            Text("This is the real \(agent.name) — the one the \(agent.appName) team talks to.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.white.opacity(0.70))
            Text("Live org data, same memory, same audit trail.")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    @ViewBuilder
    private func bubble(for message: DeployedChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .font(.system(size: 12.5))
                    .foregroundColor(.white.opacity(0.94))
                    .textSelection(.enabled)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Color.chissDeep.opacity(0.72))
                    )
            }
        case .agent:
            HStack(alignment: .top, spacing: 8) {
                AgentPixelAvatar(
                    agentId: agent.id,
                    agentName: agent.name,
                    state: .idle,
                    size: 22
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey(message.text))
                        .font(.system(size: 12.5))
                        .foregroundColor(.white.opacity(0.90))
                        .textSelection(.enabled)
                    if let artifactTitle = message.artifactTitle {
                        Link(destination: agent.baseURL) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.badge.arrow.up")
                                    .font(.system(size: 10, weight: .bold))
                                Text("\(artifactTitle) — saved in \(agent.appName)")
                                    .font(.system(size: 10.5, weight: .semibold))
                            }
                            .foregroundColor(Color.ndaiGreen.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.ndaiGreen.opacity(0.10))
                                    .overlay(Capsule().stroke(Color.ndaiGreen.opacity(0.30), lineWidth: 1))
                            )
                        }
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )
                Spacer(minLength: 60)
            }
        case .notice:
            Text(message.text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.40).opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("\(agent.name) is working…")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.white.opacity(0.50))
            Spacer()
        }
        .padding(.horizontal, 6)
    }

    // MARK: Composer

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message \(agent.name) — live at \(agent.appName)…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(1...5)
                .focused($composerFocused)
                .onSubmit(send)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.ndaiGreen.opacity(composerFocused ? 0.35 : 0.12), lineWidth: 1)
                        )
                )

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hub.isThinking(agent)
                            ? Color.white.opacity(0.20)
                            : Color.ndaiGreen
                    )
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hub.isThinking(agent))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.obsidianMid.opacity(0.92))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    private func send() {
        let text = draft
        draft = ""
        hub.send(to: agent, text: text)
    }
}
