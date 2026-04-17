import SwiftUI
import UniformTypeIdentifiers

// MARK: - Flow Lane (visual mapping for TASK_BOARD.md status values)

enum FlowLane: String, CaseIterable, Identifiable, Codable {
    case inbox      = "Inbox"
    case ready      = "Ready"
    case inProgress = "In Progress"
    case review     = "Review"
    case blocked    = "Blocked"
    case done       = "Done"

    var id: String { rawValue }

    var accentColor: Color {
        switch self {
        case .inbox:      return Color.chissPrimary.opacity(0.70)
        case .ready:      return Color(red: 0.40, green: 0.72, blue: 0.55)
        case .inProgress: return Color.chissPrimary
        case .review:     return Color(red: 0.70, green: 0.55, blue: 0.90)
        case .blocked:    return Color.sithGlow
        case .done:       return Color(red: 0.35, green: 0.75, blue: 0.50)
        }
    }

    var glowColor: Color {
        switch self {
        case .blocked: return Color.sithGlow
        case .review:  return Color(red: 0.70, green: 0.55, blue: 0.90)
        default:       return Color.chissPrimary
        }
    }

    var icon: String {
        switch self {
        case .inbox:      return "tray.fill"
        case .ready:      return "checkmark.circle"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .review:     return "eye.fill"
        case .blocked:    return "exclamationmark.octagon.fill"
        case .done:       return "checkmark.seal.fill"
        }
    }

    static func fromTaskStatus(_ status: String) -> FlowLane {
        switch status.lowercased().trimmingCharacters(in: .whitespaces) {
        case "in progress": return .inProgress
        case "review":      return .review
        case "blocked":     return .blocked
        case "ready":       return .ready
        case "done":        return .done
        default:            return .inbox
        }
    }
}

// MARK: - ParsedTask extensions

extension ParsedTask {
    var flowLane: FlowLane { FlowLane.fromTaskStatus(status) }
}

// MARK: - Drag item for task cards

struct TaskDragItem: Codable, Transferable {
    var taskId: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .plainText)
    }
}

// MARK: - Board View

struct FlowBoardView: View {
    @StateObject private var store = TaskBoardStore()
    @EnvironmentObject var flowTab: FlowTabStore
    @State private var selectedTaskId: String?
    @State private var showAddSheet = false
    @State private var dropTargetLane: FlowLane?
    @State private var searchText = ""
    var embedded: Bool = false

