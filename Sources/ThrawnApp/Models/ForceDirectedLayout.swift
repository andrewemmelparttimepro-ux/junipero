import Foundation
import simd

// MARK: - Force-Directed Layout Engine
//
// Actor-isolated 3D force simulation for graph layout. Three forces:
//   1. Coulomb repulsion — all nodes push apart
//   2. Hooke springs — connected nodes pull toward rest length
//   3. Center gravity — everything drifts toward origin
//
// Euler integration with damping. 300-tick settling burst on init,
// then incremental ticks for live updates. O(N²) repulsion is fine
// for ~30 nodes (~900 pairs, trivial).

private func vecLength(_ v: SIMD3<Float>) -> Float {
    sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
}

actor ForceDirectedLayout {

    private var positions: [String: SIMD3<Float>] = [:]
    private var velocities: [String: SIMD3<Float>] = [:]
    private var edges: [(source: String, target: String, restLength: Float)] = []
    private var nodeIds: [String] = []

    // Force constants
    private let repulsionStrength: Float = 8.0
    private let springStrength: Float = 0.3
    private let gravityStrength: Float = 0.05
    private let damping: Float = 0.85
    private let dt: Float = 0.016
    private let minDistance: Float = 0.5
    private let cutoffDistance: Float = 20.0

    // Rest lengths by edge kind
    private static let restLengths: [GraphEdgeKind: Float] = [
        .ownership: 3.0,
        .phaseLinkage: 4.0,
        .handoff: 5.0,
        .knowledge: 2.0,
    ]

    // MARK: Initialize

    func initialize(nodes: [GraphNode], graphEdges: [GraphEdge]) {
        positions.removeAll()
        velocities.removeAll()
        edges.removeAll()
        nodeIds.removeAll()

        for node in nodes {
            positions[node.id] = node.position
            velocities[node.id] = .zero
            nodeIds.append(node.id)
        }

        for edge in graphEdges {
            let restLength = Self.restLengths[edge.kind] ?? 3.0
            edges.append((edge.sourceId, edge.targetId, restLength))
        }
    }

    // MARK: Run settling burst

    func runSettling(iterations: Int) -> [String: SIMD3<Float>] {
        for _ in 0..<iterations {
            tick()
        }
        return positions
    }

    // MARK: Single tick

    @discardableResult
    func tick() -> [String: SIMD3<Float>] {
        let count = nodeIds.count
        guard count > 1 else { return positions }

        // Accumulate forces
        var forces: [String: SIMD3<Float>] = [:]
        for id in nodeIds { forces[id] = .zero }

        // 1. Repulsion (O(N²))
        for i in 0..<count {
            let idA = nodeIds[i]
            guard let posA = positions[idA] else { continue }

            for j in (i + 1)..<count {
                let idB = nodeIds[j]
                guard let posB = positions[idB] else { continue }

                var diff = posA - posB
                var dist = vecLength(diff)

                // Skip far-away pairs
                if dist > cutoffDistance { continue }

                // Clamp minimum distance
                dist = max(dist, minDistance)

                let direction = diff / dist
                let magnitude = repulsionStrength / (dist * dist)
                let force = direction * magnitude

                forces[idA]! += force
                forces[idB]! -= force
            }
        }

        // 2. Spring forces (edges only)
        for edge in edges {
            guard let posA = positions[edge.source],
                  let posB = positions[edge.target] else { continue }

            let diff = posB - posA
            var dist = vecLength(diff)
            dist = max(dist, minDistance)

            let direction = diff / dist
            let displacement = dist - edge.restLength
            let force = direction * springStrength * displacement

            forces[edge.source]! += force
            forces[edge.target]! -= force
        }

        // 3. Center gravity
        for id in nodeIds {
            guard let pos = positions[id] else { continue }
            forces[id]! -= pos * gravityStrength
        }

        // 4. Euler integration
        for id in nodeIds {
            guard let force = forces[id],
                  var vel = velocities[id],
                  var pos = positions[id] else { continue }

            vel = vel * damping + force * dt
            pos = pos + vel * dt

            velocities[id] = vel
            positions[id] = pos
        }

        return positions
    }

    // MARK: Get current positions

    func currentPositions() -> [String: SIMD3<Float>] {
        positions
    }

    // MARK: Update a single node position (for adding new nodes)

    func addNode(id: String, position: SIMD3<Float>) {
        positions[id] = position
        velocities[id] = .zero
        if !nodeIds.contains(id) {
            nodeIds.append(id)
        }
    }

    func addEdge(source: String, target: String, kind: GraphEdgeKind) {
        let restLength = Self.restLengths[kind] ?? 3.0
        edges.append((source, target, restLength))
    }
}
