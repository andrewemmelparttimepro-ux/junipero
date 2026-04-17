import Foundation
import SceneKit
import SwiftUI

// MARK: - NSColor hex helper for SceneKit materials

extension NSColor {
    convenience init(graphHex: String) {
        let hex = graphHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255.0
        let g = CGFloat((int >> 8) & 0xFF) / 255.0
        let b = CGFloat(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

// MARK: - Memory Graph Scene Controller
//
// Builds and maintains an SCNScene from the MemoryGraphModel.
// Manages geometry, camera, bloom, and position updates from
// the force-directed layout engine.

@MainActor
final class MemoryGraphSceneController: ObservableObject {
    let scene = SCNScene()
    @Published var selectedNode: GraphNode?

    private let model: MemoryGraphModel
    private let layout = ForceDirectedLayout()
    private var nodeGroup = SCNNode()
    private var edgeGroup = SCNNode()
    private var updateTimer: Timer?
    private var layoutTimer: Timer?
    private var isSettled = false

    // Map edge IDs to their source/target for quick position updates
    private var edgeEndpoints: [(edgeNode: SCNNode, sourceId: String, targetId: String)] = []

    init(model: MemoryGraphModel) {
        self.model = model
    }

    // MARK: Build Scene

    func buildScene() async {
        // Set background
        scene.background.contents = NSColor(red: 0.04, green: 0.055, blue: 0.075, alpha: 1.0)

        // Set up node containers
        nodeGroup.name = "nodeGroup"
        edgeGroup.name = "edgeGroup"
        scene.rootNode.addChildNode(edgeGroup)
        scene.rootNode.addChildNode(nodeGroup)

        // Camera
        setupCamera()

        // Lighting
        setupLighting()

        // Create geometry for all nodes
        for node in model.nodes {
            let scnNode = makeNodeGeometry(node)
            nodeGroup.addChildNode(scnNode)
        }

        // Create geometry for all edges
        for edge in model.edges {
            let edgeNode = makeEdgeGeometry(edge)
            edgeGroup.addChildNode(edgeNode)
            edgeEndpoints.append((edgeNode, edge.sourceId, edge.targetId))
        }

        // Initialize layout engine
        await layout.initialize(nodes: model.nodes, graphEdges: model.edges)

        // Run settling burst
        let settled = await layout.runSettling(iterations: 300)

        // Apply settled positions
        applyPositions(settled, animated: false)

        // Start incremental layout for gentle settling
        startLayoutTimer()
    }

    // MARK: Camera

    private func setupCamera() {
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 200
        cameraNode.camera?.fieldOfView = 50

        // Bloom post-processing
        cameraNode.camera?.bloomIntensity = 0.8
        cameraNode.camera?.bloomThreshold = 0.4
        cameraNode.camera?.bloomBlurRadius = 8.0
        cameraNode.camera?.wantsHDR = true

        cameraNode.position = SCNVector3(0, 5, 25)
        cameraNode.look(at: SCNVector3Zero)

        // Orbit parent
        let orbitNode = SCNNode()
        orbitNode.name = "cameraOrbit"
        orbitNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(orbitNode)

        // Auto-rotation — 90 seconds per full rotation
        let rotate = SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 90)
        )
        orbitNode.runAction(rotate, forKey: "autoRotate")
    }

    // MARK: Lighting

    private func setupLighting() {
        // Ambient — dim baseline so nothing is pitch black
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = NSColor(red: 0.15, green: 0.20, blue: 0.25, alpha: 1.0)
        ambient.light?.intensity = 200
        scene.rootNode.addChildNode(ambient)

        // Key light — soft directional
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.color = NSColor(red: 0.60, green: 0.75, blue: 0.85, alpha: 1.0)
        key.light?.intensity = 400
        key.position = SCNVector3(10, 15, 20)
        key.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(key)
    }

    // MARK: Node Geometry

    private func makeNodeGeometry(_ node: GraphNode) -> SCNNode {
        let sphere = SCNSphere(radius: CGFloat(node.size))
        sphere.segmentCount = node.kind == .agent ? 32 : 16

        let material = SCNMaterial()
        let color = NSColor(graphHex: node.colorHex)
        material.diffuse.contents = color

        // Emissive glow — agents brighter
        let glowIntensity: CGFloat
        switch node.kind {
        case .agent:     glowIntensity = 0.6
        case .objective: glowIntensity = 0.5
        case .task:      glowIntensity = 0.3
        case .knowledge: glowIntensity = 0.15
        }
        material.emission.contents = color.withAlphaComponent(glowIntensity)
        material.lightingModel = .physicallyBased
        material.metalness.contents = NSColor(white: 0.3, alpha: 1.0)
        material.roughness.contents = NSColor(white: 0.4, alpha: 1.0)

        if node.kind == .knowledge {
            material.transparency = 0.6
        }

        sphere.materials = [material]

        let scnNode = SCNNode(geometry: sphere)
        scnNode.name = node.id
        scnNode.position = SCNVector3(node.position.x, node.position.y, node.position.z)

        // Label
        let label = makeLabel(node.label, size: node.kind == .agent ? 0.35 : 0.25)
        label.position = SCNVector3(0, Float(node.size) + 0.3, 0)
        scnNode.addChildNode(label)

        return scnNode
    }

    private func makeLabel(_ text: String, size: CGFloat) -> SCNNode {
        let textGeo = SCNText(string: text, extrusionDepth: 0.01)
        textGeo.font = NSFont.systemFont(ofSize: size, weight: .medium)
        textGeo.flatness = 0.1

        let material = SCNMaterial()
        material.diffuse.contents = NSColor.white.withAlphaComponent(0.85)
        material.emission.contents = NSColor.white.withAlphaComponent(0.3)
        material.isDoubleSided = true
        textGeo.materials = [material]

        let labelNode = SCNNode(geometry: textGeo)

        // Center the text horizontally
        let (min, max) = textGeo.boundingBox
        let dx = (max.x - min.x) / 2
        labelNode.pivot = SCNMatrix4MakeTranslation(dx, 0, 0)

        // Billboard constraint — always face camera
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = [.X, .Y]
        labelNode.constraints = [billboard]

        let container = SCNNode()
        container.addChildNode(labelNode)
        container.name = "label"
        return container
    }

    // MARK: Edge Geometry

    private func makeEdgeGeometry(_ edge: GraphEdge) -> SCNNode {
        let cylinder = SCNCylinder(radius: CGFloat(0.015 * edge.weight), height: 1.0)

        let material = SCNMaterial()
        let opacity: CGFloat = edge.kind == .handoff ? 0.35 : 0.18
        material.diffuse.contents = NSColor(red: 0.484, green: 0.655, blue: 0.737, alpha: opacity)
        material.emission.contents = NSColor(red: 0.484, green: 0.655, blue: 0.737, alpha: opacity * 0.5)
        material.isDoubleSided = true
        cylinder.materials = [material]

        let node = SCNNode(geometry: cylinder)
        node.name = edge.id
        return node
    }

    // MARK: Position Updates

    func applyPositions(_ positions: [String: SIMD3<Float>], animated: Bool) {
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.1
        }

        for (nodeId, pos) in positions {
            guard let scnNode = nodeGroup.childNode(withName: nodeId, recursively: false)
            else { continue }
            scnNode.position = SCNVector3(pos.x, pos.y, pos.z)
        }

        if animated {
            SCNTransaction.commit()
        }

        // Update all edges
        updateAllEdges()
    }