    private var filteredTasks: [ParsedTask] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.tasks }
        return store.tasks.filter {
            $0.title.lowercased().contains(query) ||
            $0.id.lowercased().contains(query) ||
            $0.owner.lowercased().contains(query) ||
            $0.nextStep.lowercased().contains(query) ||
            $0.blockers.lowercased().contains(query) ||
            $0.deliverable.lowercased().contains(query) ||
            $0.notes.lowercased().contains(query)
        }
    }

    var body: some View {
        ZStack {
            if !embedded {
                ZStack {
                    Color.obsidian.ignoresSafeArea()
                    RadialGradient(colors: [Color.chissDeep.opacity(0.55), Color.clear], center: .topLeading, startRadius: 0, endRadius: 800).ignoresSafeArea()
                    RadialGradient(colors: [Color.sithRed.opacity(0.28), Color.clear], center: .bottomTrailing, startRadius: 0, endRadius: 700).ignoresSafeArea()
                    RadialGradient(colors: [Color.sithRed.opacity(0.12), Color.clear], center: .bottomLeading, startRadius: 0, endRadius: 450).ignoresSafeArea()
                }
            }

            if let taskId = selectedTaskId, store.tasks.contains(where: { $0.id == taskId }) {
                // Full task detail page
                TaskDetailPage(taskId: taskId, store: store, onClose: { selectedTaskId = nil })
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
            } else {
                VStack(spacing: 0) {
                    flowToolbar

                    if store.isLoading && store.tasks.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView().progressViewStyle(.circular).scaleEffect(0.8).tint(Color.chissPrimary)
                            Text("Loading TASK_BOARD.md…").font(.system(size: 12)).foregroundColor(Color.white.opacity(0.40))
                        }
                        Spacer()
                    } else if let err = store.errorText {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundColor(Color.chissPrimary.opacity(0.55))
                            Text(err).font(.system(size: 13)).foregroundColor(Color.white.opacity(0.50))
                        }
                        Spacer()
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(FlowLane.allCases) { lane in
                                    let laneTasks = filteredTasks.filter { $0.flowLane == lane }

                                    if lane == .done {
                                        DoneStackColumn(
                                            tasks: laneTasks,
                                            isDropTarget: dropTargetLane == lane,
                                            onSelect: { selectedTaskId = $0.id },
                                            onClear: { taskId in store.deleteTask(taskId) },
                                            onClearAll: {
                                                for t in laneTasks { store.deleteTask(t.id) }
                                            },
                                            onDrop: { taskId in
                                                withAnimation(.spring(response: 0.3)) {
                                                    store.moveTask(taskId, to: lane.rawValue)
                                                    dropTargetLane = nil
                                                }
                                            },
                                            onDropEnter: { dropTargetLane = lane },
                                            onDropExit: { if dropTargetLane == lane { dropTargetLane = nil } }
                                        )
                                        .frame(width: 260)
                                    } else {
                                        FlowLaneColumn(
                                            lane: lane,
                                            tasks: laneTasks,
                                            isDropTarget: dropTargetLane == lane,
                                            onSelect: { selectedTaskId = $0.id },
                                            onDrop: { taskId in
                                                withAnimation(.spring(response: 0.3)) {
                                                    store.moveTask(taskId, to: lane.rawValue)
                                                    dropTargetLane = nil
                                                }
                                            },
                                            onDropEnter: { dropTargetLane = lane },
                                            onDropExit: { if dropTargetLane == lane { dropTargetLane = nil } }
                                        )
                                        .frame(width: 260)
                                    }
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 20)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedTaskId)
        .sheet(isPresented: $showAddSheet) {
            AddTaskSheet(store: store, isPresented: $showAddSheet)
        }
        .onAppear { store.load() }
    }

    private var flowToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if !embedded {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) { flowTab.showFlow = false }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                            Text("Back").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(Color.chissPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.chissDeep.opacity(0.55)).overlay(Capsule().stroke(Color.chissPrimary.opacity(0.35), lineWidth: 1)))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(embedded ? "TASKS" : "FLOW")
                        .font(.system(size: 18, weight: .bold, design: .serif)).tracking(4)
                        .foregroundColor(Color.chissPrimary).shadow(color: Color.chissPrimary.opacity(0.40), radius: 10)
                    Text("\(store.tasks.count) tasks from TASK_BOARD.md")
                        .font(.system(size: 10, weight: .medium)).foregroundColor(Color.white.opacity(0.40))
                }

                Spacer()

                HStack(spacing: 6) {
                    ForEach(FlowLane.allCases) { lane in
                        let count = filteredTasks.filter { $0.flowLane == lane }.count
                        if count > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: lane.icon).font(.system(size: 9, weight: .bold))
                                Text("\(count)").font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(lane.accentColor)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(lane.accentColor.opacity(0.12)).overlay(Capsule().stroke(lane.accentColor.opacity(0.28), lineWidth: 1)))
                        }
                    }
                }

                // Search
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.chissPrimary.opacity(0.50))
                    TextField("Search tasks…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.85))
                        .frame(width: 120)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color.chissPrimary.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.chissPrimary.opacity(0.18), lineWidth: 1)))

                Button { showAddSheet = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                        Text("Add").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.chissDeep).overlay(Capsule().stroke(Color.chissPrimary.opacity(0.55), lineWidth: 1)))
                    .shadow(color: Color.chissPrimary.opacity(0.25), radius: 8)
                }
                .buttonStyle(.plain)

                Button { store.load() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .bold))
                        Text("Reload").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(Color.chissPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.chissDeep.opacity(0.55)).overlay(Capsule().stroke(Color.chissPrimary.opacity(0.35), lineWidth: 1)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28).padding(.vertical, 16)
            .background(ZStack {
                Color.obsidianMid.opacity(0.92)
                LinearGradient(colors: [Color.chissDeep.opacity(0.35), Color.clear], startPoint: .top, endPoint: .bottom)
            })
            .overlay(alignment: .bottom) { Rectangle().fill(Color.chissPrimary.opacity(0.12)).frame(height: 1) }
        }
    }
}

// MARK: - Lane Column (with drop target)

