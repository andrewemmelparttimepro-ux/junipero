import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Product Board Switcher
//
// The top-of-panel row that replaces the seven-tab console grid. Each button
// is a full logo mark, not a text tab. Clicking a button opens the product's
// infinite freeform board full-screen; the seven console utilities live in
// the collapsible ConsoleUtilityRail on the right edge.

struct ProductBoardSwitcher: View {
    @EnvironmentObject var nav: ConsoleNavigationStore

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ProductBoardID.allCases) { board in
                ProductLogoButton(board: board) {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        nav.selectProjectBoard(board)
                        nav.showBoardFullScreen = true
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// A single logo button. Renders the product's PNG logo prominently, with a
/// subtle brand-accent glow on hover.
struct ProductLogoButton: View {
    let board: ProductBoardID
    let action: () -> Void

    @State private var isHovered = false

    private var logoImage: NSImage? {
        guard let url = Bundle.module.url(forResource: board.logoResource, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.obsidianMid.opacity(0.96),
                                Color.obsidian.opacity(0.96),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                board.accentColor.opacity(isHovered ? 0.62 : 0.22),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: board.accentColor.opacity(isHovered ? 0.35 : 0.10),
                            radius: isHovered ? 12 : 6)

                if let logoImage {
                    Image(nsImage: logoImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                } else {
                    // Fallback if the PNG can't be found in the bundle
                    // (should never trigger; guard rail for release builds).
                    VStack(spacing: 6) {
                        Image(systemName: board.iconFallback)
                            .font(.system(size: 22, weight: .bold))
                        Text(board.displayName)
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1)
                    }
                    .foregroundColor(board.accentColor)
                    .padding(14)
                }
            }
            .frame(height: 66)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help("Open the \(board.displayName) infinite freeform board")
    }
}

// MARK: - Console Utility Rail
//
// The seven console destinations (Command, Objectives, Briefings, Agents,
// Threads, Approvals, Deliverables) live here — collapsed to a 48-pt strip
// on the right edge by default, expandable on tap. Auto-collapses after a
// selection so the primary canvas keeps its full width.

struct ConsoleUtilityRail: View {
    @EnvironmentObject var nav: ConsoleNavigationStore
    @AppStorage("thrawn.consoleUtilityRailExpanded") private var isExpanded = false

    var body: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.right" : "sidebar.right")
                        .font(.system(size: 11, weight: .heavy))
                        .frame(width: 20)
                    if isExpanded {
                        Text("CONSOLE")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .tracking(1.6)
                        Spacer()
                    }
                }
                .foregroundColor(Color.chissPrimary.opacity(0.90))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, isExpanded ? 12 : 8)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.chissDeep.opacity(0.30))
                )
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse console navigation" : "Open console navigation")

            Rectangle()
                .fill(Color.chissPrimary.opacity(0.12))
                .frame(height: 1)

            ForEach(ConsoleSection.allCases) { section in
                utilityButton(section)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: isExpanded ? 176 : 48)
        .frame(maxHeight: .infinity)
        .background(
            Color.obsidianMid.opacity(0.94)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.chissPrimary.opacity(0.14))
                        .frame(width: 1)
                }
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isExpanded)
    }

    private func utilityButton(_ section: ConsoleSection) -> some View {
        let selected = nav.selectedProjectBoard == nil
            && nav.showBoardFullScreen == false
            && nav.selectedSection == section
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                nav.selectSection(section)
                nav.showBoardFullScreen = false
                isExpanded = false
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 20)
                if isExpanded {
                    Text(section.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                }
            }
            .foregroundColor(selected ? .white : Color.white.opacity(0.50))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, isExpanded ? 12 : 8)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Color.chissDeep.opacity(0.90) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(selected ? Color.chissPrimary.opacity(0.48) : Color.clear, lineWidth: 1)
                    )
            )
            .shadow(color: selected ? Color.chissPrimary.opacity(0.18) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Open \(section.rawValue)" : section.rawValue)
    }
}

// MARK: - Full-Screen Product Board Overlay
//
// The big daddy. When a product logo is tapped, this overlay covers the
// entire window with the product's infinite freeform canvas. Exits via a
// prominent X button in the top-right corner — oversized so it can't be
// missed.

struct ProductBoardFullScreen: View {
    let board: ProductBoardID
    let onDismiss: () -> Void

