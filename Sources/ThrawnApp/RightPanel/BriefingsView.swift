import SwiftUI

// MARK: - Briefings View (SOD / EOD Audio Dex)
//
// The giant play button lives here. Each half of the day gets its own
// panel with a single huge play control that fires every active agent's
// self-briefing audio back-to-back — Thrawn first, then by rank.
//
// Below the play controls, a card list shows each briefing with the
// agent's grade, their one-sentence improvement pledge, and a click
// target that reveals the audio/text file in Finder.

struct BriefingsView: View {
    @EnvironmentObject var briefings: BriefingService
    @EnvironmentObject var specStore: AgentSpecStore

    var body: some View {
        ZStack {
            Color.obsidian.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerPanel

                    HStack(spacing: 16) {
                        giantPlayCard(kind: .sod)
                        giantPlayCard(kind: .eod)
                    }

                    if briefings.latestSOD.isEmpty && briefings.latestEOD.isEmpty {
                        emptyState
                    } else {
                        if !briefings.latestSOD.isEmpty {
                            briefingList(title: "Start of Day", entries: briefings.latestSOD)
                        }
                        if !briefings.latestEOD.isEmpty {
                            briefingList(title: "End of Day", entries: briefings.latestEOD)
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: - Header

    private var headerPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.chissPrimary)
                Text("SOD / EOD BRIEFINGS")
                    .font(.system(size: 14, weight: .heavy, design: .serif))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                Button {
                    briefings.revealInFinder(kind: .sod)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Reveal in Finder")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.chissPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.chissDeep.opacity(0.35))
                            .overlay(Capsule().stroke(Color.chissPrimary.opacity(0.35), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
            }
            Text("Every active agent produces a self-review twice a day. SOD fires at 07:00 with today's plan. EOD fires at 19:00 with yesterday's review. Audio files land in ~/Desktop/Thrawn Briefings.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.obsidianMid)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.chissPrimary.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Giant play card

    private func giantPlayCard(kind: BriefingKind) -> some View {
        let isKindSOD = (kind == .sod)
        let title = isKindSOD ? "START OF DAY" : "END OF DAY"
        let subtitle = isKindSOD ? "Today's plan • 07:00" : "Yesterday's review • 19:00"
        let entries = isKindSOD ? briefings.latestSOD : briefings.latestEOD
        let ready = entries.contains { $0.audioPath != nil }
        let isThisKindPlaying = briefings.isPlaying && entries.contains { $0.agentId == briefings.currentlyPlayingAgentId }

        return VStack(spacing: 14) {
            // Title row
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .heavy, design: .serif))
                    .tracking(2.5)
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text("\(entries.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.chissPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.chissDeep.opacity(0.55))
                            .overlay(Capsule().stroke(Color.chissPrimary.opacity(0.35), lineWidth: 1))
                    )
            }

            // The giant play button itself
            Button {
                if isThisKindPlaying {
                    briefings.stopPlayback()
                } else {
                    briefings.playAll(kind: kind)
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: ready
                                    ? [Color.chissPrimary.opacity(0.35), Color.chissDeep.opacity(0.9)]
                                    : [Color.white.opacity(0.04), Color.obsidianMid],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .overlay(
                            Circle().stroke(
                                ready ? Color.chissPrimary.opacity(0.55) : Color.white.opacity(0.12),
                                lineWidth: 2
                            )
                        )
                        .shadow(
                            color: ready ? Color.chissPrimary.opacity(0.35) : .clear,
                            radius: 18
                        )
                    Image(systemName: isThisKindPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 56, weight: .black))
                        .foregroundColor(ready ? .white : Color.white.opacity(0.25))
                        .offset(x: isThisKindPlaying ? 0 : 4) // nudge play triangle so it looks centered
                }
                .frame(width: 140, height: 140)
            }
            .buttonStyle(.plain)
            .disabled(!ready && !isThisKindPlaying)

            // Subtitle + generate-now
            VStack(spacing: 6) {
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))

                Button {
                    Task { await briefings.generate(kind: kind) }
                } label: {
                    HStack(spacing: 6) {
                        if briefings.isGenerating {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text(briefings.isGenerating ? "Generating…" : "Generate now")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.chissPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color.chissDeep.opacity(0.35))
                            .overlay(Capsule().stroke(Color.chissPrimary.opacity(0.35), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .disabled(briefings.isGenerating)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.obsidianMid)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.chissPrimary.opacity(0.18), lineWidth: 1)
                )
        )
    }

    // MARK: - Briefing list

    private func briefingList(title: String, entries: [BriefingEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .serif))
                .tracking(2.5)
                .foregroundColor(.white.opacity(0.65))

            ForEach(entries) { entry in
                BriefingRow(
                    entry: entry,
                    isPlaying: briefings.currentlyPlayingAgentId == entry.agentId
                )
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color.chissPrimary.opacity(0.35))
            Text("No briefings yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
            Text("Hit Generate now on either card to produce a briefing for today, or wait for the 07:00 / 19:00 scheduled runs.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - BriefingRow

private struct BriefingRow: View {
    let entry: BriefingEntry
    let isPlaying: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Agent name + grade chip
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.agentName.uppercased())
                        .font(.system(size: 12, weight: .heavy, design: .serif))
                        .tracking(1.3)
                        .foregroundColor(isPlaying ? .chissPrimary : .white.opacity(0.85))
                    if isPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.chissPrimary)
                    }
                }
                Text(entry.improvement)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(2)
            }

            Spacer()

            // Grade chip
            Text(entry.grade)
                .font(.system(size: 13, weight: .black, design: .serif))
                .foregroundColor(.chissPrimary)
                .frame(minWidth: 32)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.chissDeep.opacity(0.55))
                        .overlay(Capsule().stroke(Color.chissPrimary.opacity(0.35), lineWidth: 1))
                )

            // Reveal-in-Finder button (shows file icon, grayed if audio missing)
            Button {
                if let url = entry.audioPath {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([entry.textPath])
                }
            } label: {
                Image(systemName: entry.audioPath != nil ? "speaker.wave.2.fill" : "doc.text.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(entry.audioPath != nil ? .chissPrimary : .white.opacity(0.4))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.chissDeep.opacity(0.35))
                            .overlay(Circle().stroke(Color.chissPrimary.opacity(0.28), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .help(entry.audioPath != nil ? "Reveal audio file in Finder" : "Audio unavailable — reveal text briefing")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.obsidianMid)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isPlaying ? Color.chissPrimary.opacity(0.55) : Color.chissPrimary.opacity(0.12),
                            lineWidth: isPlaying ? 2 : 1
                        )
                )
        )
    }
}