struct FlowLaneColumn: View {
    let lane: FlowLane
    let tasks: [ParsedTask]
    var isDropTarget: Bool = false
    let onSelect: (ParsedTask) -> Void
    var onDrop: ((String) -> Void)? = nil
    var onDropEnter: (() -> Void)? = nil
    var onDropExit: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Lane header — pinned, never scrolls
            HStack(spacing: 8) {
                Image(systemName: lane.icon)
                    .font(.system(size: 11, weight: .bold)).foregroundColor(lane.accentColor)
                    .shadow(color: lane.glowColor.opacity(0.70), radius: 6)
                Text(lane.rawValue.uppercased())
                    .font(.system(size: 10, weight: .heavy)).tracking(1.5)
                    .foregroundColor(lane.accentColor).shadow(color: lane.glowColor.opacity(0.50), radius: 5)
                Spacer()
                Text("\(tasks.count)")
                    .font(.system(size: 10, weight: .bold)).foregroundColor(lane.accentColor.opacity(0.80))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(lane.accentColor.opacity(0.14)))
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.obsidianMid)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isDropTarget ? lane.accentColor.opacity(0.70) : lane.accentColor.opacity(0.30), lineWidth: isDropTarget ? 2 : 1))
                    .shadow(color: lane.glowColor.opacity(isDropTarget ? 0.40 : 0.18), radius: isDropTarget ? 14 : 8)
            )

            // Cards — scrollable within the lane
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 10) {
                    ForEach(tasks) { task in
                        FlowTaskCardView(task: task, lane: lane, onTap: { onSelect(task) })
                            .draggable(TaskDragItem(taskId: task.id))
                    }

                    if tasks.isEmpty || isDropTarget {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    isDropTarget ? lane.accentColor.opacity(0.55) : lane.accentColor.opacity(0.15),
                                    style: StrokeStyle(lineWidth: isDropTarget ? 2 : 1, dash: [5])
                                )
                            if isDropTarget {
                                VStack(spacing: 4) {
                                    Image(systemName: "arrow.down.doc")
                                        .font(.system(size: 14)).foregroundColor(lane.accentColor.opacity(0.70))
                                    Text("Drop here")
                                        .font(.system(size: 10, weight: .semibold)).foregroundColor(lane.accentColor.opacity(0.60))
                                }
                            } else {
                                Text("Empty")
                                    .font(.system(size: 11)).foregroundColor(Color.white.opacity(0.22))
                            }
                        }
                        .frame(minHeight: 52)
                    }
                }
                .padding(.bottom, 8)
            }
            .dropDestination(for: TaskDragItem.self) { items, _ in
                guard let item = items.first else { return false }
                onDrop?(item.taskId)
                return true
            } isTargeted: { targeted in
                if targeted { onDropEnter?() } else { onDropExit?() }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Done Stack Column (notification-style collapsed stack)

struct DoneStackColumn: View {
    let tasks: [ParsedTask]
    var isDropTarget: Bool = false
    let onSelect: (ParsedTask) -> Void
    let onClear: (String) -> Void
    let onClearAll: () -> Void
    var onDrop: ((String) -> Void)? = nil
    var onDropEnter: (() -> Void)? = nil
    var onDropExit: (() -> Void)? = nil

    @State private var expanded = false

    private let lane = FlowLane.done

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Lane header
            HStack(spacing: 8) {
                Image(systemName: lane.icon)
                    .font(.system(size: 11, weight: .bold)).foregroundColor(lane.accentColor)
                    .shadow(color: lane.glowColor.opacity(0.70), radius: 6)
                Text("DONE")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.5)
                    .foregroundColor(lane.accentColor).shadow(color: lane.glowColor.opacity(0.50), radius: 5)
                Spacer()
                Text("\(tasks.count)")
                    .font(.system(size: 10, weight: .bold)).foregroundColor(lane.accentColor.opacity(0.80))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(lane.accentColor.opacity(0.14)))
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.obsidianMid)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isDropTarget ? lane.accentColor.opacity(0.70) : lane.accentColor.opacity(0.30), lineWidth: isDropTarget ? 2 : 1))
                    .shadow(color: lane.glowColor.opacity(isDropTarget ? 0.40 : 0.18), radius: isDropTarget ? 14 : 8)
            )

            if tasks.isEmpty {
                // Empty state
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(lane.accentColor.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    Text("Empty")
                        .font(.system(size: 11)).foregroundColor(Color.white.opacity(0.22))
                }
                .frame(minHeight: 52)
            } else if !expanded {
                // Collapsed stack — shows top card with stacked cards peeking behind
                Button {
                    withAnimation(.spring(response: 0.3)) { expanded = true }
                } label: {
                    ZStack(alignment: .top) {
                        // Background cards (stacked effect)
                        if tasks.count > 2 {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.obsidianMid.opacity(0.5))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(lane.accentColor.opacity(0.08), lineWidth: 1))
                                .frame(height: 60)
                                .offset(y: 8)
                                .padding(.horizontal, 8)
                        }
                        if tasks.count > 1 {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.obsidianMid.opacity(0.7))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(lane.accentColor.opacity(0.12), lineWidth: 1))
                                .frame(height: 60)
                                .offset(y: 4)
                                .padding(.horizontal, 4)
                        }

                        // Top card
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(tasks[0].id)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(lane.accentColor.opacity(0.65))
                                Spacer()
                                HStack(spacing: 4) {
                                    Image(systemName: "square.stack.3d.up.fill")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("\(tasks.count)")
                                        .font(.system(size: 11, weight: .heavy))
                                }
                                .foregroundColor(lane.accentColor)
                            }
                            Text(tasks[0].title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(2)

                            Text("Tap to review completed tasks")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(lane.accentColor.opacity(0.5))
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.obsidianMid)
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(lane.accentColor.opacity(0.22), lineWidth: 1))
                        )
                        .shadow(color: lane.glowColor.opacity(0.10), radius: 5)
                    }
                }
                .buttonStyle(.plain)
            } else {
                // Expanded — notification-style list
                VStack(spacing: 0) {
                    // Clear All button
                    HStack {
                        Button {
                            withAnimation(.spring(response: 0.3)) { expanded = false }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 9, weight: .bold))
                                Text("COLLAPSE")
                                    .font(.system(size: 9, weight: .heavy))
                                    .tracking(0.8)
                            }
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                onClearAll()
                                expanded = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text("CLEAR ALL")
                                    .font(.system(size: 9, weight: .heavy))
                                    .tracking(0.8)
                            }
                            .foregroundColor(.sithGlow.opacity(0.8))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.sithRed.opacity(0.12))
                                .overlay(Capsule().stroke(Color.sithGlow.opacity(0.2), lineWidth: 1)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 8)

                    // Notification cards
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 6) {
                            ForEach(tasks) { task in
                                DoneNotificationCard(
                                    task: task,
                                    onTap: { onSelect(task) },
                                    onClear: { withAnimation(.spring(response: 0.25)) { onClear(task.id) } }
                                )
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .dropDestination(for: TaskDragItem.self) { items, _ in
            guard let item = items.first else { return false }
            onDrop?(item.taskId)
            return true
        } isTargeted: { targeted in
            if targeted { onDropEnter?() } else { onDropExit?() }
        }
    }
}

