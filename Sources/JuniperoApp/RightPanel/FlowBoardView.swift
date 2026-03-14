import SwiftUI

// MARK: - Flow Board Model

enum FlowLane: String, CaseIterable, Identifiable {
    case inbox = "Inbox"
    case ready = "Ready"
    case inProgress = "In Progress"
    case review = "Review"
    case blocked = "Blocked"
    case done = "Done"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .inbox: return Color(red: 0.55, green: 0.65, blue: 0.80)
        case .ready: return Color(red: 0.45, green: 0.68, blue: 0.52)
        case .inProgress: return Color(red: 0.28, green: 0.50, blue: 0.88)
        case .review: return Color(red: 0.72, green: 0.55, blue: 0.88)
        case .blocked: return Color(red: 0.88, green: 0.42, blue: 0.38)
        case .done: return Color(red: 0.35, green: 0.72, blue: 0.48)
        }
    }

    var icon: String {
        switch self {
        case .inbox: return "tray.fill"
        case .ready: return "checkmark.circle"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .review: return "eye.fill"
        case .blocked: return "exclamationmark.octagon.fill"
        case .done: return "checkmark.seal.fill"
        }
    }
}

struct FlowCard: Identifiable {
    let id = UUID()
    var title: String
    var owner: String
    var lane: FlowLane
    var note: String
}

@MainActor
final class FlowBoardStore: ObservableObject {
    @Published var cards: [FlowCard] = [
        FlowCard(title: "Thrawn Console: Gateway WS integration", owner: "R2-D2", lane: .inProgress, note: "Replace chat-completions with Gateway-native transport"),
        FlowCard(title: "Agent spec files for all six roles", owner: "Thrawn", lane: .done, note: "See agents/ in workspace"),
        FlowCard(title: "Brain drive folder structure", owner: "Thrawn", lane: .done, note: "/Volumes/brain/NDAI"),
        FlowCard(title: "Cognee memory system", owner: "Thrawn", lane: .inProgress, note: "Installed, local server running"),
        FlowCard(title: "Blender CLI automation path", owner: "R2-D2", lane: .ready, note: "CLI-Anything installed, Phase 1 scope defined"),
        FlowCard(title: "GUI control layer research", owner: "Qui-Gon", lane: .inbox, note: "High priority — potential major unlock"),
        FlowCard(title: "Persistent dedicated agent sessions", owner: "Thrawn", lane: .blocked, note: "Blocked: needs compatible surface/runtime"),
        FlowCard(title: "NDAI command structure / autonomy rules", owner: "Thrawn", lane: .inProgress, note: "APPROVAL_BOUNDARIES.md defined, evolving"),
    ]

    func move(card: FlowCard, to lane: FlowLane) {
        guard let idx = cards.firstIndex(where: { $0.id == card.id }) else { return }
        cards[idx].lane = lane
    }

    func add(title: String, owner: String, lane: FlowLane) {
        cards.append(FlowCard(title: title, owner: owner, lane: lane, note: ""))
    }

    func delete(_ card: FlowCard) {
        cards.removeAll { $0.id == card.id }
    }

    func cards(in lane: FlowLane) -> [FlowCard] {
        cards.filter { $0.lane == lane }
    }
}

// MARK: - Flow Board View

struct FlowBoardView: View {
    @StateObject private var store = FlowBoardStore()
    @State private var showAddSheet = false
    @State private var selectedCard: FlowCard? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Board toolbar
            HStack {
                Text("Flow Board")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 0.12, green: 0.22, blue: 0.44))
                Text("·")
                    .foregroundColor(Color(red: 0.55, green: 0.65, blue: 0.80))
                Text("\(store.cards.count) cards")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 0.45, green: 0.55, blue: 0.70))
                Spacer()
                Button(action: { showAddSheet = true }) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Add Card")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color(red: 0.18, green: 0.36, blue: 0.68)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(red: 0.96, green: 0.95, blue: 0.92))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
            }

            // Kanban columns
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(FlowLane.allCases) { lane in
                        FlowLaneColumn(lane: lane, store: store, onSelect: { selectedCard = $0 })
                    }
                }
                .padding(14)
            }
            .background(Color(red: 0.95, green: 0.94, blue: 0.90))
        }
        .sheet(isPresented: $showAddSheet) {
            AddFlowCardSheet(store: store, isPresented: $showAddSheet)
        }
        .sheet(item: $selectedCard) { card in
            FlowCardDetailSheet(card: card, store: store, isPresented: Binding(
                get: { selectedCard?.id == card.id },
                set: { if !$0 { selectedCard = nil } }
            ))
        }
    }
}

// MARK: - Lane Column

struct FlowLaneColumn: View {
    let lane: FlowLane
    @ObservedObject var store: FlowBoardStore
    let onSelect: (FlowCard) -> Void

