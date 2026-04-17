import SwiftUI
import SceneKit

// MARK: - Memory Graph View
//
// SwiftUI wrapper for the 3D SceneKit memory graph. Wraps SCNView
// via NSViewRepresentable for full camera control and hit testing.
// Includes overlay controls: back button, legend, node detail card.

struct MemoryGraphView: View {
    @EnvironmentObject var nav: ConsoleNavigationStore

    @StateObject private var model = MemoryGraphModel()
    @State private var sceneController: MemoryGraphSceneController?
    @State private var selectedNode: GraphNode?

    var body: some View {
        ZStack {
            Color.obsidian.ignoresSafeArea()

            if model.isLoading {
                loadingOverlay
            } else if let controller = sceneController {
                // SceneKit view — full bleed
                SceneKitGraphView(
                    scene: controller.scene,
                    onTap: { point, view in
                        controller.handleTap(at: point, in: view)
                        selectedNode = controller.selectedNode
                    }
                )
                .ignoresSafeArea()

                // Overlay controls
                overlayControls
            }
        }
        .task {
            await model.load()
            let controller = MemoryGraphSceneController(model: model)
            self.sceneController = controller
            await controller.buildScene()
            controller.startDataPolling()
        }
        .onDisappear {
            sceneController?.stopTimers()
        }
    }

    // MARK: - Overlay Controls

    private var overlayControls: some View {
        ZStack {
            // Back button — top left
            VStack {
                HStack {
                    backButton
                    Spacer()

                    // Stats badge — top right
                    statsBadge
                }
                Spacer()
            }
            .padding(16)

            // Legend — bottom left
            VStack {
                Spacer()
                HStack {
                    legendOverlay
                    Spacer()

                    // Node detail — bottom right
                    if let node = selectedNode {
                        nodeDetailCard(node)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Back Button

    private var backButton: some View {
        Button {
            withAnimation(.spring(response: 0.28)) {
                nav.showMemoryGraph = false
            }
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
                    .fill(Color.chissDeep.opacity(0.80))
                    .overlay(Capsule().stroke(Color.chissPrimary.opacity(0.35), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats Badge

    private var statsBadge: some View {
        let agents = model.nodes.filter { $0.kind == .agent }.count
        let tasks = model.nodes.filter { $0.kind == .task }.count
        let edges = model.edges.count

        return Text("\(agents) agents · \(tasks) tasks · \(edges) connections")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Color.chissPrimary.opacity(0.6))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.obsidianMid.opacity(0.85))
                    .overlay(Capsule().stroke(Color.chissPrimary.opacity(0.15), lineWidth: 1))
            )
    }

    // MARK: - Legend

    private var legendOverlay: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("MEMORY GRAPH")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.5)
                .foregroundColor(Color.chissPrimary.opacity(0.5))

            legendRow(hex: "#7CA7BC", label: "Agent")
            legendRow(hex: "#5BBD72", label: "Task (Done)")
            legendRow(hex: "#4A90D9", label: "Task (Active)")
            legendRow(hex: "#B81419", label: "Blocked")
            legendRow(hex: "#9B6ED0", label: "Objective")
            legendRow(hex: "#7CA7BC", label: "Knowledge", dimmed: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.obsidianMid.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.chissPrimary.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func legendRow(hex: String, label: String, dimmed: Bool = false) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(nsColor: NSColor(graphHex: hex)).opacity(dimmed ? 0.4 : 1.0))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Node Detail Card

    private func nodeDetailCard(_ node: GraphNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(nsColor: NSColor(graphHex: node.colorHex)))
                    .frame(width: 12, height: 12)
                    .shadow(color: Color(nsColor: NSColor(graphHex: node.colorHex)).opacity(0.6), radius: 6)
                Text(node.label)
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    selectedNode = nil
                    sceneController?.selectedNode = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            Text(node.kind.rawValue.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.5)
                .foregroundColor(Color.chissPrimary.opacity(0.6))

            Divider().opacity(0.2)

            ForEach(node.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack(alignment: .top, spacing: 6) {
                    Text(key)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 60, alignment: .trailing)
                    Text(value)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 260)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.obsidianMid.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.chissPrimary.opacity(0.20), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 12)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Loading

    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)
                .tint(Color.chissPrimary)
            Text("Building memory graph...")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.chissPrimary.opacity(0.6))
        }
    }
}

// MARK: - SceneKit NSViewRepresentable
//
// Wraps SCNView directly instead of using SwiftUI's SceneView to get
// full control over camera and gesture recognizers. SCNView's built-in
// allowsCameraControl gives us orbit/pan/zoom out of the box.

struct SceneKitGraphView: NSViewRepresentable {
    let scene: SCNScene
    let onTap: (CGPoint, SCNView) -> Void

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.backgroundColor = NSColor(red: 0.04, green: 0.055, blue: 0.075, alpha: 1.0)
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60

        // Click gesture for node selection
        let click = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleClick(_:))
        )
        view.addGestureRecognizer(click)

        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        // Scene is managed by the controller, no SwiftUI-driven updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    class Coordinator: NSObject {
        let onTap: (CGPoint, SCNView) -> Void

        init(onTap: @escaping (CGPoint, SCNView) -> Void) {
            self.onTap = onTap
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let point = gesture.location(in: view)
            onTap(point, view)
        }
    }
}