// MARK: - Done Notification Card

struct DoneNotificationCard: View {
    let task: ParsedTask
    let onTap: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Tap to open detail
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 0.35, green: 0.75, blue: 0.50).opacity(0.6))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            Text(task.id)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                            if !task.owner.isEmpty {
                                Text(task.owner)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(Color(red: 0.35, green: 0.75, blue: 0.50).opacity(0.5))
                            }
                        }
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            // Dismiss (clear) button
            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.obsidianMid.opacity(0.9))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(red: 0.35, green: 0.75, blue: 0.50).opacity(0.12), lineWidth: 1))
        )
    }
}

// MARK: - Heartbeat Countdown

/// Maps agent names/IDs to their heartbeat schedule.
/// Thrawn fires every 15 min, others fire at their minuteOffset once per hour.
struct HeartbeatCountdown {
    private static let scheduleByName: [String: (offset: Int, interval: Int)] = [
        "Thrawn":  (0,  15),
        "R2-D2":   (10, 60),
        "C-3PO":   (20, 60),
        "Qui-Gon": (30, 60),
        "Lando":   (40, 60),
        "Boba":    (50, 60),
    ]
    private static let scheduleById: [String: (offset: Int, interval: Int)] = [
        "thrawn":  (0,  15),
        "r2d2":    (10, 60),
        "c3po":    (20, 60),
        "quigon":  (30, 60),
        "lando":   (40, 60),
        "boba":    (50, 60),
    ]

    static func secondsUntilNext(for key: String) -> Int? {
        guard let schedule = scheduleByName[key] ?? scheduleById[key] else { return nil }
        let now = Date()
        let calendar = Calendar.current
        let currentMinute = calendar.component(.minute, from: now)
        let currentSecond = calendar.component(.second, from: now)
        let totalSecondsIntoHour = currentMinute * 60 + currentSecond

        if schedule.interval == 15 {
            let currentInCycle = totalSecondsIntoHour % (15 * 60)
            let remaining = (15 * 60) - currentInCycle
            return remaining <= 0 ? 15 * 60 : remaining
        } else {
            let targetSecondsIntoHour = schedule.offset * 60
            var remaining = targetSecondsIntoHour - totalSecondsIntoHour
            if remaining <= 0 { remaining += 3600 }
            return remaining
        }
    }

    static func format(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m > 0 {
            return "\(m)m \(String(format: "%02d", s))s"
        }
        return "\(s)s"
    }
}

/// Live countdown badge — glows red, pulses when imminent.
struct HeartbeatCountdownBadge: View {
    let owner: String
    var compact: Bool = false
    @State private var secondsLeft: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isImminent: Bool { secondsLeft <= 60 }
    private var isClose: Bool { secondsLeft <= 180 }

    private var glowColor: Color {
        if isImminent { return Color(red: 1.0, green: 0.25, blue: 0.20) }   // bright red
        if isClose    { return Color(red: 0.95, green: 0.45, blue: 0.25) }   // orange
        return Color(red: 0.85, green: 0.30, blue: 0.25).opacity(0.55)       // dim red
    }

    var body: some View {
        Group {
            if HeartbeatCountdown.secondsUntilNext(for: owner) != nil {
                HStack(spacing: compact ? 2 : 3) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: compact ? 5 : 6))
                        .foregroundColor(glowColor)
                        .shadow(color: isImminent ? glowColor.opacity(0.90) : .clear, radius: isImminent ? 6 : 0)
                    Text(HeartbeatCountdown.format(secondsLeft))
                        .font(.system(size: compact ? 8 : 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(glowColor)
                        .shadow(color: isImminent ? glowColor.opacity(0.70) : .clear, radius: isImminent ? 4 : 0)
                }
                .onReceive(timer) { _ in
                    secondsLeft = HeartbeatCountdown.secondsUntilNext(for: owner) ?? 0
                }
                .onAppear {
                    secondsLeft = HeartbeatCountdown.secondsUntilNext(for: owner) ?? 0
                }
            }
        }
    }
}

