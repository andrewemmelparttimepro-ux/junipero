import SwiftUI

// MARK: - Model

enum FlowLane: String, CaseIterable, Identifiable {
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
        FlowCard(title: "Cognee memory system", owner: "Thrawn", lane: .inProgress, note: "Installed, local server running on :8000"),
        FlowCard(title: "Blender CLI automation path", owner: "R2-D2", lane: .ready, note: "CLI-Anything installed, Phase 1 scope defined"),
        FlowCard(title: "GUI control layer research", owner: "Qui-Gon", lane: .inbox, note: "High priority — major autonomy unlock"),
        FlowCard(title: "Persistent dedicated agent sessions", owner: "Thrawn", lane: .blocked, note: "Needs compatible surface/runtime"),
        FlowCard(title: "Autonomy boundaries and command structure", owner: "Thrawn", lane: .inProgress, note: "APPROVAL_BOUNDARIES.md defined, evolving"),
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

// MARK: - Board View

struct FlowBoardView: View {
    @StateObject private var store = FlowBoardStore()
    @EnvironmentObject var flowTab: FlowTabStore
    @State private var showAdd = false
    @State private var selectedCard: FlowCard? = nil

    var body: some View {
        ZStack {
            // Full-window obsidian backdrop with Sith red ambient
            ZStack {
                Color.obsidian.ignoresSafeArea()
                RadialGradient(colors: [Color.chissDeep.opacity(0.55), Color.clear], center: .topLeading, startRadius: 0, endRadius: 800)
                    .ignoresSafeArea()
                RadialGradient(colors: [Color.sithRed.opacity(0.28), Color.clear], center: .bottomTrailing, startRadius: 0, endRadius: 700)
                    .ignoresSafeArea()
                RadialGradient(colors: [Color.sithRed.opacity(0.12), Color.clear], center: .bottomLeading, startRadius: 0, endRadius: 450)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Toolbar
                HStack(spacing: 14) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) { flowTab.showFlow = false }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                            Text("Back")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(Color.chissPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color.chissDeep.opacity(0.55))
                                .overlay(Capsule().stroke(Color.chissPrimary.opacity(0.35), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("FLOW")
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .tracking(4)
                            .foregroundColor(Color.chissPrimary)
                            .shadow(color: Color.chissPrimary.opacity(0.40), radius: 10)
                        Text("\(store.cards.count) cards across \(FlowLane.allCases.count) lanes")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.40))
                    }

                    Spacer()

                    // Lane summary pills
                    HStack(spacing: 6) {
                        ForEach(FlowLane.allCases) { lane in
                            let count = store.cards(in: lane).count
                            if count > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: lane.icon)
                                        .font(.system(size: 9, weight: .bold))
                                    Text("\(count)")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundColor(lane.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(lane.accentColor.opacity(0.12)).overlay(Capsule().stroke(lane.accentColor.opacity(0.28), lineWidth: 1)))
                            }
                        }
                    }

