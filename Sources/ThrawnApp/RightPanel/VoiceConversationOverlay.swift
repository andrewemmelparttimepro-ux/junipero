import SwiftUI

struct VoiceConversationOverlay: View {
    @EnvironmentObject var voiceChat: VoiceConversationService

    private var hintText: String {
        switch voiceChat.mode {
        case .listening: return "Just talk — I'll answer when you stop."
        case .thinking:  return "Working on it."
        case .speaking:  return "Talk over me to interrupt."
        case .idle:      return "Caps Lock starts a session."
        }
    }

    var body: some View {
        if voiceChat.isSessionActive || !voiceChat.transcript.isEmpty || voiceChat.lastErrorText != nil {
            HStack(spacing: 12) {
                VoiceLevelGlyph(level: voiceChat.audioLevel, isListening: voiceChat.mode == .listening)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(voiceChat.statusText)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(.white.opacity(0.86))
                        if !voiceChat.routeLabel.isEmpty, voiceChat.routeLabel != "idle" {
                            Text(voiceChat.routeLabel.uppercased())
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .tracking(1.1)
                                .foregroundColor(Color.ndaiGreen.opacity(0.85))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(Color.ndaiGreen.opacity(0.12)))
                        }
                    }
                    Text(voiceChat.lastErrorText ?? (voiceChat.transcript.isEmpty ? hintText : voiceChat.transcript))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(voiceChat.lastErrorText == nil ? .white.opacity(0.52) : Color.sithGlow.opacity(0.86))
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    voiceChat.dismissOverlay()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.66))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help(voiceChat.isSessionActive ? "End voice session" : "Dismiss voice message")
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: 520)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.obsidianMid.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke((voiceChat.mode == .listening ? Color.ndaiGreen : Color.chissPrimary).opacity(0.26), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 10)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

private struct VoiceLevelGlyph: View {
    let level: Double
    let isListening: Bool

    private var bars: [Double] {
        [0.28, 0.52, 0.84, 0.64, 0.38]
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, base in
                Capsule()
                    .fill(isListening ? Color.ndaiGreen : Color.chissPrimary)
                    .frame(width: 3.5, height: barHeight(base: base, index: index))
                    .opacity(isListening ? 0.95 : 0.48)
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .frame(width: 34, height: 34)
        .background(
            Circle()
                .fill(isListening ? Color.ndaiGreen.opacity(0.16 + min(level, 1) * 0.16) : Color.chissPrimary.opacity(0.12))
        )
        .overlay(
            Circle()
                .stroke((isListening ? Color.ndaiGreen : Color.chissPrimary).opacity(0.22 + min(level, 1) * 0.34), lineWidth: 1)
        )
        .shadow(color: isListening ? Color.ndaiGreen.opacity(0.18 + min(level, 1) * 0.28) : .clear, radius: 8)
    }

    private func barHeight(base: Double, index: Int) -> CGFloat {
        guard isListening else { return CGFloat(8 + base * 8) }
        let emphasis = 0.35 + (sin(Double(index) * 1.7) + 1.0) * 0.18
        return CGFloat(7 + base * 8 + min(1, level) * (14 + emphasis * 8))
    }
}