// MARK: - Task Card View (draggable)

struct FlowTaskCardView: View {
    let task: ParsedTask
    let lane: FlowLane
    let onTap: () -> Void

    private var isBlocked: Bool { lane == .blocked }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(task.id)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(lane.accentColor.opacity(0.65))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(lane.accentColor.opacity(0.10)))

                Text(task.title)
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(Color.white.opacity(0.90))
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)

                if !task.nextStep.isEmpty {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "arrow.right.circle").font(.system(size: 8.5)).foregroundColor(Color.chissPrimary.opacity(0.60)).padding(.top, 1)
                        Text(task.nextStep).font(.system(size: 10.5)).foregroundColor(Color.chissPrimary.opacity(0.75)).lineLimit(2)
                    }
                }

                if isBlocked && !task.blockers.isEmpty {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8.5)).foregroundColor(Color.sithGlow).padding(.top, 1)
                        Text(task.blockers).font(.system(size: 10.5)).foregroundColor(Color.sithGlow.opacity(0.90)).lineLimit(2)
                    }
                }

                HStack(spacing: 6) {
                    if !task.owner.isEmpty {
                        HStack(spacing: 5) {
                            Text(task.owner)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(isBlocked ? Color.sithGlow : Color.chissPrimary)
                            HeartbeatCountdownBadge(owner: task.owner)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(isBlocked ? Color.sithRed.opacity(0.18) : Color.chissDeep.opacity(0.50))
                            .overlay(Capsule().stroke(isBlocked ? Color.sithGlow.opacity(0.40) : Color.chissPrimary.opacity(0.28), lineWidth: 1)))
                    }
                    Spacer()
                    if !task.priority.isEmpty {
                        Text(task.priority).font(.system(size: 9, weight: .bold))
                            .foregroundColor(task.priority.lowercased() == "high" || task.priority.lowercased() == "critical" ? Color.sithGlow : Color.white.opacity(0.40))
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.obsidianMid)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(lane.accentColor.opacity(isBlocked ? 0.55 : 0.22), lineWidth: 1)))
            .shadow(color: lane.glowColor.opacity(isBlocked ? 0.35 : 0.10), radius: isBlocked ? 12 : 5)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - Full Task Detail Page (Notion/Linear-style)

struct TaskDetailPage: View {
    let taskId: String
    @ObservedObject var store: TaskBoardStore
    let onClose: () -> Void

    @State private var editTitle: String = ""
    @State private var editOwner: String = ""
    @State private var editPriority: String = ""
    @State private var editDue: String = ""
    @State private var editNextStep: String = ""
    @State private var editBlockers: String = ""
    @State private var editDeliverable: String = ""
    @State private var editNotes: String = ""
    @State private var newComment: String = ""
    @State private var newChecklistItem: String = ""
    @State private var activeTab: DetailTab = .details

    enum DetailTab: String, CaseIterable {
        case details = "Details"
        case checklist = "Checklist"
        case comments = "Comments"
        case activity = "Activity"
    }

    private var task: ParsedTask? {
        store.tasks.first { $0.id == taskId }
    }

    private var lane: FlowLane { task?.flowLane ?? .inbox }

    var body: some View {
        ZStack {
            Color.obsidian.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header bar
                taskHeader

                // Tab switcher
                tabSwitcher

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch activeTab {
                        case .details:   detailsTab
                        case .checklist: checklistTab
                        case .comments:  commentsTab
                        case .activity:  activityTab
                        }
                    }
                    .padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { loadFields() }
        .onChange(of: taskId) { _ in loadFields() }
    }

    private func loadFields() {
        guard let t = task else { return }
        editTitle = t.title
        editOwner = t.owner
        editPriority = t.priority
        editDue = t.due
        editNextStep = t.nextStep
        editBlockers = t.blockers
        editDeliverable = t.deliverable
        editNotes = t.notes
    }

    // MARK: - Header

    private var taskHeader: some View {
        HStack(spacing: 14) {
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                    Text("Board").font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(Color.chissPrimary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Color.chissDeep.opacity(0.55)).overlay(Capsule().stroke(Color.chissPrimary.opacity(0.35), lineWidth: 1)))
            }
            .buttonStyle(.plain)

            Text(taskId)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(Color.chissPrimary)

            Spacer()