    private func updateAllEdges() {
        for entry in edgeEndpoints {
            guard let sourceNode = nodeGroup.childNode(withName: entry.sourceId, recursively: false),
                  let targetNode = nodeGroup.childNode(withName: entry.targetId, recursively: false)
            else { continue }

            positionEdge(entry.edgeNode, from: sourceNode.position, to: targetNode.position)
        }
    }

    private func positionEdge(_ edgeNode: SCNNode, from: SCNVector3, to: SCNVector3) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let dz = to.z - from.z
        let distance = sqrt(dx * dx + dy * dy + dz * dz)

        guard distance > 0.01, let cyl = edgeNode.geometry as? SCNCylinder else { return }

        cyl.height = CGFloat(distance)

        // Position at midpoint
        edgeNode.position = SCNVector3(
            (from.x + to.x) / 2,
            (from.y + to.y) / 2,
            (from.z + to.z) / 2
        )

        // Rotate to align — cylinder's local Y axis to the direction vector
        let direction = SCNVector3(dx, dy, dz)
        let up = SCNVector3(0, 1, 0)

        // Cross product for rotation axis
        let cross = SCNVector3(
            up.y * direction.z - up.z * direction.y,
            up.z * direction.x - up.x * direction.z,
            up.x * direction.y - up.y * direction.x
        )
        let crossLen = sqrt(cross.x * cross.x + cross.y * cross.y + cross.z * cross.z)
        let dot = up.x * direction.x + up.y * direction.y + up.z * direction.z

