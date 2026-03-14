import SwiftUI
import Foundation

// MARK: - Model

struct ParsedTask: Identifiable {
    let id: String
    var title: String
    var owner: String
    var status: String
    var priority: String
    var due: String
    var nextStep: String
    var blockers: String
    var deliverable: String
    var notes: String
}

// MARK: - Parser

func parseTaskBoard(from text: String) -> [ParsedTask] {
    var tasks: [ParsedTask] = []
    let lines = text.components(separatedBy: "\n")
    var i = 0

    while i < lines.count {
        let line = lines[i]
        if line.hasPrefix("### TASK-") {
            let taskId = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            var fields: [String: String] = [:]
            i += 1
            while i < lines.count && !lines[i].hasPrefix("### ") {
                let l = lines[i]
                if l.hasPrefix("- "), let colon = l.range(of: ": ") {
                    let key = String(l[l.index(l.startIndex, offsetBy: 2)..<colon.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let value = String(l[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
                    fields[key] = value
                }
                i += 1
            }
            let task = ParsedTask(
                id: taskId,
                title: fields["Title"] ?? taskId,
                owner: fields["Owner"] ?? "",
                status: fields["Status"] ?? "",
                priority: fields["Priority"] ?? "",
                due: fields["Due"] ?? "",
                nextStep: fields["Next step"] ?? "",
                blockers: fields["Blockers"] ?? "",
                deliverable: fields["Deliverable"] ?? "",
                notes: fields["Notes"] ?? ""
            )
            tasks.append(task)
        } else {
            i += 1
        }
    }
    return tasks
}

// MARK: - Store

@MainActor
final class TaskBoardStore: ObservableObject {
    @Published var tasks: [ParsedTask] = []
    @Published var isLoading = false
    @Published var errorText: String?

    private static let filePath = "/Users/crustacean/.openclaw/workspace/ops/TASK_BOARD.md"

    func load() {
        isLoading = true
        errorText = nil
        Task {
            if let content = try? String(contentsOfFile: Self.filePath, encoding: .utf8) {
                tasks = parseTaskBoard(from: content)
                if tasks.isEmpty { errorText = "No tasks found in TASK_BOARD.md" }
            } else {
                tasks = []
                errorText = "Could not read TASK_BOARD.md"
            }
            isLoading = false
        }
    }

    func tasksInLane(_ lane: String) -> [ParsedTask] {
        tasks.filter { $0.status.lowercased() == lane.lowercased() }
    }
}

// MARK: - View

struct TaskBoardView: View {
    @StateObject private var store = TaskBoardStore()
    private let lanes = ["In Progress", "Review", "Blocked", "Ready", "Inbox", "Done"]

    var body: some View {
        ZStack {
            Color.obsidian.ignoresSafeArea()
            RadialGradient(colors: [Color.chissDeep.opacity(0.40), Color.clear], center: .topLeading, startRadius: 0, endRadius: 700)
                .ignoresSafeArea()
            RadialGradient(colors: [Color.sithRed.opacity(0.18), Color.clear], center: .bottomTrailing, startRadius: 0, endRadius: 500)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TASK BOARD")
                            .font(.system(size: 14, weight: .bold, design: .serif))
                            .tracking(3)
                            .foregroundColor(Color.chissPrimary)
                            .shadow(color: Color.chissPrimary.opacity(0.40), radius: 8)
                        Text("\(store.tasks.count) active tasks")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.40))
                    }
                    Spacer()
                    if store.isLoading {
                        ProgressView().progressViewStyle(.circular).scaleEffect(0.65).tint(Color.chissPrimary)
                    }
                    Button {
                        store.load()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .bold))
                            Text("Reload")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(Color.chissPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.chissDeep.opacity(0.55)).overlay(Capsule().stroke(Color.chissPrimary.opacity(0.35), lineWidth: 1)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.obsidianMid.opacity(0.92))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.chissPrimary.opacity(0.12)).frame(height: 1)
                }

                if let err = store.errorText {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28))
                            .foregroundColor(Color.chissPrimary.opacity(0.55))
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.50))
                    }
                    Spacer()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(lanes, id: \.self) { lane in
                                let laneTasks = store.tasksInLane(lane)
                                if !laneTasks.isEmpty || lane == "In Progress" || lane == "Blocked" {
                                    TaskLaneColumn(lane: lane, tasks: laneTasks)
                                        .frame(width: 280)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { store.load() }
    }
}