            // Status picker (inline move)
            Menu {
                ForEach(FlowLane.allCases) { targetLane in
                    Button {
                        withAnimation { store.moveTask(taskId, to: targetLane.rawValue) }
                    } label: {
                        Label(targetLane.rawValue, systemImage: targetLane.icon)
                    }
                    .disabled(targetLane == lane)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: lane.icon).font(.system(size: 10, weight: .bold))
                    Text(lane.rawValue).font(.system(size: 11, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(lane.accentColor)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(lane.accentColor.opacity(0.12)).overlay(Capsule().stroke(lane.accentColor.opacity(0.40), lineWidth: 1)))
            }
            .buttonStyle(.plain)

            // Delete
            Button {
                store.deleteTask(taskId)
                onClose()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.sithGlow.opacity(0.70))
                    .frame(width: 30, height: 28)
                    .background(Capsule().fill(Color.sithRed.opacity(0.10)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(Color.obsidianMid.opacity(0.92))
        .overlay(alignment: .bottom) { Rectangle().fill(lane.accentColor.opacity(0.15)).frame(height: 1) }
    }

    // MARK: - Tabs

    private var tabSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(DetailTab.allCases, id: \.rawValue) { tab in
                let count: Int = {
                    switch tab {
                    case .comments:  return store.commentsForTask(taskId).count
                    case .checklist: return store.checklistForTask(taskId).items.count
                    case .activity:  return store.activitiesForTask(taskId).count
                    default: return 0
                    }
                }()

                Button { activeTab = tab } label: {
                    HStack(spacing: 5) {
                        Text(tab.rawValue).font(.system(size: 11, weight: .semibold))
                        if count > 0 {
                            Text("\(count)").font(.system(size: 9, weight: .bold))
                                .foregroundColor(activeTab == tab ? .white : Color.chissPrimary.opacity(0.70))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(activeTab == tab ? Color.chissPrimary.opacity(0.40) : Color.chissPrimary.opacity(0.12)))
                        }
                    }
                    .foregroundColor(activeTab == tab ? .white : Color.white.opacity(0.50))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(activeTab == tab ? Color.chissDeep : Color.clear)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
        .background(Color.obsidianMid.opacity(0.60))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.chissPrimary.opacity(0.08)).frame(height: 1) }
    }

    // MARK: - Details Tab

    private var detailsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title (large, editable)
            editableField("Title", text: $editTitle, font: .system(size: 18, weight: .bold), onCommit: {
                store.updateTask(taskId, field: "title", oldValue: task?.title ?? "", newValue: editTitle) { $0.title = editTitle }
            })

