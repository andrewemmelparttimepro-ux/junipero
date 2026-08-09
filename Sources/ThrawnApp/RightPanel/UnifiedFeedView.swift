import SwiftUI

// MARK: - Unified Feed (rethink Phase 3)
// One timeline for the whole stable: local fleet runs, deployed agents
// (ARI / OTTO / SPOT reporting home through the Brain), proof verdicts,
// watchdog pages, and credential events. Read-only; the Brain is the
// system of record.
struct UnifiedFeedView: View {
    @State private var events: [BrainClient.FeedEvent] = []
    @State private var loading = true
    @State private var lastRefreshed: Date?

    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color.chissPrimary.opacity(0.15))

            if loading && events.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView().tint(Color.chissPrimary)
                    Spacer()
                }
                Spacer()
            } else if events.isEmpty {
                Spacer()
                Text("No events in the Brain yet. The fleet reports here as it runs.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(events) { event in
                            feedRow(event)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(Color.obsidian)
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.up.forward")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color.chissPrimary)
            Text("UNIFIED FEED")
                .font(.system(size: 12, weight: .black))
                .tracking(2)
                .foregroundColor(.white.opacity(0.85))
            Text("local fleet · deployed agents · proofs · watchdog")
                .font(.system(size: 9.5))
                .foregroundColor(.white.opacity(0.35))
            Spacer()
            if let lastRefreshed {
                Text(lastRefreshed, style: .time)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.30))
            }
            Button {
                refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.chissPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func feedRow(_ event: BrainClient.FeedEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(event.at, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .frame(width: 82, alignment: .leading)

            Text(event.agentSlug.uppercased())
                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(agentColor(event.agentSlug))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(agentColor(event.agentSlug).opacity(0.12)))
                .frame(width: 110, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(event.kind)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(kindColor(event))
                    if let status = event.status, status != "ok" {
                        Text(status)
                            .font(.system(size: 8.5))
                            .foregroundColor(.white.opacity(0.40))
                    }
                }
                if let summary = event.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.68))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white.opacity(event.status == "failed" ? 0.035 : 0.015))
        )
    }

    private func agentColor(_ slug: String) -> Color {
        switch slug {
        case "thrawn": return Color.chissPrimary
        case "ari", "otto", "spot": return Color.ndaiGreen
        case "watchdog": return Color.orange
        case "product-sentinel": return Color(red: 0.72, green: 0.62, blue: 0.90)
        default: return Color(red: 0.55, green: 0.70, blue: 0.85)
        }
    }

    private func kindColor(_ event: BrainClient.FeedEvent) -> Color {
        if event.status == "failed" || event.kind == "error" { return Color.sithGlow }
        switch event.kind {
        case "deliverable": return Color.ndaiGreen
        case "proof_verdict": return event.status == "passed" ? Color.ndaiGreen : Color.orange
        case "watchdog", "escalation": return Color.orange
        default: return Color.chissPrimary.opacity(0.85)
        }
    }

    private func refresh() {
        BrainClient.shared.fetchFeed { fetched in
            events = fetched
            loading = false
            lastRefreshed = Date()
        }
    }
}