    @EnvironmentObject private var store: ProductBoardStore
    @EnvironmentObject private var nav: ConsoleNavigationStore

    private var logoImage: NSImage? {
        guard let url = Bundle.module.url(forResource: board.logoResource, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        ZStack {
            // Whiteboard backdrop — the board owns the screen while it's open
            Color(red: 0.955, green: 0.945, blue: 0.915)
                .ignoresSafeArea()

            // The freeform infinite canvas fills everything under the chrome
            ProductBoardCanvas(board: board)
                .environmentObject(store)

            // Chrome layer
            VStack(spacing: 0) {
                overlayHeader
                Spacer()
                overlayFooter
            }
            .padding(.top, 32)     // keep clear of the traffic-light strip
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .allowsHitTesting(true)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
    }

    // MARK: - Header row (logo + board switcher + oversized X)

    @ViewBuilder
    private var overlayHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            // Board identity (logo + name)
            HStack(spacing: 12) {
                if let logoImage {
                    Image(nsImage: logoImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 46)
                } else {
                    Image(systemName: board.iconFallback)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(board.accentColor)
                        .frame(height: 46)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.obsidianMid.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(board.accentColor.opacity(0.35), lineWidth: 1)
                    )
            )
            .shadow(color: board.accentColor.opacity(0.30), radius: 12)

            Spacer()

            // Inline board switcher — swap boards without exiting the overlay
            HStack(spacing: 8) {
                ForEach(ProductBoardID.allCases) { candidate in
                    let selected = candidate == board
                    Button {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                            nav.selectProjectBoard(candidate)
                        }
                    } label: {
                        Text(candidate.shortName)
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1.4)
                            .foregroundColor(selected ? .white : Color.white.opacity(0.52))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selected ? candidate.accentColor.opacity(0.22) : Color.white.opacity(0.05))
                                    .overlay(
                                        Capsule()
                                            .stroke(selected ? candidate.accentColor.opacity(0.60) : Color.white.opacity(0.05), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Switch to \(candidate.displayName)")
                }
            }
            .padding(6)
            .background(Capsule().fill(Color.obsidianMid.opacity(0.72)))

            // Oversized X exit — the biggest control on screen so it's
            // impossible to miss. Andrew's request: "make the x slightly
            // oversized in its typical spot".
            OversizedExitButton(accent: board.accentColor) {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    onDismiss()
                }
            }
        }
    }

    // MARK: - Footer hint

    @ViewBuilder
    private var overlayFooter: some View {
        HStack {
            Text("DOUBLE-CLICK TO ADD A NOTE  ·  DROP FILES TO PIN THEM  ·  DRAG TO PAN  ·  ⌘ SCROLL, PINCH OR ± TO ZOOM  ·  ⌫ TO DELETE SELECTED")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(Color.white.opacity(0.30))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.obsidianMid.opacity(0.78)))
            Spacer()
        }
    }
}

/// A prominent close button — larger than typical macOS chrome so it reads
/// as the primary escape from the full-screen board.
struct OversizedExitButton: View {
    let accent: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.obsidianMid,
                                Color.obsidian,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                isHovered ? Color(red: 0.95, green: 0.28, blue: 0.32).opacity(0.85)
                                          : Color.white.opacity(0.14),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: isHovered ? Color(red: 0.95, green: 0.28, blue: 0.32).opacity(0.45)
                                            : Color.black.opacity(0.30),
                            radius: isHovered ? 14 : 6)

                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(isHovered ? Color(red: 0.98, green: 0.42, blue: 0.46) : Color.white.opacity(0.78))
            }
            .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.14)) { isHovered = hovering }
        }
        .keyboardShortcut(.escape, modifiers: [])
        .help("Close board (Esc)")
    }
}

// MARK: - Freeform Canvas
//
// The actual infinite board. Apple-Freeform semantics: blank canvas, drag
// anywhere to add anything anywhere. Evernote-infinite semantics: pans
// without bounds, notes can live in negative coordinates. Every note
// persists per-board.

struct ProductBoardCanvas: View {
    let board: ProductBoardID
    @EnvironmentObject private var store: ProductBoardStore

    // Viewport state (persists only within a session — resets each launch
    // per common canvas UX; the notes themselves persist).
    @State private var viewportOffset: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @GestureState private var panTranslation: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1