            // Properties grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                ownerPickerField()
                propertyField("Priority", icon: "flag.fill", text: $editPriority, onCommit: {
                    store.updateTask(taskId, field: "priority", oldValue: task?.priority ?? "", newValue: editPriority) { $0.priority = editPriority }
                })
                propertyField("Due", icon: "calendar", text: $editDue, onCommit: {
                    store.updateTask(taskId, field: "due", oldValue: task?.due ?? "", newValue: editDue) { $0.due = editDue }
                })
                propertyField("Deliverable", icon: "shippingbox", text: $editDeliverable, onCommit: {
                    store.updateTask(taskId, field: "deliverable", oldValue: task?.deliverable ?? "", newValue: editDeliverable) { $0.deliverable = editDeliverable }
                })
            }

            Divider().background(Color.chissPrimary.opacity(0.15))

            // Next step
            editableField("Next Step", text: $editNextStep, placeholder: "What's the next action?", onCommit: {
                store.updateTask(taskId, field: "nextStep", oldValue: task?.nextStep ?? "", newValue: editNextStep) { $0.nextStep = editNextStep }
            })

            // Blockers
            editableField("Blockers", text: $editBlockers, placeholder: "Any blockers?", color: Color.sithGlow, onCommit: {
                store.updateTask(taskId, field: "blockers", oldValue: task?.blockers ?? "", newValue: editBlockers) { $0.blockers = editBlockers }
            })

            // Notes (multiline)
            VStack(alignment: .leading, spacing: 6) {
                Text("NOTES").font(.system(size: 9, weight: .heavy)).tracking(1.5).foregroundColor(Color.white.opacity(0.35))
                TextEditor(text: $editNotes)
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.85))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.chissPrimary.opacity(0.15), lineWidth: 1)))
                    .onChange(of: editNotes) { _ in
                        store.updateTask(taskId, field: "notes", oldValue: task?.notes ?? "", newValue: editNotes) { $0.notes = editNotes }
                    }
            }
        }
    }

    // MARK: - Checklist Tab

    private var checklistTab: some View {
        let checklist = store.checklistForTask(taskId)
        let completedCount = checklist.items.filter(\.completed).count
        let totalCount = checklist.items.count

        return VStack(alignment: .leading, spacing: 16) {
            if totalCount > 0 {
                // Progress bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(completedCount)/\(totalCount) complete")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(Color.chissPrimary.opacity(0.70))
                        Spacer()
                        Text("\(totalCount > 0 ? Int(Double(completedCount) / Double(totalCount) * 100) : 0)%")
                            .font(.system(size: 11, weight: .bold)).foregroundColor(Color.chissPrimary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08)).frame(height: 6)
                            Capsule().fill(Color.chissPrimary).frame(width: totalCount > 0 ? geo.size.width * CGFloat(completedCount) / CGFloat(totalCount) : 0, height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }

            // Items
            ForEach(checklist.items) { item in
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.25)) { store.toggleChecklistItem(taskId: taskId, itemId: item.id) }
                    } label: {
                        Image(systemName: item.completed ? "checkmark.square.fill" : "square")
                            .font(.system(size: 16))
                            .foregroundColor(item.completed ? Color(red: 0.35, green: 0.75, blue: 0.50) : Color.chissPrimary.opacity(0.50))
                    }
                    .buttonStyle(.plain)

                    Text(item.text)
                        .font(.system(size: 13))
                        .foregroundColor(item.completed ? Color.white.opacity(0.35) : Color.white.opacity(0.85))
                        .strikethrough(item.completed, color: Color.white.opacity(0.25))

                    Spacer()

                    Button {
                        store.deleteChecklistItem(taskId: taskId, itemId: item.id)
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundColor(Color.white.opacity(0.25))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }

            // Add item
            HStack(spacing: 10) {
                Image(systemName: "plus.circle").font(.system(size: 14)).foregroundColor(Color.chissPrimary.opacity(0.50))
                TextField("Add checklist item…", text: $newChecklistItem)
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundColor(Color.white.opacity(0.85))
                    .onSubmit {
                        let trimmed = newChecklistItem.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        store.addChecklistItem(taskId: taskId, text: trimmed)
                        newChecklistItem = ""
                    }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.chissPrimary.opacity(0.12), lineWidth: 1)))
        }
    }

    // MARK: - Comments Tab

    private var commentsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Comment input
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.10)).frame(width: 28, height: 28)
                    Text("A").font(.system(size: 12, weight: .bold)).foregroundColor(Color.white.opacity(0.60))
                }
                TextField("Add a comment…", text: $newComment, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundColor(Color.white.opacity(0.85))
                    .lineLimit(1...5)
                    .onSubmit {
                        let trimmed = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        store.addComment(taskId: taskId, text: trimmed)
                        newComment = ""
                    }
                Button {
                    let trimmed = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    store.addComment(taskId: taskId, text: trimmed)
                    newComment = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.chissPrimary.opacity(0.25) : Color.chissPrimary)
                }
                .buttonStyle(.plain)
                .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.chissPrimary.opacity(0.18), lineWidth: 1)))

            Divider().background(Color.chissPrimary.opacity(0.10))

            // Existing comments
            let taskComments = store.commentsForTask(taskId)
            if taskComments.isEmpty {
                Text("No comments yet.")
                    .font(.system(size: 12)).foregroundColor(Color.white.opacity(0.30))
                    .padding(.top, 8)
            } else {
                ForEach(taskComments) { comment in
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            Circle().fill(Color.chissDeep).frame(width: 26, height: 26)
                            Text(String(comment.author.prefix(1)))
                                .font(.system(size: 11, weight: .bold)).foregroundColor(Color.chissPrimary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(comment.author)
                                    .font(.system(size: 11, weight: .semibold)).foregroundColor(Color.chissPrimary)
                                Text(Self.relativeDate(comment.timestamp))
                                    .font(.system(size: 10)).foregroundColor(Color.white.opacity(0.30))
                                Spacer()
                                Button {
                                    store.deleteComment(comment.id)
                                } label: {
                                    Image(systemName: "trash").font(.system(size: 9)).foregroundColor(Color.white.opacity(0.20))
                                }
                                .buttonStyle(.plain)
                            }
                            Text(comment.text)
                                .font(.system(size: 13)).foregroundColor(Color.white.opacity(0.85))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - Activity Tab

    private var activityTab: some View {
        let taskActivities = store.activitiesForTask(taskId)

        return VStack(alignment: .leading, spacing: 0) {
            if taskActivities.isEmpty {
                Text("No activity recorded yet.")
                    .font(.system(size: 12)).foregroundColor(Color.white.opacity(0.30))
                    .padding(.top, 8)
            } else {
                ForEach(taskActivities) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        // Timeline dot + line
                        VStack(spacing: 0) {
                            Circle()
                                .fill(entry.fieldChanged == "status" ? lane.accentColor : Color.chissPrimary.opacity(0.40))
                                .frame(width: 8, height: 8)
                            Rectangle()
                                .fill(Color.chissPrimary.opacity(0.12))
                                .frame(width: 1)
                        }
                        .frame(width: 8)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(entry.author)
                                    .font(.system(size: 11, weight: .semibold)).foregroundColor(Color.chissPrimary)
                                Text(entry.action)
                                    .font(.system(size: 11)).foregroundColor(Color.white.opacity(0.60))
                            }

                            if let oldVal = entry.oldValue, let newVal = entry.newValue, !oldVal.isEmpty {
                                HStack(spacing: 4) {
                                    Text(oldVal)
                                        .font(.system(size: 10)).foregroundColor(Color.white.opacity(0.30))
                                        .strikethrough(true, color: Color.white.opacity(0.20))
                                    Image(systemName: "arrow.right").font(.system(size: 8)).foregroundColor(Color.white.opacity(0.25))
                                    Text(newVal)
                                        .font(.system(size: 10, weight: .semibold)).foregroundColor(Color.chissPrimary.opacity(0.80))
                                }
                            }

                            Text(Self.relativeDate(entry.timestamp))
                                .font(.system(size: 9)).foregroundColor(Color.white.opacity(0.25))
                        }
                        .padding(.bottom, 12)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func editableField(_ label: String, text: Binding<String>, font: Font = .system(size: 13), placeholder: String = "", color: Color = Color.chissPrimary, onCommit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(1.5).foregroundColor(Color.white.opacity(0.35))
            TextField(placeholder.isEmpty ? label : placeholder, text: text)
                .font(font)
                .foregroundColor(color == Color.sithGlow ? Color.sithGlow.opacity(0.90) : Color.white.opacity(0.85))
                .textFieldStyle(.plain)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.15), lineWidth: 1)))
                .onSubmit { onCommit() }
        }
    }

    private static let detailOwners = ["Andrew", "Thrawn", "R2-D2", "C-3PO", "Qui-Gon", "Lando", "Boba"]

    private func ownerPickerField() -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "person.fill").font(.system(size: 9)).foregroundColor(Color.chissPrimary.opacity(0.50))
                Text("OWNER").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundColor(Color.white.opacity(0.35))
            }
            Menu {
                ForEach(Self.detailOwners, id: \.self) { name in
                    Button(name) {
                        let old = editOwner
                        editOwner = name
                        store.updateTask(taskId, field: "owner", oldValue: old, newValue: name) { $0.owner = name }
                    }
                }
            } label: {
                HStack {
                    Text(editOwner.isEmpty ? "Select owner" : editOwner)
                        .font(.system(size: 12))
                        .foregroundColor(editOwner.isEmpty ? Color.white.opacity(0.35) : Color.white.opacity(0.85))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(Color.chissPrimary.opacity(0.50))
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.chissPrimary.opacity(0.12), lineWidth: 1)))
            }
        }
    }

    private func propertyField(_ label: String, icon: String, text: Binding<String>, onCommit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9)).foregroundColor(Color.chissPrimary.opacity(0.50))
                Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(1).foregroundColor(Color.white.opacity(0.35))
            }
            TextField(label, text: text)
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.85))
                .textFieldStyle(.plain)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.chissPrimary.opacity(0.12), lineWidth: 1)))
                .onSubmit { onCommit() }
        }
    }

    private static func relativeDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 604800 { return "\(Int(interval / 86400))d ago" }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt.string(from: date)
    }
}

