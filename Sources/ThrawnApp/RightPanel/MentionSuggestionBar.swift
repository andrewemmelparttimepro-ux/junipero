import SwiftUI

// MARK: - Mention Suggestions
//
// Typing "@" in a composer offers the deployed agents from the registry, so
// summoning ARI is discoverable instead of folklore. Selecting a suggestion
// completes the token in place; the routing itself lives in ThreadStore and
// keys off the finished "@ari" text, so this bar is purely a typing aid —
// nothing breaks if it is never used.

struct MentionSuggestionBar: View {
    @Binding var text: String

    @ObservedObject private var hub = DeployedAgentHub.shared

    /// The trailing "@…" token being typed, if any.
    private var activeToken: Substring? {
        guard let last = text.split(separator: " ", omittingEmptySubsequences: false).last,
              last.hasPrefix("@"), !last.contains("\n")
        else { return nil }
        return last
    }

    private var suggestions: [DeployedAgentConfig] {
        guard let token = activeToken else { return [] }
        let typed = token.dropFirst().lowercased()
        return hub.agents.filter { agent in
            let mention = agent.mention.lowercased()
            // Offer while typing a prefix; stop once the mention is complete
            // (the space after completion also dismisses via activeToken).
            return typed.isEmpty || (mention.hasPrefix(typed) && mention != typed)
        }
    }

    var body: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(suggestions) { agent in
                    Button {
                        complete(with: agent)
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(hub.presence(for: agent).isUp ? Color.ndaiGreen : Color.white.opacity(0.25))
                                .frame(width: 6, height: 6)
                            Text("@\(agent.mention)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(Color.ndaiGreen)
                            Text("\(agent.name) · \(agent.appName) — routes this message to the deployed agent")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.62))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.ndaiGreen.opacity(0.25), lineWidth: 1)
                    )
            )
            .transition(.opacity)
        }
    }

    private func complete(with agent: DeployedAgentConfig) {
        guard let token = activeToken, let range = text.range(of: token, options: .backwards) else {
            text += "@\(agent.mention) "
            return
        }
        text.replaceSubrange(range, with: "@\(agent.mention) ")
    }
}