    // Note-level interaction state
    @State private var draggedNodeID: String?
    @State private var draggedTranslation: CGSize = .zero
    @State private var editingNodeID: String?
    @State private var selectedNodeID: String?
    @State private var isDropTargeted = false

    private var effectiveScale: CGFloat {
        min(max(zoom * pinchScale, 0.30), 2.20)
    }

    private var effectiveOffset: CGSize {
        CGSize(
            width: viewportOffset.width + panTranslation.width,
            height: viewportOffset.height + panTranslation.height
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let nodes = store.nodes(for: board)

            ZStack {
                // ⌘ + scroll wheel zooms, anchored at the cursor. The catcher
                // is click-transparent — it only consumes scroll events with
                // Command held while the cursor is over the canvas.
                ScrollWheelZoomCatcher { deltaY, location in
                    zoomBy(deltaY: deltaY, at: location, in: proxy.size)
                }

                // Infinite dot grid background — the visual cue that the
                // canvas has no edges
                ZStack {
                    AgedPaperBase()
                    InfinitePaperGrid(offset: effectiveOffset, scale: effectiveScale)
                }
                .contentShape(Rectangle())
                .gesture(panGesture)
                .simultaneousGesture(magnificationGesture)
                .onTapGesture {
                    if editingNodeID != nil {
                        // Clicking away commits (or discards) the open edit —
                        // the note card's onChange(isEditing) fires the commit.
                        editingNodeID = nil
                    } else {
                        selectedNodeID = nil
                    }
                }
                .simultaneousGesture(
                    SpatialTapGesture(count: 2, coordinateSpace: .local)
                        .onEnded { value in
                            addNote(atScreenPoint: value.location, in: proxy.size)
                        }
                )

                // Notes layer
                ForEach(nodes) { node in
                    let dragOffset = (draggedNodeID == node.id) ? draggedTranslation : .zero
                    FreeformNoteCard(
                        node: node,
                        accent: board.accentColor,
                        isEditing: editingNodeID == node.id,
                        isSelected: selectedNodeID == node.id,
                        onCommit: { newTitle, newBody in
                            // File cards never enter text-edit mode; guard so
                            // the empty-note discard can't touch them.
                            guard node.filePath == nil else {
                                editingNodeID = nil
                                return
                            }
                            let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            let body = newBody.trimmingCharacters(in: .whitespacesAndNewlines)
                            if title.isEmpty && body.isEmpty {
                                // Freeform behavior: an untouched empty note
                                // is discarded rather than left as litter.
                                store.deleteNode(node.id, on: board)
                                if selectedNodeID == node.id { selectedNodeID = nil }
                            } else {
                                store.updateNode(node.id, on: board, title: title, body: body)
                            }
                            editingNodeID = nil
                        },
                        onBeginEdit: {
                            editingNodeID = node.id
                            selectedNodeID = node.id
                        },
                        onSelect: {
                            selectedNodeID = node.id
                        },
                        onDelete: {
                            store.deleteNode(node.id, on: board)
                            if selectedNodeID == node.id { selectedNodeID = nil }
                            if editingNodeID == node.id { editingNodeID = nil }
                        }
                    )
                    .scaleEffect(effectiveScale, anchor: .center)
                    .position(
                        x: proxy.size.width / 2
                            + effectiveOffset.width
                            + CGFloat(node.position.x) * effectiveScale
                            + dragOffset.width,
                        y: proxy.size.height / 2
                            + effectiveOffset.height
                            + CGFloat(node.position.y) * effectiveScale
                            + dragOffset.height
                    )
                    .gesture(nodeDragGesture(node))
                }

                // Empty-state hint layer — only when the board has no notes
                if nodes.isEmpty {
                    EmptyBoardHint(board: board) {
                        addNoteAtViewportCenter()
                    }
                }

                // Bottom-right floating controls
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        canvasControls
                    }
                }
                .padding(24)
            }
            .clipped()
            .onDeleteCommand {
                // ⌫ deletes the selected note (matches the footer hint).
                guard editingNodeID == nil, let selected = selectedNodeID else { return }
                store.deleteNode(selected, on: board)
                selectedNodeID = nil
            }
            // Drag files from Finder onto the board — they pin as document
            // cards at the drop location. Link, not copy: double-click opens
            // the live original.
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers, location in
                handleFileDrop(providers, at: location, in: proxy.size)
            }
            .overlay {
                if isDropTargeted {
                    Rectangle()
                        .stroke(board.accentColor.opacity(0.70), lineWidth: 3)
                        .background(board.accentColor.opacity(0.05))
                        .allowsHitTesting(false)
                }
            }
        }
        .onChange(of: board) { _ in
            recenter()
            selectedNodeID = nil
            editingNodeID = nil
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var canvasControls: some View {
        HStack(spacing: 6) {
            iconButton("minus.magnifyingglass", help: "Zoom out") {
                withAnimation(.easeInOut(duration: 0.14)) {
                    zoom = max(0.30, zoom - 0.15)
                }
            }
            Text("\(Int(effectiveScale * 100))%")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.60))
                .frame(width: 42)
            iconButton("plus.magnifyingglass", help: "Zoom in") {
                withAnimation(.easeInOut(duration: 0.14)) {
                    zoom = min(2.20, zoom + 0.15)
                }
            }
            iconButton("scope", help: "Recenter") {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    recenter()
                }
            }
            iconButton("plus", help: "Add note (or double-click canvas)") {
                addNoteAtViewportCenter()
            }
        }
        .padding(6)
        .background(
            Capsule()
                .fill(Color.obsidianMid.opacity(0.94))
                .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.30), radius: 10)
    }

    private func iconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color.white.opacity(0.72))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.045)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($panTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                viewportOffset.width += value.translation.width
                viewportOffset.height += value.translation.height
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in state = value }
            .onEnded { value in
                zoom = min(max(zoom * value, 0.30), 2.20)
            }
    }

    private func nodeDragGesture(_ node: ProductBoardNode) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                draggedNodeID = node.id
                draggedTranslation = value.translation
                selectedNodeID = node.id
            }
            .onEnded { value in
                let scale = max(effectiveScale, 0.30)
                store.moveNode(
                    node.id,
                    on: board,
                    to: ProductBoardPoint(
                        node.position.x + Double(value.translation.width / scale),
                        node.position.y + Double(value.translation.height / scale)
                    )
                )
                draggedNodeID = nil
                draggedTranslation = .zero
            }
    }

    // MARK: - Helpers

    private func addNoteAtViewportCenter() {
        let scale = max(effectiveScale, 0.30)
        let boardPoint = ProductBoardPoint(
            Double(-viewportOffset.width / scale),
            Double(-viewportOffset.height / scale)
        )
        beginEditing(store.addNote(to: board, title: "", body: "", at: boardPoint))
    }

    /// Add a note exactly where the user double-clicked, converting the
    /// screen-space location through the current pan + zoom transform.
    private func addNote(atScreenPoint point: CGPoint, in size: CGSize) {
        let scale = max(effectiveScale, 0.30)
        let boardPoint = ProductBoardPoint(
            Double((point.x - size.width / 2 - viewportOffset.width) / scale),
            Double((point.y - size.height / 2 - viewportOffset.height) / scale)
        )
        beginEditing(store.addNote(to: board, title: "", body: "", at: boardPoint))
    }

    private func beginEditing(_ node: ProductBoardNode) {
        selectedNodeID = node.id
        editingNodeID = node.id
    }

    /// Resolve dropped file URLs and pin each as a card at the drop point.
    /// Multiple files cascade slightly so they don't stack invisibly.
    private func handleFileDrop(
        _ providers: [NSItemProvider],
        at location: CGPoint,
        in size: CGSize
    ) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }

        for (index, provider) in fileProviders.enumerated() {
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, error in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let direct = item as? URL {
                    url = direct
                } else {
                    url = nil
                }
                guard let url else {
                    FlightRecorder.logError(
                        source: "board:drop",
                        message: "Could not read dropped item: \(error?.localizedDescription ?? "unknown provider payload")"
                    )
                    return
                }
                Task { @MainActor in
                    let cascade = CGFloat(index) * 26
                    let scale = max(effectiveScale, 0.30)
                    let boardPoint = ProductBoardPoint(
                        Double((location.x + cascade - size.width / 2 - viewportOffset.width) / scale),
                        Double((location.y + cascade - size.height / 2 - viewportOffset.height) / scale)
                    )
                    let node = store.addFile(to: board, url: url, at: boardPoint)
                    selectedNodeID = node.id
                }
            }
        }
        return true
    }

    private func recenter() {
        viewportOffset = .zero
        zoom = 1
    }

    /// Cursor-anchored zoom: the board point under the pointer stays put
    /// while everything scales around it — standard whiteboard mechanics.
    private func zoomBy(deltaY: CGFloat, at location: CGPoint, in size: CGSize) {
        let old = zoom
        // Exponential feel: small wheel ticks nudge, fast trackpad swipes fly.
        let next = min(max(old * pow(1.004, deltaY), 0.30), 2.20)
        guard abs(next - old) > 0.0001 else { return }

        let cursorFromCenter = CGPoint(
            x: location.x - size.width / 2,
            y: location.y - size.height / 2
        )
        // boardPoint = (cursor - offset) / oldScale; keep it stationary:
        let boardX = (cursorFromCenter.x - viewportOffset.width) / old
        let boardY = (cursorFromCenter.y - viewportOffset.height) / old
        viewportOffset.width = cursorFromCenter.x - boardX * next
        viewportOffset.height = cursorFromCenter.y - boardY * next
        zoom = next
    }
}