                    Button(action: { showAdd = true }) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("Add")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color.chissDeep)
                                .overlay(Capsule().stroke(Color.chissPrimary.opacity(0.55), lineWidth: 1))
                        )
                        .shadow(color: Color.chissPrimary.opacity(0.25), radius: 8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(
                    ZStack {
                        Color.obsidianMid.opacity(0.92)
                        LinearGradient(colors: [Color.chissDeep.opacity(0.35), Color.clear], startPoint: .top, endPoint: .bottom)
                    }
                )
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.chissPrimary.opacity(0.12)).frame(height: 1)
                }

                // Kanban columns — full width, scrollable horizontally
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(FlowLane.allCases) { lane in
                            FlowLaneColumn(lane: lane, store: store, onSelect: { selectedCard = $0 })
                                .frame(width: 260)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showAdd) {
            AddFlowCardSheet(store: store, isPresented: $showAdd)
        }
        .sheet(item: $selectedCard) { card in
            FlowCardDetailSheet(
                card: card,
                store: store,
                isPresented: Binding(get: { selectedCard?.id == card.id }, set: { if !$0 { selectedCard = nil } })
            )
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
        VStack(alignment: .leading, spacing: 10) {
            // Lane header
            HStack(spacing: 8) {
                Image(systemName: lane.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(lane.accentColor)
                    .shadow(color: lane.glowColor.opacity(0.70), radius: 6)
                Text(lane.rawValue.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.5)
                    .foregroundColor(lane.accentColor)
                    .shadow(color: lane.glowColor.opacity(0.50), radius: 5)
                Spacer()
                Text("\(cards.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(lane.accentColor.opacity(0.80))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(lane.accentColor.opacity(0.14)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.obsidianMid)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(lane.accentColor.opacity(0.30), lineWidth: 1)
                    )
                    .shadow(color: lane.glowColor.opacity(0.18), radius: 8)
            )

            // Cards
            VStack(spacing: 10) {
                ForEach(cards) { card in
                    FlowCardView(card: card, store: store, onTap: { onSelect(card) })
                }

                if cards.isEmpty {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(lane.accentColor.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [5]))
                        Text("Empty")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.22))
                    }
                    .frame(minHeight: 52)
                }
            }
        }
    }
}

// MARK: - Card View

struct FlowCardView: View {
    let card: FlowCard
    @ObservedObject var store: FlowBoardStore
    let onTap: () -> Void

    private var allLanes: [FlowLane] { FlowLane.allCases }
    private var idx: Int { allLanes.firstIndex(of: card.lane) ?? 0 }
    private var prev: FlowLane? { idx > 0 ? allLanes[idx - 1] : nil }
    private var next: FlowLane? { idx < allLanes.count - 1 ? allLanes[idx + 1] : nil }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(card.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.90))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !card.note.isEmpty {
                    Text(card.note)
                        .font(.system(size: 10.5))
                        .foregroundColor(Color.chissPrimary.opacity(0.75))
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Text(card.owner)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(card.lane == .blocked ? Color.sithGlow : Color.chissPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(card.lane == .blocked
                                ? Color.sithRed.opacity(0.18)
                                : Color.chissDeep.opacity(0.50))
                            .overlay(Capsule().stroke(card.lane == .blocked
                                ? Color.sithGlow.opacity(0.40)
                                : Color.chissPrimary.opacity(0.28), lineWidth: 1))
                        )

                    Spacer()

                    HStack(spacing: 4) {
                        if let p = prev {
                            Button { withAnimation(.spring(response: 0.28)) { store.move(card: card, to: p) } } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(Color.chissPrimary.opacity(0.80))
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(Color.chissDeep.opacity(0.55)))
                            }
                            .buttonStyle(.plain)
                        }
                        if let n = next {
                            Button { withAnimation(.spring(response: 0.28)) { store.move(card: card, to: n) } } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(card.lane == .blocked ? Color.sithGlow : Color.chissPrimary)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(card.lane == .blocked ? Color.sithRed.opacity(0.28) : Color.chissDeep.opacity(0.55)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.obsidianMid)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(card.lane.accentColor.opacity(card.lane == .blocked ? 0.55 : 0.22), lineWidth: 1)
                    )
            )
            .shadow(color: card.lane.glowColor.opacity(card.lane == .blocked ? 0.35 : 0.10), radius: card.lane == .blocked ? 12 : 5)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - Add Card Sheet

struct AddFlowCardSheet: View {
    @ObservedObject var store: FlowBoardStore
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var owner = "Thrawn"
    @State private var lane: FlowLane = .inbox
    @State private var note = ""