// MARK: - Lane Column

private struct TaskLaneColumn: View {
    let lane: String
    let tasks: [ParsedTask]

    var isBlocked: Bool { lane == "Blocked" }

    var laneColor: Color {
        switch lane {
        case "Blocked": return Color.sithGlow
        case "In Progress": return Color.chissPrimary
        case "Review": return Color(red: 0.70, green: 0.55, blue: 0.90)
        case "Done": return Color(red: 0.35, green: 0.75, blue: 0.50)
        case "Ready": return Color(red: 0.40, green: 0.72, blue: 0.55)
        default: return Color.chissPrimary.opacity(0.70)
        }
    }

    var laneIcon: String {
        switch lane {
        case "Blocked": return "exclamationmark.octagon.fill"
        case "In Progress": return "arrow.triangle.2.circlepath"
        case "Review": return "eye.fill"
        case "Done": return "checkmark.seal.fill"
        case "Ready": return "checkmark.circle"
        default: return "tray.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: laneIcon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(laneColor)
                    .shadow(color: laneColor.opacity(0.70), radius: 6)
                Text(lane.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.5)
                    .foregroundColor(laneColor)
                Spacer()
                Text("\(tasks.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(laneColor.opacity(0.80))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(laneColor.opacity(0.14)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.obsidianMid)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(laneColor.opacity(0.30), lineWidth: 1))
                    .shadow(color: laneColor.opacity(0.18), radius: 8)
            )

            VStack(spacing: 10) {
                if tasks.isEmpty {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(laneColor.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [5]))
                        Text("Empty")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.22))
                    }
                    .frame(minHeight: 52)
                } else {
                    ForEach(tasks) { task in
                        TaskCardView(task: task, laneColor: laneColor, isBlocked: isBlocked)
                    }
                }
            }
        }
    }
}

// MARK: - Task Card

private struct TaskCardView: View {
    let task: ParsedTask
    let laneColor: Color
    let isBlocked: Bool

    @State private var expanded = false

    var body: some View {
        Button { withAnimation(.spring(response: 0.28)) { expanded.toggle() } } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(task.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.90))
                    .lineLimit(expanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if expanded {
                    if !task.nextStep.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: 9))
                                .foregroundColor(Color.chissPrimary.opacity(0.70))
                                .padding(.top, 1)
                            Text(task.nextStep)
                                .font(.system(size: 10.5))
                                .foregroundColor(Color.chissPrimary.opacity(0.80))
                        }
                    }
                    if isBlocked && !task.blockers.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(Color.sithGlow)
                                .padding(.top, 1)
                            Text(task.blockers)
                                .font(.system(size: 10.5))
                                .foregroundColor(Color.sithGlow.opacity(0.90))
                        }
                    }
                    if !task.deliverable.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "shippingbox")
                                .font(.system(size: 9))
                                .foregroundColor(Color.white.opacity(0.40))
                                .padding(.top, 1)
                            Text(task.deliverable)
                                .font(.system(size: 10))
                                .foregroundColor(Color.white.opacity(0.40))
                                .lineLimit(1)
                        }
                    }
                }

                HStack(spacing: 6) {
                    if !task.owner.isEmpty {
                        Text(task.owner)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(isBlocked ? Color.sithGlow : Color.chissPrimary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(isBlocked ? Color.sithRed.opacity(0.18) : Color.chissDeep.opacity(0.50))
                                    .overlay(Capsule().stroke(isBlocked ? Color.sithGlow.opacity(0.40) : Color.chissPrimary.opacity(0.28), lineWidth: 1))
                            )
                    }
                    Spacer()
                    if !task.priority.isEmpty {
                        Text(task.priority)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(task.priority.lowercased() == "high" ? Color.sithGlow : Color.white.opacity(0.40))
                    }
                    if !task.due.isEmpty {
                        Text(task.due)
                            .font(.system(size: 9))
                            .foregroundColor(Color.white.opacity(0.35))
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.obsidianMid)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(laneColor.opacity(isBlocked ? 0.55 : 0.22), lineWidth: 1))
            )
            .shadow(color: laneColor.opacity(isBlocked ? 0.35 : 0.10), radius: isBlocked ? 12 : 5)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