// MARK: - ⌘ + scroll wheel zoom catcher
//
// SwiftUI exposes no scroll-wheel events on macOS, so this representable
// anchors an NSView in the canvas purely for geometry + lifecycle and
// installs a local event monitor. The view is click-transparent (hitTest
// returns nil) so every SwiftUI gesture — pan, tap, drag, drop — is
// untouched. The monitor consumes a scroll event only when Command is held
// AND the cursor is inside the canvas bounds; everything else passes through.

private struct ScrollWheelZoomCatcher: NSViewRepresentable {
    let onZoom: (_ deltaY: CGFloat, _ location: CGPoint) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onZoom = onZoom
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onZoom = onZoom
    }

    final class CatcherView: NSView {
        var onZoom: ((CGFloat, CGPoint) -> Void)?
        private var monitor: Any?

        // Top-left origin so converted coordinates match SwiftUI's space.
        override var isFlipped: Bool { true }

        // Never participate in hit testing — clicks, drags, and drops all
        // belong to the SwiftUI layers.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                installMonitorIfNeeded()
            } else {
                removeMonitorIfNeeded()
            }
        }

        private func installMonitorIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      let window = self.window,
                      event.window === window,
                      event.modifierFlags.contains(.command)
                else { return event }
                let local = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(local) else { return event }
                self.onZoom?(event.scrollingDeltaY, local)
                return nil   // consumed — don't let anything scroll underneath
            }
        }

        private func removeMonitorIfNeeded() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

