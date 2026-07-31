import SwiftUI

enum AgentGatewayPickerStyle {
    case rail
    case header
    case thread
    case dossier
    case account
}

/// One gateway control used anywhere an agent identity is represented.
///
/// The picker owns no route state. It reads and writes AgentSpecStore, which
/// means the stable, left rail, headers, and active conversations all redraw
/// from the same persisted selection.
struct AgentGatewayPicker: View {
    @EnvironmentObject private var specStore: AgentSpecStore
    @EnvironmentObject private var agentRuntime: AgentRuntimeCoordinator

    let agentID: String
    let style: AgentGatewayPickerStyle

    private var backend: ProviderBackend {
        specStore.subscriptionGateway(forAgentId: agentID)
    }

    private var isLocked: Bool {
        agentID == "steven"
    }

    var body: some View {
        Group {
            if isLocked {
                pickerLabel(showsChevron: false, showsLock: true)
                    .accessibilityLabel("Grok gateway, locked for Steven")
            } else {
                Menu {
                    ForEach(StableGatewayPolicy.selectableGateways, id: \.self) { candidate in
                        Button {
                            select(candidate)
                        } label: {
                            if candidate == backend {
                                Label(candidate.gatewayDisplayName, systemImage: "checkmark")
                            } else {
                                Text(candidate.gatewayDisplayName)
                            }
                        }
                    }
                } label: {
                    pickerLabel(showsChevron: true, showsLock: false)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("\(displayName(backend)) gateway for \(agentID)")
                .accessibilityHint("Choose which signed-in subscription brain this agent uses")
            }
        }
        .help(isLocked
              ? "Steven stays on Grok"
              : "Switch this agent's brain without changing its identity or local conversation")
    }

    private func select(_ candidate: ProviderBackend) {
        guard specStore.setSubscriptionGateway(candidate, forAgentId: agentID) else {
            return
        }
        Task {
            // Status refresh only. Selecting a brain never launches sign-in.
            await agentRuntime.refresh(agentID: agentID, backend: candidate)
        }
    }

    @ViewBuilder
    private func pickerLabel(showsChevron: Bool, showsLock: Bool) -> some View {
        switch style {
        case .rail:
            HStack(spacing: 4) {
                Text(shortName(backend))
                    .font(.system(size: 9.5, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .lineLimit(1)
                pickerGlyph(showsChevron: showsChevron, showsLock: showsLock, size: 7)
            }
            .foregroundColor(.white.opacity(0.94))
            .padding(.horizontal, 9)
            .frame(height: 21)
            .background(
                Capsule()
                    .fill(Color(red: 0.025, green: 0.065, blue: 0.090))
                    .overlay(
                        Capsule().stroke(
                            agentID == "steven"
                                ? Color.orange.opacity(0.48)
                                : Color.chissPrimary.opacity(0.72),
                            lineWidth: 1
                        )
                    )
            )
            .shadow(
                color: agentID == "steven"
                    ? Color.orange.opacity(0.18)
                    : Color.chissPrimary.opacity(0.28),
                radius: 4
            )

        case .header:
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 10, weight: .bold))
                Text(shortName(backend))
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(0.9)
                pickerGlyph(showsChevron: showsChevron, showsLock: showsLock, size: 7)
            }
            .foregroundColor(Color.chissPrimary.opacity(0.92))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                Capsule()
                    .fill(Color.chissDeep.opacity(0.52))
                    .overlay(Capsule().stroke(Color.chissPrimary.opacity(0.34), lineWidth: 1))
            )

        case .thread:
            HStack(spacing: 5) {
                Text("THRAWN · \(shortName(backend))")
                    .font(.system(size: 9.5, weight: .black, design: .rounded))
                    .tracking(0.8)
                pickerGlyph(showsChevron: showsChevron, showsLock: showsLock, size: 7)
            }
            .foregroundColor(.white.opacity(0.92))
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
            )

        case .dossier:
            HStack(spacing: 5) {
                Text(shortName(backend))
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.84))
                    .lineLimit(1)
                pickerGlyph(showsChevron: showsChevron, showsLock: showsLock, size: 9)
            }
            .frame(minWidth: 78, alignment: .leading)

        case .account:
            HStack(spacing: 6) {
                Text(backend.gatewayDisplayName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.86))
                pickerGlyph(showsChevron: showsChevron, showsLock: showsLock, size: 8)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private func pickerGlyph(
        showsChevron: Bool,
        showsLock: Bool,
        size: CGFloat
    ) -> some View {
        if showsLock {
            Image(systemName: "lock.fill")
                .font(.system(size: size, weight: .bold))
                .foregroundColor(Color.orange.opacity(0.82))
        } else if showsChevron {
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: size, weight: .bold))
                .foregroundColor(Color.chissPrimary.opacity(0.84))
        }
    }

    private func shortName(_ provider: ProviderBackend) -> String {
        switch provider {
        case .codex: return "OPENAI"
        case .grok: return "GROK"
        case .claude: return "CLAUDE"
        case .xai: return "XAI API"
        case .openai: return "API"
        case .openclaw: return "OPENCLAW"
        case .ollama: return "OLLAMA"
        }
    }

    private func displayName(_ provider: ProviderBackend) -> String {
        switch provider {
        case .codex: return "OpenAI"
        case .grok: return "Grok"
        case .claude: return "Claude"
        case .xai: return "xAI API"
        case .openai: return "OpenAI-compatible API"
        case .openclaw: return "OpenClaw"
        case .ollama: return "Ollama"
        }
    }
}
