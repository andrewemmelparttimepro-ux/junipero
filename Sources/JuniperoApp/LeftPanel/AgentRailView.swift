import SwiftUI

struct AgentRailView: View {
    @EnvironmentObject private var agentRosterStore: AgentRosterStore
    @State private var selectedEntryID: String?
    @State private var hoveredEntryID: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.26),
                            Color(red: 0.96, green: 0.94, blue: 0.90).opacity(0.20),
                            Color(red: 0.91, green: 0.90, blue: 0.87).opacity(0.12),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.30), lineWidth: 1)
                )
                .overlay(alignment: .trailing) {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.00),
                            Color.black.opacity(0.05),
                            Color.white.opacity(0.18),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: 1)
                    .padding(.vertical, 18)
                }
                .shadow(color: Color.black.opacity(0.08), radius: 18, x: 10, y: 0)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("THE SEVEN")
                        .font(.system(size: 9, weight: .bold, design: .serif))
                        .tracking(2.8)
                        .foregroundStyle(Color.black.opacity(0.48))

                    SevenTickDivider()
                        .frame(height: 14)
                }
                .padding(.top, 18)
                .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(agentRosterStore.entries) { entry in
                        AgentRailRow(
                            entry: entry,
                            isSelected: selectedEntryID == entry.id,
                            isHovered: hoveredEntryID == entry.id
                        ) {
                            selectedEntryID = (selectedEntryID == entry.id) ? nil : entry.id
                        }
                        .onHover { isHovering in
                            hoveredEntryID = isHovering ? entry.id : (hoveredEntryID == entry.id ? nil : hoveredEntryID)
                        }
                        .popover(
                            isPresented: Binding(
                                get: { selectedEntryID == entry.id },
                                set: { isPresented in
                                    if !isPresented, selectedEntryID == entry.id {
                                        selectedEntryID = nil
                                    }
                                }
                            ),
                            attachmentAnchor: .rect(.bounds),
                            arrowEdge: .leading
                        ) {
                            AgentRailPopoverView(entry: currentEntry(for: entry.id) ?? entry)
                        }
                    }
                }
                .padding(.top, 22)
                .padding(.horizontal, 10)

                Spacer(minLength: 0)

                RailSeal()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 18)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func currentEntry(for id: String) -> AgentRailEntry? {
        agentRosterStore.entries.first(where: { $0.id == id })
    }
}

private struct SevenTickDivider: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.black.opacity(index == 3 ? 0.28 : 0.16))
                    .frame(width: index == 3 ? 12 : 8, height: index % 2 == 0 ? 2 : 1)
            }
        }
    }
}

private struct RailSeal: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.black.opacity(0.10))
                .frame(height: 1)
            Text("VII")
                .font(.system(size: 10, weight: .bold, design: .serif))
                .tracking(2.8)
                .foregroundStyle(Color.black.opacity(0.34))
            Rectangle()
                .fill(Color.black.opacity(0.10))
                .frame(height: 1)
        }
    }
}

private struct AgentRailRow: View {
    let entry: AgentRailEntry
    let isSelected: Bool
    let isHovered: Bool
    let onTap: () -> Void

    var body: some View {
        TimelineView(.animation) { context in
            let pulse = glowPulse(at: context.date)
            let engaged = isSelected || isHovered

            Button(action: onTap) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(backgroundFill(for: pulse, engaged: engaged))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(borderColor(for: pulse, engaged: engaged), lineWidth: engaged ? 0.9 : 0.6)
                        )
                        .shadow(
                            color: entry.isActive
                                ? entry.presentation.accentColor.opacity(0.18 * pulse)
                                : .clear,
                            radius: 12,
                            x: 0,
                            y: 4
                        )

                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(entry.presentation.accentColor.opacity(entry.isActive ? 0.82 : engaged ? 0.38 : 0.22))
                            .frame(width: 2, height: 30)
                            .shadow(
                                color: entry.isActive
                                    ? entry.presentation.accentColor.opacity(0.52 * pulse)
                                    : .clear,
                                radius: 6
                            )

                        Text(entry.displayName.uppercased())
                            .font(.system(size: 11.5, weight: .semibold, design: .serif))
                            .tracking(1.8)
                            .foregroundStyle(textColor(for: pulse, engaged: engaged))
                            .shadow(color: shadowColor(for: pulse), radius: shadowRadius(for: pulse))
                            .multilineTextAlignment(.leading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.95)

                        Spacer(minLength: 0)

                        DiamondStatusGlyph(
                            color: glyphColor(for: pulse, engaged: engaged),
                            isActive: entry.isActive
                        )
                    }
                    .padding(.horizontal, 10)
                }
                .frame(height: 44, alignment: .leading)
                .contentShape(Rectangle())
                .offset(x: engaged ? 2 : 0)
            }
            .buttonStyle(.plain)
        }
    }

    private func glowPulse(at date: Date) -> Double {
        guard entry.isActive else { return isSelected ? 0.75 : 0.45 }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2) / 2.2
        return 0.68 + (0.32 * ((cos(phase * .pi * 2) * -1) + 1) / 2)
    }

    private func textColor(for pulse: Double, engaged: Bool) -> Color {
        if entry.isActive {
            return entry.presentation.accentColor.opacity(min(1.0, 0.78 + (pulse * 0.20)))
        }
        if entry.activitySource == .unavailable {
            return Color.black.opacity(0.28)
        }
        return Color.black.opacity(engaged ? 0.72 : 0.48)
    }

    private func shadowColor(for pulse: Double) -> Color {
        guard entry.isActive else { return .clear }
        return entry.presentation.accentColor.opacity(0.55 * pulse)
    }

    private func shadowRadius(for pulse: Double) -> CGFloat {
        guard entry.isActive else { return 0 }
        return 8 * pulse
    }

    private func backgroundFill(for pulse: Double, engaged: Bool) -> LinearGradient {
        if entry.isActive {
            return LinearGradient(
                colors: [
                    entry.presentation.accentColor.opacity(0.18 * pulse),
                    entry.presentation.accentColor.opacity(0.07),
                    Color.white.opacity(0.03),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        if engaged {
            return LinearGradient(
                colors: [
                    entry.presentation.accentColor.opacity(0.10),
                    Color.white.opacity(0.10),
                    Color.clear,
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        return LinearGradient(
            colors: [
                Color.white.opacity(0.08),
                Color.clear,
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func borderColor(for pulse: Double, engaged: Bool) -> Color {
        if entry.isActive {
            return entry.presentation.accentColor.opacity(0.34 * pulse)
        }
        return Color.white.opacity(engaged ? 0.28 : 0.12)
    }

    private func glyphColor(for pulse: Double, engaged: Bool) -> Color {
        if entry.isActive {
            return entry.presentation.accentColor.opacity(0.88 * pulse)
        }
        if entry.activitySource == .unavailable {
            return Color.black.opacity(0.18)
        }
        return Color.black.opacity(engaged ? 0.34 : 0.18)
    }
}

private struct DiamondStatusGlyph: View {
    let color: Color
    let isActive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: isActive ? 8 : 6, height: isActive ? 8 : 6)
            .rotationEffect(.degrees(45))
            .shadow(color: isActive ? color.opacity(0.45) : .clear, radius: 4)
    }
}