// MARK: - Add Task Sheet

struct AddTaskSheet: View {
    @ObservedObject var store: TaskBoardStore
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var owner = "Andrew"
    @State private var lane: FlowLane = .inbox
    @State private var priority = "Medium"

    private let owners = ["Andrew", "Thrawn", "R2-D2", "C-3PO", "Qui-Gon", "Lando", "Boba"]
    private let priorities = ["Critical", "High", "Medium", "Low"]

    var body: some View {
        ZStack {
            Color.obsidian.ignoresSafeArea()
            RadialGradient(colors: [Color.chissDeep.opacity(0.55), Color.clear], center: .topLeading, startRadius: 0, endRadius: 400).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("New Task")
                    .font(.system(size: 17, weight: .bold, design: .serif)).tracking(1)
                    .foregroundColor(Color.chissPrimary).shadow(color: Color.chissPrimary.opacity(0.35), radius: 8)

                VStack(alignment: .leading, spacing: 5) {
                    Text("TITLE").font(.system(size: 9, weight: .heavy)).tracking(1.5).foregroundColor(Color.chissPrimary.opacity(0.60))
                    TextField("Task title", text: $title)
                        .textFieldStyle(.plain).foregroundColor(.white.opacity(0.92)).padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.obsidianMid).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.chissPrimary.opacity(0.25), lineWidth: 1)))
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("OWNER").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundColor(Color.chissPrimary.opacity(0.60))
                        Picker("", selection: $owner) {
                            ForEach(owners, id: \.self) { Text($0) }
                        }.frame(width: 130)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("PRIORITY").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundColor(Color.chissPrimary.opacity(0.60))
                        Picker("", selection: $priority) {
                            ForEach(priorities, id: \.self) { Text($0) }
                        }.frame(width: 120)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("LANE").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundColor(Color.chissPrimary.opacity(0.60))
                    Picker("", selection: $lane) {
                        ForEach(FlowLane.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(width: 160)
                }

                HStack {
                    Spacer()
                    Button("Cancel") { isPresented = false }
                        .buttonStyle(.plain).foregroundColor(Color.chissPrimary.opacity(0.70))
                    Button("Create Task") {
                        guard !title.isEmpty else { return }
                        store.addTask(title: title, owner: owner, status: lane.rawValue, priority: priority)
                        isPresented = false
                    }
                    .buttonStyle(.plain).foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Capsule().fill(Color.chissDeep).overlay(Capsule().stroke(Color.chissPrimary.opacity(0.55), lineWidth: 1)))
                    .disabled(title.isEmpty)
                }
            }
            .padding(28).frame(width: 420)
        }
    }
}
