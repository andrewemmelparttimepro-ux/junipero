import SwiftUI

// MARK: - Voice Control Sheet
//
// One place to see what the voice stack is actually doing: which engine is
// transcribing, which lane is answering, whether the speech-to-speech link is
// live, and the announcement rules the agents obey.

struct VoiceControlSheet: View {
    @Binding var isPresented: Bool

    @EnvironmentObject var voice: VoiceService
    @EnvironmentObject var conversation: VoiceConversationService
    @EnvironmentObject var fastLane: VoiceFastLane
    @EnvironmentObject var realtime: VoiceRealtimeService

    private var accent: Color { .ndaiGreen }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 18)

            Divider().overlay(Color.white.opacity(0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    pipelineCard
                    realtimeCard
                    announcementsCard
                    hintCard
                }
                .padding(.horizontal, 26).padding(.vertical, 18)
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 10) {
                // Caps Lock is the fast path, but a visible control makes the
                // feature discoverable and gives a way in when the hotkey is
                // remapped or unavailable.
                Button {
                    conversation.toggleThrawnVoice()
                } label: {
                    Label(conversation.isSessionActive ? "END SESSION" : "START SESSION",
                          systemImage: conversation.isSessionActive ? "stop.fill" : "mic.fill")
                        .font(.system(size: 10, weight: .black)).tracking(1)
                        .foregroundColor(conversation.isSessionActive
                                         ? Color(red: 0.95, green: 0.28, blue: 0.26)
                                         : Color(red: 0.03, green: 0.08, blue: 0.05))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(conversation.isSessionActive
                                                   ? Color.red.opacity(0.14)
                                                   : accent))
                }
                .buttonStyle(.plain)
                .disabled(voice.muted)

                Button {
                    voice.playSample(for: "thrawn")
                } label: {
                    Label("TEST VOICE", systemImage: "play.fill")
                        .font(.system(size: 10, weight: .black)).tracking(1)
                        .foregroundColor(.white.opacity(0.72))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.06))
                            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)))
                }
                .buttonStyle(.plain)
                .disabled(voice.muted)

                Spacer()

                Button { isPresented = false } label: {
                    Text("DONE")
                        .font(.system(size: 11, weight: .black)).tracking(1.4)
                        .foregroundColor(Color(red: 0.03, green: 0.08, blue: 0.05))
                        .padding(.horizontal, 22).padding(.vertical, 9)
                        .background(Capsule().fill(accent))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 26).padding(.vertical, 14)
        }
        .frame(width: 720, height: 640)
        .background(Color.obsidian)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("VOICE")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(2.6).foregroundColor(accent.opacity(0.85))
                Text("Talk to Thrawn.")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("Caps Lock opens a live session. The mic stays open — just talk, and talk over him to interrupt.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                voice.muted.toggle()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: voice.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text(voice.muted ? "MUTED" : "LIVE")
                        .font(.system(size: 8.5, weight: .black, design: .monospaced)).tracking(1.2)
                }
                .foregroundColor(voice.muted ? Color(red: 0.95, green: 0.28, blue: 0.26) : accent)
                .frame(width: 74, height: 58)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill((voice.muted ? Color.red : accent).opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke((voice.muted ? Color.red : accent).opacity(0.35), lineWidth: 1)))
            }
            .buttonStyle(.plain)
            .help(voice.muted ? "Unmute the voice layer" : "Mute all spoken output")
        }
    }

    // MARK: Cards

    private var pipelineCard: some View {
        card(title: "PIPELINE", accentColor: accent) {
            VStack(alignment: .leading, spacing: 10) {
                statRow("Session", conversation.isSessionActive ? "Active — \(conversation.mode.rawValue)" : "Idle",
                        good: conversation.isSessionActive)
                statRow("Transcription", conversation.engineLabel.isEmpty ? "on-device (resolved at session start)" : conversation.engineLabel,
                        good: !conversation.engineLabel.isEmpty)
                statRow("Last answer route", routeDescription, good: !fastLane.lastRouteLabel.isEmpty && fastLane.lastRouteLabel != "idle")
                statRow("Echo cancellation", "On — barge-in enabled", good: true)
                Text("Turns end on their own after about three quarters of a second of silence. Nothing waits for a second key press.")
                    .font(.system(size: 10.5)).foregroundColor(.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var routeDescription: String {
        switch fastLane.lastRouteLabel {
        case "instant":     return "Instant — answered from the board, no model"
        case "local":       return "Local model — conversational"
        case "local+tool":  return "Local model — ran a board tool"
        case "escalated":   return "Escalated to the command thread"
        case "idle", "":    return "Nothing spoken yet"
        default:            return fastLane.lastRouteLabel
        }
    }

    private var realtimeCard: some View {
        card(title: "SPEECH-TO-SPEECH", accentColor: realtime.isConfigured ? accent : .white.opacity(0.3)) {
            VStack(alignment: .leading, spacing: 10) {
                Text(realtime.isConfigured
                     ? "Audio goes straight to a speech-native model and comes straight back — no transcription step, no synthesis step, interruption handled by the model itself."
                     : "Not configured. Voice currently runs the local fast lane, which needs no credentials.")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)

                statRow("Status", realtime.statusText, good: realtime.isConnected)

                if realtime.isConfigured {
                    Toggle(isOn: Binding(
                        get: { realtime.preferred },
                        set: { realtime.preferred = $0 }
                    )) {
                        Text("Use speech-to-speech when available")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.82))
                    }
                    .toggleStyle(.switch)
                    .tint(accent)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TO ENABLE")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(1.6).foregroundColor(.white.opacity(0.34))
                        Text("Write your OpenAI API key to:")
                            .font(.system(size: 11)).foregroundColor(.white.opacity(0.55))
                        Text("~/Library/Application Support/Thrawn/openai-realtime-config.json")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(accent.opacity(0.85))
                            .textSelection(.enabled)
                        Text(#"as {"apiKey": "sk-…"} — or export OPENAI_API_KEY before launching. Then reopen this panel."#)
                            .font(.system(size: 10.5)).foregroundColor(.white.opacity(0.42))
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            realtime.refreshConfiguration()
                        } label: {
                            Text("RECHECK")
                                .font(.system(size: 9.5, weight: .black, design: .monospaced)).tracking(1.2)
                                .foregroundColor(.white.opacity(0.72))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(0.06))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1)))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
            }
        }
    }

    private var announcementsCard: some View {
        card(title: "AGENT ANNOUNCEMENTS", accentColor: .white.opacity(0.3)) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Heartbeat open and close lines from the stable. Separate from conversation — these stay on the built-in synthesizer so they keep working offline.")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(isOn: Binding(get: { voice.respectFocus }, set: { voice.respectFocus = $0 })) {
                    Text("Silence the stable during Focus (Thrawn still speaks)")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.82))
                }
                .toggleStyle(.switch).tint(accent)

                HStack(spacing: 10) {
                    Text("Quiet hours")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.82))
                    Spacer()
                    Text(quietHoursLabel)
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.55))
                }
            }
        }
    }

    private var quietHoursLabel: String {
        guard let start = voice.quietHoursStart, let end = voice.quietHoursEnd else { return "off" }
        return String(format: "%02d:00 – %02d:00", start, end)
    }

    private var hintCard: some View {
        card(title: "TRY SAYING", accentColor: .white.opacity(0.3)) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach([
                    "\u{201C}What's on the board?\u{201D}",
                    "\u{201C}What's blocked?\u{201D}",
                    "\u{201C}Tell me about task twenty one.\u{201D}",
                    "\u{201C}Move task twenty one to done.\u{201D}",
                    "\u{201C}Add a task for Davos to check the canaries.\u{201D}",
                    "\u{201C}Wake Dwight.\u{201D}",
                ], id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.66))
                }
                Text("Board changes obey the same autonomy ceilings as the heartbeats — if the ladder says observe, voice can read but not move cards.")
                    .font(.system(size: 10.5)).foregroundColor(.white.opacity(0.40))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: Building blocks

    private func card<Content: View>(title: String, accentColor: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                .tracking(2.2).foregroundColor(accentColor.opacity(0.9))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(0.030))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)))
    }

    private func statRow(_ label: String, _ value: String, good: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.55))
                .frame(width: 128, alignment: .leading)
            HStack(spacing: 6) {
                Circle().fill(good ? accent : Color.white.opacity(0.28)).frame(width: 6, height: 6)
                Text(value)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
