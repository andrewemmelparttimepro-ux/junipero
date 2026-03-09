import SwiftUI

struct AgentRailPopoverView: View {
    let entry: AgentRailEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            crest
            header

            HStack(spacing: 10) {
                statTile(title: "Status", value: entry.activitySource.label, highlighted: entry.isActive)
                statTile(title: "Last Active", value: lastActiveLabel)
            }

            sectionCard(title: "Mandate") {
                VStack(alignment: .leading, spacing: 12) {
                    detailRow(title: "Role", value: entry.presentation.roleTitle)
                    detailRow(title: "Focus", value: entry.presentation.roleNote)
                    detailRow(title: "Model", value: entry.model ?? "Unavailable")
                }
            }

            sectionCard(title: "Paths") {
                VStack(alignment: .leading, spacing: 12) {
                    detailRow(title: "Workspace", value: entry.workspacePath ?? "Unavailable", multiline: true)
                    detailRow(title: "Agent Dir", value: entry.agentDirPath ?? "Unavailable", multiline: true)
                }
            }

            if entry.presentation.isPrimaryIdentity {
                noteCard(
                    title: "Front Identity",
                    body: {
                        if let backingAgentName = entry.backingAgentName, !backingAgentName.isEmpty {
                            return "O'Brien is the face of the main session and rides on the default OpenClaw routing setup backed by \(backingAgentName)."
                        }
                        return "O'Brien is the face of the main session and rides on the default OpenClaw routing setup."
                    }()
                )
            } else if entry.isDefaultAgent {
                noteCard(
                    title: "Default Agent",
                    body: "\(entry.popoverTitle) is the current default routing agent behind O'Brien."
                )
            }
        }
        .padding(20)
        .frame(width: 352)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.96),
                                Color(red: 0.97, green: 0.95, blue: 0.90).opacity(0.98),
                                Color(red: 0.94, green: 0.93, blue: 0.89).opacity(0.96),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RadialGradient(
                    colors: [
                        entry.presentation.accentColor.opacity(0.14),
                        Color.clear,
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 180
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(entry.presentation.accentColor.opacity(0.24), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.13), radius: 24, x: 0, y: 12)
        )
    }

    private var crest: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(entry.presentation.accentColor.opacity(0.24))
                .frame(height: 1)
            Text("ORDER OF THE SEVEN")
                .font(.system(size: 9, weight: .bold, design: .serif))
                .tracking(2.4)
                .foregroundStyle(entry.presentation.accentColor.opacity(0.86))
            Rectangle()
                .fill(entry.presentation.accentColor.opacity(0.24))
                .frame(height: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(entry.presentation.accentColor.opacity(0.16))
                    .frame(width: 48, height: 48)
                Circle()
                    .stroke(entry.presentation.accentColor.opacity(0.24), lineWidth: 1)
                    .frame(width: 48, height: 48)
                Image(systemName: entry.presentation.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(entry.presentation.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.popoverTitle)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.black.opacity(0.86))
                Text(entry.displayName.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .serif))
                    .tracking(2.4)
                    .foregroundStyle(entry.presentation.accentColor.opacity(0.88))

                HStack(spacing: 8) {
                    statusChip(label: entry.activitySource.label, tint: entry.presentation.accentColor, highlighted: entry.isActive)
                    if entry.presentation.isPrimaryIdentity {
                        statusChip(label: "Primary Identity", tint: entry.presentation.accentColor, highlighted: false)
                    } else if entry.isDefaultAgent {
                        statusChip(label: "Default Agent", tint: entry.presentation.accentColor, highlighted: false)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func statTile(title: String, value: String, highlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(Color.black.opacity(0.42))
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(highlighted ? entry.presentation.accentColor : Color.black.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(highlighted ? entry.presentation.accentColor.opacity(0.10) : Color.white.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(highlighted ? entry.presentation.accentColor.opacity(0.20) : Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.9)
                .foregroundStyle(Color.black.opacity(0.46))
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func detailRow(title: String, value: String, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(Color.black.opacity(0.45))
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.78))
                .lineLimit(multiline ? 3 : 1)
                .fixedSize(horizontal: false, vertical: multiline)
        }
    }

    private func noteCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(entry.presentation.accentColor.opacity(0.9))
            Text(body)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(entry.presentation.accentColor.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(entry.presentation.accentColor.opacity(0.14), lineWidth: 1)
        )
    }

    private func statusChip(label: String, tint: Color, highlighted: Bool) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(highlighted ? tint.opacity(0.18) : Color.black.opacity(0.05))
            )
            .foregroundStyle(highlighted ? tint : Color.black.opacity(0.60))
    }

    private var lastActiveLabel: String {
        guard let lastActiveAt = entry.lastActiveAt else {
            return entry.activitySource == .unavailable ? "Unavailable" : "No recent activity"
        }
        return Self.relativeFormatter.localizedString(for: lastActiveAt, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
