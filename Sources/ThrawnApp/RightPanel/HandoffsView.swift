import SwiftUI

// MARK: - Handoffs View (Dex Layer)
//
// Twice-daily handoffs between Thrawn and Claude.
// Morning = debrief + course correction.
// Evening = debrief + one implemented improvement.

struct HandoffsView: View {
    @EnvironmentObject var handoffStore: HandoffStore
    @EnvironmentObject var scheduler: AgentScheduler

    @State private var selectedHandoffId: String?

    var body: some View {
        ZStack {
            Color.obsidian.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerPanel
                    triggerPanel

                    if handoffStore.handoffs.isEmpty {
                        emptyState
                    } else {
                        ForEach(handoffStore.handoffs) { h in
                            HandoffCard(
                                handoff: h,
                                isExpanded: selectedHandoffId == h.id,
                                onTap: {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedHandoffId = selectedHandoffId == h.id ? nil : h.id
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(20)
            }
        }
        .onAppear {
            handoffStore.scanForResponses()
        }
    }

    // MARK: - Header

    private var headerPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.chissPrimary)
                Text("DEX HANDOFF LAYER")
                    .font(.system(size: 14, weight: .heavy, design: .serif))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.9))
            }
            Text("Twice-daily handoffs between Thrawn and Claude. Morning debriefs run at 09:02. Evening implementation handoffs run at 17:02 and ship one concrete business improvement per day.")
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

    // MARK: - Trigger Panel

    private var triggerPanel: some View {
        HStack(spacing: 12) {
            TriggerButton(
                label: "RUN MORNING NOW",
                icon: "sunrise.fill",
                color: .orange
            ) {
                scheduler.triggerHandoff(kind: .morning)
            }

            TriggerButton(
                label: "RUN EVENING NOW",
                icon: "moon.stars.fill",
                color: .chissPrimary
            ) {
                scheduler.triggerHandoff(kind: .evening)
            }

            Spacer()

            Button {
                handoffStore.scanForResponses()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                    Text("SCAN")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1)
                }
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.left.arrow.right.circle")
                .font(.system(size: 34))
                .foregroundColor(.chissPrimary.opacity(0.4))
            Text("No handoffs yet")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
            Text("The first handoff will generate automatically at 09:02 tomorrow, or trigger one manually above.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Trigger Button

private struct TriggerButton: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.6)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .shadow(color: color.opacity(0.3), radius: 8)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Handoff Card

struct HandoffCard: View {
    let handoff: Handoff
    let isExpanded: Bool
    let onTap: () -> Void

    @State private var reportText: String = ""

    private var statusColor: Color {
        switch handoff.status {
        case .pending: return .orange
        case .reviewed: return .chissPrimary
        case .implemented: return .green
        case .stale: return .white.opacity(0.3)
        }
    }

    private var kindColor: Color {
        handoff.kind == .morning ? .orange : .chissPrimary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: handoff.kind.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(kindColor)
                    .shadow(color: kindColor.opacity(0.5), radius: 5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(handoff.kind.displayName.uppercased())
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(1)
                        .foregroundColor(.white.opacity(0.9))
                    Text(handoff.id)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }

                Spacer()

                // Health pill
                Text("\(handoff.metrics.overallHealthPercent)%")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(healthColor(handoff.metrics.overallHealthPercent))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(healthColor(handoff.metrics.overallHealthPercent).opacity(0.15))
                            .overlay(Capsule().stroke(healthColor(handoff.metrics.overallHealthPercent).opacity(0.35), lineWidth: 1))
                    )

                // Status pill
                Text(handoff.status.rawValue.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1)
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(statusColor.opacity(0.12))
                            .overlay(Capsule().stroke(statusColor.opacity(0.3), lineWidth: 1))
                    )
            }

            // Summary
            Text(handoff.summary)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            // Metrics row
            HStack(spacing: 14) {
                MetricChip(label: "LLM", value: "\(handoff.metrics.llmCalls)")
                MetricChip(label: "HB OK", value: "\(handoff.metrics.heartbeatsCompleted)")
                MetricChip(label: "HB ERR", value: "\(handoff.metrics.heartbeatsErrored)")
                MetricChip(label: "TASKS", value: "\(handoff.metrics.tasksCompleted)/\(handoff.metrics.tasksCreated)")
                MetricChip(label: "ERR", value: "\(handoff.metrics.errorCount)")
                Spacer()
            }

            // Expanded report
            if isExpanded {
                Divider().background(Color.white.opacity(0.08))
                ScrollView {
                    Text(reportText.isEmpty ? "Loading report..." : reportText)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 400)
                .onAppear {
                    reportText = (try? String(contentsOfFile: handoff.reportPath, encoding: .utf8)) ?? "Report unavailable at \(handoff.reportPath)"
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.obsidianMid.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(kindColor.opacity(0.18), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private func healthColor(_ percent: Int) -> Color {
        if percent >= 90 { return .green }
        if percent >= 70 { return .chissPrimary }
        if percent >= 50 { return .orange }
        return .sithGlow
    }
}

private struct MetricChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.35))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
        }
    }
}
