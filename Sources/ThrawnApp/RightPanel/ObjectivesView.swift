import SwiftUI

// MARK: - Objectives View
//
// Top-level UI for the factory: select a playbook, provide input,
// launch an objective, monitor progress. The factory never stops.

struct ObjectivesView: View {
    @EnvironmentObject var objectiveStore: ObjectiveStore

    @State private var selectedPlaybookId: String = PlaybookLibrary.all[0].id
    @State private var inputText: String = ""
    @State private var showLaunchConfirm = false

    private var selectedPlaybook: Playbook? {
        PlaybookLibrary.all.first(where: { $0.id == selectedPlaybookId })
    }

    var body: some View {
        ZStack {
            Color.obsidian.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // ── Launch Panel ──
                    launchPanel

                    // ── Active Objectives ──
                    if !objectiveStore.objectives.isEmpty {
                        objectivesList
                    }
                }
                .padding(20)
            }
        }
        .onAppear {
            objectiveStore.refreshFromBoard()
        }
    }

    // MARK: - Launch Panel

    private var launchPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "target")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.sithGlow)
                Text("LAUNCH OBJECTIVE")
                    .font(.system(size: 14, weight: .heavy, design: .serif))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.9))
            }

            Text("Select a playbook and provide the target. Thrawn will decompose it into tasks and run the factory 24/7 until completion.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            // Playbook selector
            HStack(spacing: 12) {
                ForEach(PlaybookLibrary.all) { playbook in
                    PlaybookPill(
                        playbook: playbook,
                        isSelected: selectedPlaybookId == playbook.id
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedPlaybookId = playbook.id
                        }
                    }
                }
            }

            // Selected playbook description
            if let playbook = selectedPlaybook {
                VStack(alignment: .leading, spacing: 8) {
                    Text(playbook.description)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(3)

                    Text("\(playbook.phases.count) phases • ~\(playbook.totalEstimatedTasks) tasks")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.chissPrimary.opacity(0.7))
                }

                // Input field
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playbook.inputLabel.uppercased())
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1)
                            .foregroundColor(.white.opacity(0.4))

                        TextField(playbook.inputPlaceholder, text: $inputText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.chissPrimary.opacity(0.2), lineWidth: 1)
                                    )
                            )
                    }

                    Button {
                        objectiveStore.launch(playbook: playbook, input: inputText)
                        inputText = ""
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("LAUNCH")
                                .font(.system(size: 12, weight: .heavy))
                                .tracking(1)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.sithRed, Color.sithRed.opacity(0.7)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                .shadow(color: Color.sithGlow.opacity(0.3), radius: 8)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.obsidianMid)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.chissPrimary.opacity(0.12), lineWidth: 1)
                )
        )
    }

    // MARK: - Objectives List

    private var objectivesList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("OBJECTIVES")
                    .font(.system(size: 12, weight: .heavy, design: .serif))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.6))

                Button {
                    objectiveStore.refreshFromBoard()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Refresh task counts from board")

                Spacer()

                let activeCount = objectiveStore.activeObjectives.count
                if activeCount > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.sithGlow)
                            .frame(width: 6, height: 6)
                            .shadow(color: .sithGlow, radius: 4)
                        Text("\(activeCount) ACTIVE")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1)
                            .foregroundColor(.sithGlow)
                    }
                }
            }

            ForEach(objectiveStore.objectives.sorted(by: {
                statusOrder($0.status) < statusOrder($1.status)
            })) { objective in
                ObjectiveCard(objective: objective)
            }
        }
    }

    private func statusOrder(_ status: Objective.ObjectiveStatus) -> Int {
        switch status {
        case .active: return 0
        case .paused: return 1
        case .completed: return 2
        case .stopped: return 3
        }
    }
}

// MARK: - Playbook Pill

struct PlaybookPill: View {
    let playbook: Playbook
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: playbook.icon)
                    .font(.system(size: 10, weight: .bold))
                Text(playbook.name)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isSelected ? Color.chissDeep : Color.white.opacity(0.05))
                    .overlay(
                        Capsule().stroke(
                            isSelected ? Color.chissPrimary.opacity(0.5) : Color.clear,
                            lineWidth: 1
                        )
                    )
            )
            .shadow(color: isSelected ? Color.chissPrimary.opacity(0.15) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Objective Card

struct ObjectiveCard: View {
    let objective: Objective
    @EnvironmentObject var objectiveStore: ObjectiveStore

    private var playbook: Playbook? {
        PlaybookLibrary.all.first(where: { $0.id == objective.playbookId })
    }

    private var currentPhase: PlaybookPhase? {
        guard let playbook, objective.currentPhaseIndex < playbook.phases.count else { return nil }
        return playbook.phases[objective.currentPhaseIndex]
    }

    private var statusColor: Color {
        switch objective.status {
        case .active: return .sithGlow
        case .paused: return .orange
        case .completed: return .green
        case .stopped: return .white.opacity(0.3)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(spacing: 10) {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: objective.status == .active ? statusColor : .clear, radius: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(playbook?.name ?? objective.playbookId): \(objective.input)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))

                    Text(objective.id)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }

                Spacer()

                // Status badge
                Text(objective.status.rawValue.uppercased())
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

            // Progress bar
            if let playbook {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.08))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [statusColor.opacity(0.8), statusColor],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, geo.size.width * objective.progressPercent / 100))
                        }
                    }
                    .frame(height: 5)

                    HStack {
                        if let phase = currentPhase {
                            Text("Phase \(objective.currentPhaseIndex + 1)/\(playbook.phases.count): \(phase.name)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.chissPrimary.opacity(0.7))

                            Text("→ \(phase.agent)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.chissPrimary)
                        } else if objective.status == .completed {
                            Text("All \(playbook.phases.count) phases complete")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.green.opacity(0.7))
                        }

                        Spacer()

                        Text("\(objective.tasksCompleted)/\(objective.tasksCreated) tasks")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }

            // Action buttons
            if objective.status == .active || objective.status == .paused {
                HStack(spacing: 8) {
                    if objective.status == .active {
                        ObjectiveActionButton(label: "PAUSE", icon: "pause.fill", color: .orange) {
                            objectiveStore.pause(objective.id)
                        }
                    } else {
                        ObjectiveActionButton(label: "RESUME", icon: "play.fill", color: .sithGlow) {
                            objectiveStore.resume(objective.id)
                        }
                    }

                    ObjectiveActionButton(label: "STOP", icon: "stop.fill", color: .white.opacity(0.4)) {
                        objectiveStore.stop(objective.id)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.obsidianMid.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(statusColor.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

struct ObjectiveActionButton: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(label)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.8)
            }
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(color.opacity(0.08))
                    .overlay(Capsule().stroke(color.opacity(0.2), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}
