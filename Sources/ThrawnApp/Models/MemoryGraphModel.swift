import Foundation

// MARK: - Memory Graph Model
//
// Parses JSONL logs, TASK_BOARD.md, objectives.json, and agent knowledge
// directories into an in-memory graph of nodes and edges. This is the
// single data source for the 3D SceneKit visualization.
//
// Data sources:
//   • heartbeat-*.jsonl  — agent activity counts
//   • llm-*.jsonl        — LLM call counts per agent
//   • events-*.jsonl     — dispatcher moves (handoff edges)
//   • TASK_BOARD.md      — task nodes + ownership edges
//   • objectives.json    — objective nodes + phase linkage
//   • agents/*/knowledge — knowledge file nodes

// MARK: - Graph Node

enum GraphNodeKind: String, Codable {
    case agent
    case task
    case objective
    case knowledge
}

struct GraphNode: Identifiable {
    let id: String                   // e.g. "agent:thrawn", "task:TASK-003"
    let kind: GraphNodeKind
    let label: String
    var position: SIMD3<Float>
    var size: Float                  // Sphere radius
    var colorHex: String
    var metadata: [String: String]
}

// MARK: - Graph Edge

enum GraphEdgeKind: String, Codable {
    case ownership       // Agent → Task
    case phaseLinkage    // Task → Objective
    case handoff         // Agent → Agent
    case knowledge       // Agent → Knowledge
}

struct GraphEdge: Identifiable {
    let id: String
    let sourceId: String
    let targetId: String
    let kind: GraphEdgeKind
    var weight: Float
}

// MARK: - Agent Color Map

private let agentColors: [String: String] = [
    "thrawn":  "#7CA7BC",   // chissPrimary — Lead
    "r2d2":    "#4A90D9",   // blue — Dev
    "c3po":    "#D4A843",   // gold — Data
    "quigon":  "#5BBD72",   // green — Research
    "lando":   "#9B6ED0",   // purple — Marketing
    "boba":    "#D05B5B",   // red — QA
    "bart":    "#4ABBB5",   // teal — Deep Research
    "hunter":  "#D0895B",   // orange — Lead Gen
]

private let agentDisplayNames: [String: String] = [
    "thrawn": "Thrawn", "r2d2": "R2-D2", "c3po": "C-3PO",
    "quigon": "Qui-Gon", "lando": "Lando", "boba": "Boba Fett",
    "bart": "Bart", "hunter": "Hunter",
]

private let agentRoles: [String: String] = [
    "thrawn": "Lead", "r2d2": "Dev", "c3po": "Data & API",
    "quigon": "Research", "lando": "Marketing", "boba": "QA & Recon",
    "bart": "Deep Research", "hunter": "Lead Gen & OSINT",
]

private let taskStatusColors: [String: String] = [
    "Ready":       "#7CA7BC",
    "In Progress": "#4A90D9",
    "Review":      "#78B0D8",
    "Done":        "#5BBD72",
    "Blocked":     "#B81419",
    "Inbox":       "#556677",
]

// MARK: - Owner name normalization

private let ownerToId: [String: String] = [
    "thrawn": "thrawn", "Thrawn": "thrawn",
    "r2-d2": "r2d2", "R2-D2": "r2d2", "r2d2": "r2d2",
    "c-3po": "c3po", "C-3PO": "c3po", "c3po": "c3po",
    "qui-gon": "quigon", "Qui-Gon": "quigon", "quigon": "quigon",
    "lando": "lando", "Lando": "lando", "Lando Calrissian": "lando",
    "boba": "boba", "Boba": "boba", "Boba Fett": "boba",
    "bart": "bart", "Bart": "bart",
    "hunter": "hunter", "Hunter": "hunter",
    "Andrew": "andrew",
]

// MARK: - Graph Model

@MainActor
final class MemoryGraphModel: ObservableObject {
    @Published var nodes: [GraphNode] = []
    @Published var edges: [GraphEdge] = []
    @Published var isLoading = false

    private var fileModDates: [String: Date] = [:]