// MARK: - Infinite Dot Grid

// MARK: - Whiteboard Paper
//
// The board reads as an actual whiteboard: warm off-white base, a faint
// graph-paper grid, gently aged edges, and a whisper of paper grain.

private struct AgedPaperBase: View {
    var body: some View {
        ZStack {
            // Warm off-white base
            Color(red: 0.955, green: 0.945, blue: 0.915)
            // Bright center — like light hitting the board
            RadialGradient(
                colors: [Color.white.opacity(0.50), .clear],
                center: .center, startRadius: 60, endRadius: 900
            )
            // Aged, slightly darkened edges
            RadialGradient(
                colors: [.clear, Color(red: 0.60, green: 0.55, blue: 0.45).opacity(0.18)],
                center: .center, startRadius: 420, endRadius: 1500
            )
            PaperGrainTexture()
                .opacity(0.05)
        }
    }
}

private struct PaperGrainTexture: View {
    var body: some View {
        Canvas { ctx, size in
            guard size.width > 1, size.height > 1 else { return }
            var rng = SystemRandomNumberGenerator()
            for _ in 0..<Int(size.width * size.height * 0.006) {
                let x = CGFloat(rng.next() % UInt64(size.width))
                let y = CGFloat(rng.next() % UInt64(size.height))
                let alpha = Double(rng.next() % 100) / 100.0 * 0.5
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: 1.1, height: 1.1)),
                    with: .color(Color(red: 0.35, green: 0.30, blue: 0.22).opacity(alpha))
                )
            }
        }
    }
}

private struct InfinitePaperGrid: View {
    let offset: CGSize
    let scale: CGFloat