    var body: some View {
        ZStack {
            Color.obsidian.ignoresSafeArea()
            RadialGradient(colors: [Color.chissDeep.opacity(0.55), Color.clear], center: .topLeading, startRadius: 0, endRadius: 400)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("New Flow Card")
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .tracking(1)
                    .foregroundColor(Color.chissPrimary)
                    .shadow(color: Color.chissPrimary.opacity(0.35), radius: 8)

                sheetField("Title", text: $title)
                sheetField("Note", text: $note)

                HStack {
                    sheetLabel("Owner")
                    Picker("", selection: $owner) {
                        ForEach(["Thrawn","R2-D2","C-3PO","Qui-Gon","Lando","Boba"], id: \.self) { Text($0).foregroundColor(.white) }
                    }
                    .frame(width: 130)
                }

                HStack {
                    sheetLabel("Lane")
                    Picker("", selection: $lane) {
                        ForEach(FlowLane.allCases) { Text($0.rawValue).tag($0).foregroundColor(.white) }
                    }
                    .frame(width: 150)
                }

                HStack {
                    Spacer()
                    Button("Cancel") { isPresented = false }
                        .buttonStyle(.plain)
                        .foregroundColor(Color.chissPrimary.opacity(0.70))

                    Button("Add Card") {
                        guard !title.isEmpty else { return }
                        store.add(title: title, owner: owner, lane: lane)
                        isPresented = false
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.chissDeep).overlay(Capsule().stroke(Color.chissPrimary.opacity(0.55), lineWidth: 1)))
                    .disabled(title.isEmpty)
                }
            }
            .padding(28)
            .frame(width: 400)
        }
    }

    private func sheetField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            sheetLabel(label)
            TextField(label, text: text)
                .textFieldStyle(.plain)
                .foregroundColor(.white.opacity(0.92))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.obsidianMid).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.chissPrimary.opacity(0.25), lineWidth: 1)))
        }
    }

    private func sheetLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color.chissPrimary.opacity(0.70))
    }
}

// MARK: - Card Detail Sheet

struct FlowCardDetailSheet: View {
    let card: FlowCard
    @ObservedObject var store: FlowBoardStore
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.obsidian.ignoresSafeArea()
            RadialGradient(colors: [Color.chissDeep.opacity(0.50), Color.clear], center: .topLeading, startRadius: 0, endRadius: 400)
                .ignoresSafeArea()
            RadialGradient(colors: [Color.sithRed.opacity(0.10), Color.clear], center: .bottomTrailing, startRadius: 0, endRadius: 300)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text(card.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.95))

                HStack {
                    Label(card.owner, systemImage: "person.fill").foregroundColor(Color.chissPrimary)
                    Spacer()
                    Label(card.lane.rawValue, systemImage: card.lane.icon).foregroundColor(card.lane.accentColor)
                }
                .font(.system(size: 12, weight: .semibold))

                if !card.note.isEmpty {
                    Text(card.note).font(.system(size: 13)).foregroundColor(Color.chissPrimary.opacity(0.80))
                }

                Divider().background(Color.chissPrimary.opacity(0.20))

                Text("Move to")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.chissPrimary.opacity(0.65))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FlowLane.allCases) { lane in
                            Button {
                                store.move(card: card, to: lane)
                                isPresented = false
                            } label: {
                                Text(lane.rawValue)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(card.lane == lane ? .white : lane.accentColor)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(card.lane == lane ? lane.accentColor : lane.accentColor.opacity(0.12)).overlay(Capsule().stroke(lane.accentColor.opacity(0.40), lineWidth: 1)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider().background(Color.sithRed.opacity(0.25))

                HStack {
                    Button("Delete") {
                        store.delete(card)
                        isPresented = false
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color.sithGlow)
                    .shadow(color: Color.sithGlow.opacity(0.50), radius: 6)

                    Spacer()

                    Button("Done") { isPresented = false }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.chissDeep).overlay(Capsule().stroke(Color.chissPrimary.opacity(0.55), lineWidth: 1)))
                }
            }
            .padding(28)
            .frame(width: 400)
        }
    }
}