        if crossLen > 0.0001 {
            let angle = atan2(crossLen, dot)
            let axis = SCNVector3(cross.x / crossLen, cross.y / crossLen, cross.z / crossLen)
            edgeNode.rotation = SCNVector4(axis.x, axis.y, axis.z, angle)
        } else if dot < 0 {
            // 180 degree rotation — flip
            edgeNode.rotation = SCNVector4(1, 0, 0, Float.pi)
        } else {
            edgeNode.rotation = SCNVector4(0, 0, 0, 0)
        }
    }

    // MARK: Hit Testing

    func handleTap(at point: CGPoint, in sceneView: SCNView) {
        let hits = sceneView.hitTest(point, options: [
            .searchMode: NSNumber(value: SCNHitTestSearchMode.closest.rawValue)
        ])

        // Walk up the node tree to find one with a matching graph node ID
        for hit in hits {
            var current: SCNNode? = hit.node
            while let node = current {
                if let name = node.name, model.nodes.contains(where: { $0.id == name }) {
                    selectedNode = model.nodes.first(where: { $0.id == name })
                    highlightNode(name)
                    return
                }
                current = node.parent
            }
        }

        // Tapped empty space — deselect
        selectedNode = nil
        clearHighlight()
    }

    private func highlightNode(_ nodeId: String) {
        // Reset all nodes, then highlight selected
        for child in nodeGroup.childNodes {
            guard let geo = child.geometry as? SCNSphere else { continue }
            let isSelected = child.name == nodeId

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.2
            if isSelected {
                child.scale = SCNVector3(1.3, 1.3, 1.3)
                geo.firstMaterial?.emission.intensity = 1.5
            } else {
                child.scale = SCNVector3(1, 1, 1)
                geo.firstMaterial?.emission.intensity = 1.0
            }
            SCNTransaction.commit()
        }
    }

    private func clearHighlight() {
        for child in nodeGroup.childNodes {
            guard child.geometry is SCNSphere else { continue }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.2
            child.scale = SCNVector3(1, 1, 1)
            child.geometry?.firstMaterial?.emission.intensity = 1.0
            SCNTransaction.commit()
        }
    }

    // MARK: Live Updates

    private func startLayoutTimer() {
        // Incremental layout ticks at 30Hz for a few seconds, then stop
        var tickCount = 0
        layoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { timer.invalidate(); return }
                tickCount += 1
                let positions = await self.layout.tick()
                self.applyPositions(positions, animated: false)

                // After 5 seconds of settling, slow down to 2Hz
                if tickCount > 150 {
                    timer.invalidate()
                    self.isSettled = true
                    self.startSlowUpdateTimer()
                }
            }
        }
    }

    private func startSlowUpdateTimer() {
        // 2Hz gentle drift after settling
        layoutTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { timer.invalidate(); return }
                let positions = await self.layout.tick()
                self.applyPositions(positions, animated: true)
            }
        }
    }

    func startDataPolling() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.model.checkForUpdates() {
                    await self.model.refresh()
                    await self.rebuildScene()
                }
            }
        }
    }

    func stopTimers() {
        updateTimer?.invalidate()
        updateTimer = nil
        layoutTimer?.invalidate()
        layoutTimer = nil
    }

    private func rebuildScene() async {
        // Clear existing geometry
        nodeGroup.childNodes.forEach { $0.removeFromParentNode() }
        edgeGroup.childNodes.forEach { $0.removeFromParentNode() }
        edgeEndpoints.removeAll()

        // Rebuild
        for node in model.nodes {
            let scnNode = makeNodeGeometry(node)
            nodeGroup.addChildNode(scnNode)
        }
        for edge in model.edges {
            let edgeNode = makeEdgeGeometry(edge)
            edgeGroup.addChildNode(edgeNode)
            edgeEndpoints.append((edgeNode, edge.sourceId, edge.targetId))
        }

        await layout.initialize(nodes: model.nodes, graphEdges: model.edges)
        let settled = await layout.runSettling(iterations: 200)
        applyPositions(settled, animated: true)
    }
}