    private let logsDir: URL = ThrawnPaths.appSupportDir
        .appendingPathComponent("workspace/logs")
    private let boardPath: URL = ThrawnPaths.appSupportDir
        .appendingPathComponent("workspace/ops/TASK_BOARD.md")
    private let objectivesPath: URL = ThrawnPaths.appSupportDir
        .appendingPathComponent("workspace/objectives.json")
    private let agentsDir: URL = ThrawnPaths.appSupportDir
        .appendingPathComponent("workspace/agents")

    // MARK: Load

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let result = await Task.detached(priority: .utility) { [logsDir, boardPath, objectivesPath, agentsDir] in
            Self.buildGraph(
                logsDir: logsDir,
                boardPath: boardPath,
                objectivesPath: objectivesPath,
                agentsDir: agentsDir
            )
        }.value

        self.nodes = result.nodes
        self.edges = result.edges
    }

    // MARK: Refresh (incremental)

    func checkForUpdates() -> Bool {
        var changed = false
        let paths = logFilePaths() + [boardPath, objectivesPath]
        for path in paths {
            let attrs = try? FileManager.default.attributesOfItem(atPath: path.path)
            let modDate = attrs?[.modificationDate] as? Date
            if modDate != fileModDates[path.path] {
                fileModDates[path.path] = modDate
                changed = true
            }
        }
        return changed
    }

    func refresh() async {
        await load()
    }

    private func logFilePaths() -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: logsDir,
            includingPropertiesForKeys: nil) else { return [] }
        return items.filter { $0.pathExtension == "jsonl" }
    }

    // MARK: - Static Graph Builder

    private struct BuildResult {
        let nodes: [GraphNode]
        let edges: [GraphEdge]
    }

    private nonisolated static func buildGraph(
        logsDir: URL, boardPath: URL, objectivesPath: URL, agentsDir: URL
    ) -> BuildResult {
        var nodes: [GraphNode] = []
        var edges: [GraphEdge] = []
        var edgeCounter = 0

        func nextEdgeId() -> String {
            edgeCounter += 1
            return "edge-\(edgeCounter)"
        }

        // ── 1. Count agent activity from logs ──

        var heartbeatCounts: [String: Int] = [:]
        var llmCounts: [String: Int] = [:]

        let fm = FileManager.default
        let logFiles = (try? fm.contentsOfDirectory(at: logsDir,
            includingPropertiesForKeys: nil)) ?? []

        for file in logFiles where file.lastPathComponent.hasPrefix("heartbeat-") {
            for entry in readJSONL(file) {
                if let agent = entry["agent"] as? String {
                    let cleaned = agent.replacingOccurrences(of: "agent:heartbeat:", with: "")
                    heartbeatCounts[cleaned, default: 0] += 1
                }
            }
        }

        for file in logFiles where file.lastPathComponent.hasPrefix("llm-") {
            for entry in readJSONL(file) {
                if let agent = entry["agent"] as? String {
                    let cleaned = agent
                        .replacingOccurrences(of: "agent:heartbeat:", with: "")
                        .replacingOccurrences(of: "agent:toolresult:", with: "")
                    if cleaned != "chat" {
                        llmCounts[cleaned, default: 0] += 1
                    }
                }
            }
        }

        // ── 2. Build agent nodes ──

        let agentIds = ["thrawn", "r2d2", "c3po", "quigon", "lando", "boba", "bart", "hunter"]
        let maxActivity = agentIds.map { (heartbeatCounts[$0, default: 0] + llmCounts[$0, default: 0]) }.max() ?? 1

        for agentId in agentIds {
            let activity = heartbeatCounts[agentId, default: 0] + llmCounts[agentId, default: 0]
            let normalized = Float(activity) / Float(max(maxActivity, 1))
            let size: Float = 0.3 + normalized * 0.9  // 0.3 to 1.2

            nodes.append(GraphNode(
                id: "agent:\(agentId)",
                kind: .agent,
                label: agentDisplayNames[agentId] ?? agentId,
                position: randomPosition(radius: 8),
                size: size,
                colorHex: agentColors[agentId] ?? "#7CA7BC",
                metadata: [
                    "Role": agentRoles[agentId] ?? "Agent",
                    "Heartbeats": "\(heartbeatCounts[agentId, default: 0])",
                    "LLM Calls": "\(llmCounts[agentId, default: 0])",
                ]
            ))
        }

        // ── 3. Parse task board ──

        if let boardContent = try? String(contentsOf: boardPath, encoding: .utf8) {
            let taskBlocks = boardContent.components(separatedBy: "### TASK-")
            for block in taskBlocks.dropFirst() {
                let lines = block.components(separatedBy: "\n")
                guard let headerLine = lines.first else { continue }
                let taskId = "TASK-" + headerLine.components(separatedBy: ":").first!
                    .trimmingCharacters(in: .whitespaces)

                var fields: [String: String] = [:]
                for line in lines {
                    if let (key, value) = parseFieldLine(line) {
                        fields[key] = value
                    }
                }

                let status = fields["Status"] ?? "Inbox"
                let owner = fields["Owner"] ?? ""
                let title = fields["Title"] ?? taskId
                let project = fields["Project"] ?? fields["Objective"] ?? ""

                nodes.append(GraphNode(
                    id: "task:\(taskId)",
                    kind: .task,
                    label: taskId,
                    position: randomPosition(radius: 6),
                    size: 0.4,
                    colorHex: taskStatusColors[status] ?? "#556677",
                    metadata: [
                        "Title": title,
                        "Status": status,
                        "Owner": owner,
                        "Objective": project,
                    ]
                ))

                // Edge: Agent → Task (ownership)
                if let agentId = ownerToId[owner] {
                    edges.append(GraphEdge(
                        id: nextEdgeId(),
                        sourceId: "agent:\(agentId)",
                        targetId: "task:\(taskId)",
                        kind: .ownership,
                        weight: 1.0
                    ))
                }

                // Edge: Task → Objective (phase linkage)
                if !project.isEmpty && project.hasPrefix("OBJ-") {
                    edges.append(GraphEdge(
                        id: nextEdgeId(),
                        sourceId: "task:\(taskId)",
                        targetId: "obj:\(project)",
                        kind: .phaseLinkage,
                        weight: 1.0
                    ))
                }
            }
        }

        // ── 4. Parse objectives ──

        if let data = try? Data(contentsOf: objectivesPath),
           let objs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for obj in objs {
                let id = obj["id"] as? String ?? "OBJ-unknown"
                let input = obj["input"] as? String ?? "Objective"
                let status = obj["status"] as? String ?? "active"
                let phase = obj["currentPhaseIndex"] as? Int ?? 0
                let created = obj["tasksCreated"] as? Int ?? 0
                let completed = obj["tasksCompleted"] as? Int ?? 0

                let shortLabel = String(input.prefix(20)) + (input.count > 20 ? "..." : "")

                nodes.append(GraphNode(
                    id: "obj:\(id)",
                    kind: .objective,
                    label: shortLabel,
                    position: randomPosition(radius: 10),
                    size: 0.7,
                    colorHex: "#9B6ED0",
                    metadata: [
                        "Input": input,
                        "Status": status,
                        "Phase": "\(phase)",
                        "Tasks": "\(completed)/\(created)",
                    ]
                ))
            }
        }

        // ── 5. Parse agent knowledge files ──

        var knowledgeCount = 0
        let maxKnowledge = 50

        for agentId in agentIds {
            let knowledgeDir = agentsDir
                .appendingPathComponent(agentId)
                .appendingPathComponent("knowledge")

            guard let files = try? fm.contentsOfDirectory(at: knowledgeDir,
                includingPropertiesForKeys: nil) else { continue }

            let mdFiles = files.filter { $0.pathExtension == "md" && $0.lastPathComponent != "README.md" }

            if mdFiles.count > 8 {
                // Cluster into summary node
                knowledgeCount += 1
                if knowledgeCount <= maxKnowledge {
                    let nodeId = "knowledge:\(agentId)-cluster"
                    nodes.append(GraphNode(
                        id: nodeId,
                        kind: .knowledge,
                        label: "\(mdFiles.count) files",
                        position: randomPosition(radius: 4),
                        size: 0.25,
                        colorHex: "#7CA7BC",
                        metadata: ["Agent": agentDisplayNames[agentId] ?? agentId, "Count": "\(mdFiles.count)"]
                    ))
                    edges.append(GraphEdge(
                        id: nextEdgeId(),
                        sourceId: "agent:\(agentId)",
                        targetId: nodeId,
                        kind: .knowledge,
                        weight: 0.5
                    ))
                }
            } else {
                for file in mdFiles {
                    knowledgeCount += 1
                    guard knowledgeCount <= maxKnowledge else { break }
                    let name = file.deletingPathExtension().lastPathComponent
                    let nodeId = "knowledge:\(agentId)-\(name)"
                    nodes.append(GraphNode(
                        id: nodeId,
                        kind: .knowledge,
                        label: String(name.prefix(15)),
                        position: randomPosition(radius: 4),
                        size: 0.2,
                        colorHex: "#7CA7BC",
                        metadata: ["Agent": agentDisplayNames[agentId] ?? agentId, "File": file.lastPathComponent]
                    ))
                    edges.append(GraphEdge(
                        id: nextEdgeId(),
                        sourceId: "agent:\(agentId)",
                        targetId: nodeId,
                        kind: .knowledge,
                        weight: 0.5
                    ))
                }
            }
        }

        // ── 6. Parse handoff edges from dispatcher events ──

        var handoffCounts: [String: Int] = [:]  // "agentA->agentB" -> count

        for file in logFiles where file.lastPathComponent.hasPrefix("events-") {
            for entry in readJSONL(file) {
                guard let category = entry["category"] as? String, category == "dispatcher",
                      let action = entry["action"] as? String, action == "move",
                      let detail = entry["detail"] as? String,
                      detail.contains("Owner")
                else { continue }

                // Pattern: "TASK-xxx: Owner → AgentName"
                let parts = detail.components(separatedBy: "→")
                if parts.count == 2 {
                    let target = parts[1].trimmingCharacters(in: .whitespaces)
                    if let targetId = ownerToId[target], targetId != "andrew" {
                        // The source is "Thrawn" for most handoffs (hub pattern)
                        let key = "thrawn->\(targetId)"
                        handoffCounts[key, default: 0] += 1
                    }
                }
                // Also try the " -> " form
                let altParts = detail.components(separatedBy: " -> ")
                if altParts.count == 2 {
                    let target = altParts[1].trimmingCharacters(in: .whitespaces)
                    if let targetId = ownerToId[target], targetId != "andrew" {
                        let key = "thrawn->\(targetId)"
                        handoffCounts[key, default: 0] += 1
                    }
                }
            }
        }

        let maxHandoffs = handoffCounts.values.max() ?? 1
        for (pair, count) in handoffCounts {
            let parts = pair.components(separatedBy: "->")
            guard parts.count == 2 else { continue }
            let weight = Float(count) / Float(max(maxHandoffs, 1)) * 2.0 + 0.5
            edges.append(GraphEdge(
                id: nextEdgeId(),
                sourceId: "agent:\(parts[0])",
                targetId: "agent:\(parts[1])",
                kind: .handoff,
                weight: min(weight, 3.0)
            ))
        }

        return BuildResult(nodes: nodes, edges: edges)
    }

    // MARK: - Helpers

    private nonisolated static func readJSONL(_ url: URL) -> [[String: Any]] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return content.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return obj
        }
    }

    private nonisolated static func parseFieldLine(_ line: String) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("- ") else { return nil }
        let content = String(trimmed.dropFirst(2))

        // Try "**Field:** Value" form
        if content.hasPrefix("**"),
           let endBold = content.range(of: ":**") {
            let key = String(content[content.index(content.startIndex, offsetBy: 2)..<endBold.lowerBound])
            let value = String(content[endBold.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (key, value)
        }

        // Try "Field: Value" form
        if let colonRange = content.range(of: ": ") {
            let key = String(content[..<colonRange.lowerBound])
            let value = String(content[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (key, value)
        }

        return nil
    }

    private nonisolated static func randomPosition(radius: Float) -> SIMD3<Float> {
        let theta = Float.random(in: 0..<Float.pi * 2)
        let phi = Float.random(in: -Float.pi/2..<Float.pi/2)
        let r = Float.random(in: 1..<radius)
        return SIMD3<Float>(
            r * cos(phi) * cos(theta),
            r * cos(phi) * sin(theta),
            r * sin(phi)
        )
    }
}