    var cards: [FlowCard] { store.cards(in: lane) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Lane header
            HStack(spacing: 6) {
                Image(systemName: lane.icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(lane.color)
                Text(lane.rawValue.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .foregroundColor(lane.color)
                Spacer()
                Text("\(cards.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(lane.color.opacity(0.70))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(lane.color.opacity(0.14)))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(lane.color.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(lane.color.opacity(0.25), lineWidth: 1)
                    )
            )

            // Cards
            VStack(spacing: 8) {
                ForEach(cards) { card in
                    FlowCardView(card: card, store: store, onTap: { onSelect(card) })
                }

                if cards.isEmpty {
                    Text("Empty")
                        .font(.system(size: 11))
                        .foregroundColor(Color.black.opacity(0.28))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.black.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                }
            }
        }
        .frame(width: 200)
    }
}

// MARK: - Card View

struct FlowCardView: View {
    let card: FlowCard
    @ObservedObject var store: FlowBoardStore
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(card.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(red: 0.12, green: 0.18, blue: 0.30))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !card.note.isEmpty {
                    Text(card.note)
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 0.38, green: 0.48, blue: 0.62))
                        .lineLimit(2)
                }

                HStack {
                    Text(card.owner)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(red: 0.22, green: 0.38, blue: 0.65))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(red: 0.22, green: 0.38, blue: 0.65).opacity(0.12)))
                    Spacer()
                    // Move arrows
                    moveButtons
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(card.lane.color.opacity(0.30), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var moveButtons: some View {
        HStack(spacing: 4) {
            if let prev = previousLane {
                Button {
                    withAnimation(.spring(response: 0.3)) { store.move(card: card, to: prev) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(red: 0.40, green: 0.52, blue: 0.72))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color(red: 0.40, green: 0.52, blue: 0.72).opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
            if let next = nextLane {
                Button {
                    withAnimation(.spring(response: 0.3)) { store.move(card: card, to: next) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(red: 0.22, green: 0.38, blue: 0.72))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color(red: 0.22, green: 0.38, blue: 0.72).opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var allLanes: [FlowLane] { FlowLane.allCases }
    private var currentIndex: Int { allLanes.firstIndex(of: card.lane) ?? 0 }
    private var previousLane: FlowLane? { currentIndex > 0 ? allLanes[currentIndex - 1] : nil }
    private var nextLane: FlowLane? { currentIndex < allLanes.count - 1 ? allLanes[currentIndex + 1] : nil }
}

// MARK: - Add Card Sheet

struct AddFlowCardSheet: View {
    @ObservedObject var store: FlowBoardStore
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var owner = "Thrawn"
    @State private var lane: FlowLane = .inbox

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Flow Card")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(red: 0.12, green: 0.22, blue: 0.44))

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Owner")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.40, green: 0.50, blue: 0.65))
                Picker("", selection: $owner) {
                    ForEach(["Thrawn", "R2-D2", "C-3PO", "Qui-Gon", "Lando", "Boba"], id: \.self) { Text($0) }
                }
                .frame(width: 120)
            }

            HStack {
                Text("Lane")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.40, green: 0.50, blue: 0.65))
                Picker("", selection: $lane) {
                    ForEach(FlowLane.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 140)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(red: 0.40, green: 0.50, blue: 0.65))
                Button("Add") {
                    guard !title.isEmpty else { return }
                    store.add(title: title, owner: owner, lane: lane)
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(red: 0.18, green: 0.36, blue: 0.68)))
                .disabled(title.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

// MARK: - Card Detail Sheet

struct FlowCardDetailSheet: View {
    let card: FlowCard
    @ObservedObject var store: FlowBoardStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(card.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(red: 0.12, green: 0.22, blue: 0.44))

            HStack {
                Label(card.owner, systemImage: "person.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.28, green: 0.44, blue: 0.70))
                Spacer()
                Label(card.lane.rawValue, systemImage: card.lane.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(card.lane.color)
            }

            if !card.note.isEmpty {
                Text(card.note)
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 0.30, green: 0.40, blue: 0.55))
            }

            Divider()

            Text("Move to")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(red: 0.40, green: 0.50, blue: 0.65))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FlowLane.allCases) { lane in
                        Button {
                            store.move(card: card, to: lane)
                            isPresented = false
                        } label: {
                            Text(lane.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(card.lane == lane ? .white : lane.color)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(card.lane == lane ? lane.color : lane.color.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            HStack {
                Button("Delete Card") {
                    store.delete(card)
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(red: 0.80, green: 0.25, blue: 0.22))
                Spacer()
                Button("Done") { isPresented = false }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color(red: 0.18, green: 0.36, blue: 0.68)))
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