    var body: some View {
        Canvas { context, size in
            let spacing = max(18, 36 * scale)
            let startX = offset.width.truncatingRemainder(dividingBy: spacing)
            let startY = offset.height.truncatingRemainder(dividingBy: spacing)
            let line = Color(red: 0.42, green: 0.50, blue: 0.60).opacity(0.15)

            var x = startX - spacing
            while x <= size.width + spacing {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(line), lineWidth: 0.6)
                x += spacing
            }
            var y = startY - spacing
            while y <= size.height + spacing {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(line), lineWidth: 0.6)
                y += spacing
            }
        }
    }
}

// MARK: - Freeform Note Card

private struct FreeformNoteCard: View {
    let node: ProductBoardNode
    let accent: Color
    let isEditing: Bool
    let isSelected: Bool
    let onCommit: (String, String) -> Void
    let onBeginEdit: () -> Void
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var titleDraft: String
    @State private var bodyDraft: String
    @FocusState private var titleFocused: Bool

    init(
        node: ProductBoardNode,
        accent: Color,
        isEditing: Bool,
        isSelected: Bool,
        onCommit: @escaping (String, String) -> Void,
        onBeginEdit: @escaping () -> Void,
        onSelect: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.node = node
        self.accent = accent
        self.isEditing = isEditing
        self.isSelected = isSelected
        self.onCommit = onCommit
        self.onBeginEdit = onBeginEdit
        self.onSelect = onSelect
        self.onDelete = onDelete
        _titleDraft = State(initialValue: node.title)
        _bodyDraft = State(initialValue: node.body)
    }

    /// Dark ink on light stickies — the whiteboard look.
    private static let ink = Color(red: 0.18, green: 0.16, blue: 0.13)

    private var noteTint: Color {
        // Pastel sticky-note colors on the whiteboard.
        let palette: [Color] = [
            Color(red: 1.00, green: 0.93, blue: 0.58),   // sticky yellow
            Color(red: 0.74, green: 0.88, blue: 1.00),   // sky
            Color(red: 1.00, green: 0.80, blue: 0.84),   // pink
            Color(red: 0.80, green: 0.94, blue: 0.76),   // mint
            Color(red: 0.92, green: 0.84, blue: 1.00),   // lilac
        ]
        return palette[node.colorSlot % palette.count]
    }

    private var isFile: Bool { node.filePath != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let filePath = node.filePath {
                fileContent(filePath)
            } else if isEditing {
                TextField("Note title", text: $titleDraft, onCommit: commit)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Self.ink)
                    .focused($titleFocused)
                TextEditor(text: $bodyDraft)
                    .font(.system(size: 11))
                    .foregroundColor(Self.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 44, maxHeight: 120)
            } else {
                Text(node.title.isEmpty ? "Untitled" : node.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(node.title.isEmpty ? Self.ink.opacity(0.38) : Self.ink)
                    .lineLimit(3)
                if !node.body.isEmpty {
                    Text(node.body)
                        .font(.system(size: 10.5))
                        .foregroundColor(Self.ink.opacity(0.72))
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(width: 218, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isFile
                            // Documents read as white paper pinned to the board
                            ? [Color.white, Color(red: 0.97, green: 0.96, blue: 0.93)]
                            : [noteTint, noteTint.opacity(0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            Color.black.opacity(isSelected ? 0.38 : 0.10),
                            lineWidth: isSelected ? 1.4 : 1
                        )
                )
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.22 : 0.12), radius: isSelected ? 12 : 6, x: 0, y: 4)
        .overlay(alignment: .topTrailing) {
            if isSelected && !isEditing {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(red: 0.85, green: 0.22, blue: 0.26))
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain)
                .offset(x: 8, y: -8)
                .help("Delete note")
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(count: 2) {
            if let filePath = node.filePath {
                openFile(filePath)
            } else {
                onBeginEdit()
            }
        }
        .onTapGesture(count: 1) {
            onSelect()
        }
        .help(isFile ? "Double-click to open · drag to move" : "Double-click to edit · drag to move")
        .onChange(of: isEditing) { editing in
            if editing {
                titleDraft = node.title
                bodyDraft = node.body
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    titleFocused = true
                }
            } else {
                // ALWAYS commit on exit — the commit handler is where empty
                // notes get discarded, so skipping it when drafts look
                // unchanged would leave blank notes behind.
                onCommit(titleDraft, bodyDraft)
            }
        }
    }

    private func commit() {
        onCommit(titleDraft, bodyDraft)
    }

    @ViewBuilder
    private func fileContent(_ filePath: String) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: filePath))
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(node.title)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(Self.ink)
                    .lineLimit(2)
                Text(fileSubtitle(filePath))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundColor(Self.ink.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func fileSubtitle(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.uppercased()
        let kind = ext.isEmpty ? "FILE" : ext
        guard FileManager.default.fileExists(atPath: path) else {
            return "\(kind) · MISSING"
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let bytes = (attrs?[.size] as? Int64) ?? 0
        guard bytes > 0 else { return kind }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return "\(kind) · \(size.uppercased())"
    }

    /// PDFs route to mRk — NDAI's own markup app — when the desktop build is
    /// installed. Everything else (and PDFs when mRk is absent) opens in the
    /// system default app, so double-click never silently does nothing.
    private func openFile(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if url.pathExtension.lowercased() == "pdf",
           let mrk = NSWorkspace.shared.urlForApplication(
               withBundleIdentifier: "pro.ndai.mrk"
           ) {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: mrk,
                configuration: NSWorkspace.OpenConfiguration()
            )
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Empty State

private struct EmptyBoardHint: View {
    let board: ProductBoardID
    let onAdd: () -> Void

    private static let ink = Color(red: 0.30, green: 0.28, blue: 0.24)

    var body: some View {
        VStack(spacing: 14) {
            Text("BLANK WHITEBOARD")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(2.2)
                .foregroundColor(board.accentColor.opacity(0.92))
            Text("Double-click anywhere to add a note.\nDrag notes to move them. Pan and zoom the canvas.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Self.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Button(action: onAdd) {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .heavy))
                    Text("Add your first note")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(Color(red: 0.15, green: 0.14, blue: 0.12))
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(
                    Capsule()
                        .fill(board.accentColor.opacity(0.30))
                        .overlay(Capsule().stroke(board.accentColor.opacity(0.65), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.10), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 6)
    }
}

// MARK: - Inline board panel: live thread feed
//
// ConsoleSectionBody dispatches to `ProductBoardView(board:)` when a project
// board is the current selection but the full-screen overlay is closed.
// Instead of dead space with a "reopen" button, this surface is a live feed
// of Andrew's Thrawn threads — most recently updated always on top, a green
// indicator when a thread has something waiting, and a subtle affiliation
// tag showing which product / company / project the thread is tied to.

struct ProductBoardView: View {
    let board: ProductBoardID
    @EnvironmentObject private var nav: ConsoleNavigationStore
    @EnvironmentObject private var threadStore: ThreadStore

    private var logoImage: NSImage? {
        guard let url = Bundle.module.url(forResource: board.logoResource, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    /// Most recently updated first — re-sorts live as threads change.
    private var sortedThreads: [ChatThread] {
        threadStore.threads.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Compact board affordance
            HStack(spacing: 12) {
                if let logoImage {
                    Image(nsImage: logoImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 34)
                } else {
                    Image(systemName: board.iconFallback)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(board.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(board.displayName.uppercased())
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(1.6)
                        .foregroundColor(.white.opacity(0.85))
                    Text("Whiteboard ready")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.40))
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        nav.showBoardFullScreen = true
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .heavy))
                        Text("Open board")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(board.accentColor.opacity(0.22))
                            .overlay(Capsule().stroke(board.accentColor.opacity(0.60), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .help("Open the \(board.displayName) whiteboard full-screen")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.obsidianMid.opacity(0.72))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }

            // Live thread feed
            HStack {
                Text("THREADS · MOST RECENT FIRST")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .tracking(1.8)
                    .foregroundColor(.white.opacity(0.34))
                Spacer()
                if threadStore.unreadThreadCount > 0 {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.ndaiGreen)
                            .frame(width: 6, height: 6)
                            .shadow(color: Color.ndaiGreen.opacity(0.8), radius: 3)
                        Text("\(threadStore.unreadThreadCount) FOR YOU")
                            .font(.system(size: 8.5, weight: .black, design: .monospaced))
                            .tracking(1.2)
                            .foregroundColor(Color.ndaiGreen.opacity(0.88))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            if sortedThreads.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundColor(.white.opacity(0.22))
                    Text("No threads yet. Hit Command to start one with Thrawn.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.40))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sortedThreads) { thread in
                            BoardThreadRow(
                                thread: thread,
                                affiliation: Self.affiliation(for: thread)
                            ) {
                                openThread(thread)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.obsidian.opacity(0.55))
    }

    private func openThread(_ thread: ChatThread) {
        threadStore.markThreadRead(thread.id)
        threadStore.selectedThreadId = thread.id
        withAnimation(.easeInOut(duration: 0.18)) {
            nav.selectSection(.command)
        }
    }

    // MARK: Affiliation detection

    struct Affiliation {
        let label: String
        let color: Color
    }

    /// Best-effort tag for which product / company / project a thread is
    /// about, inferred from its recent message text. Word-boundary matching
    /// for short tokens (OMP) so "company" doesn't false-positive.
    static func affiliation(for thread: ChatThread) -> Affiliation? {
        let corpus = thread.messages.suffix(8).map(\.text).joined(separator: " ").lowercased()
        guard !corpus.isEmpty else { return nil }
        let words = Set(
            corpus.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        )
        if corpus.contains("spas") {
            return Affiliation(label: "SPAS 360", color: ProductBoardID.spas360.accentColor)
        }
        if corpus.contains("hit zero") || corpus.contains("hitzero") {
            return Affiliation(label: "HIT ZERO", color: ProductBoardID.hitZero.accentColor)
        }
        if corpus.contains("sandpro") || words.contains("omp") || corpus.contains("objectivetracker") {
            return Affiliation(label: "SANDPRO OMP", color: ProductBoardID.sandProOMP.accentColor)
        }
        if words.contains("cyclops") {
            return Affiliation(label: "CYCLOPS", color: Color(red: 0.02, green: 0.71, blue: 0.83))
        }
        if words.contains("uniss") {
            return Affiliation(label: "UNISS", color: Color(red: 0.30, green: 0.62, blue: 0.38))
        }
        if words.contains("freewheel") {
            return Affiliation(label: "FREEWHEEL", color: Color(red: 0.85, green: 0.60, blue: 0.25))
        }
        if words.contains("ndai") {
            return Affiliation(label: "NDAI", color: Color.ndaiGreen)
        }
        return nil
    }
}

private struct BoardThreadRow: View {
    let thread: ChatThread
    let affiliation: ProductBoardView.Affiliation?
    let onOpen: () -> Void
    @State private var isHovered = false

    private var hasSomethingForMe: Bool { thread.unreadCount > 0 }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                // Green indicator when Thrawn has something waiting; spinner
                // while a reply is still being generated.
                ZStack {
                    if thread.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.42)
                            .tint(Color.chissPrimary)
                    } else {
                        Circle()
                            .fill(hasSomethingForMe ? Color.ndaiGreen : Color.white.opacity(0.14))
                            .frame(width: 9, height: 9)
                            .shadow(
                                color: hasSomethingForMe ? Color.ndaiGreen.opacity(0.85) : .clear,
                                radius: 4
                            )
                    }
                }
                .frame(width: 14, height: 14)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(thread.userMessagePreview.isEmpty ? "Untitled thread" : thread.userMessagePreview)
                            .font(.system(size: 12, weight: hasSomethingForMe ? .bold : .semibold))
                            .foregroundColor(.white.opacity(hasSomethingForMe ? 0.95 : 0.78))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(thread.formattedDate)
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.32))
                    }

                    if !thread.assistantMessagePreview.isEmpty {
                        Text(thread.assistantMessagePreview)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.46))
                            .lineLimit(2)
                    }

                    if let affiliation {
                        Text(affiliation.label)
                            .font(.system(size: 7.5, weight: .black, design: .monospaced))
                            .tracking(1.2)
                            .foregroundColor(affiliation.color.opacity(0.88))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(affiliation.color.opacity(0.10))
                                    .overlay(Capsule().stroke(affiliation.color.opacity(0.30), lineWidth: 1))
                            )
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.obsidianMid.opacity(isHovered ? 0.95 : 0.78))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(
                                hasSomethingForMe ? Color.ndaiGreen.opacity(0.34) : Color.white.opacity(0.07),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: hasSomethingForMe ? Color.ndaiGreen.opacity(0.10) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open this thread in Command")
    }
}

// MARK: - Product Accent Colors

extension ProductBoardID {
    var accentColor: Color {
        switch self {
        case .spas360:    return Color(red: 0.34, green: 0.72, blue: 0.96)
        case .hitZero:    return Color(red: 0.94, green: 0.28, blue: 0.42)
        case .sandProOMP: return Color.ndaiGreen
        }
    }
}
