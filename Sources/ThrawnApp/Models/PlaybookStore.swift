import Foundation
import SwiftUI

// MARK: - Playbook & Objective System
//
// Playbooks are predefined task decomposition templates.
// Objectives are active instances of playbooks with user-provided input.
// Thrawn reads active objectives on every heartbeat, decomposes them
// into task board items, and tracks progress toward completion.
//
// The factory never stops: if no objectives exist, Thrawn falls back
// to the NDAI improvement protocol.

// MARK: - Playbook Definition

struct PlaybookPhase: Identifiable, Codable {
    var id: String { name }
    let name: String
    let agent: String           // Which agent handles this phase
    let description: String     // What the agent should do
    let taskTemplate: String    // Task title template — {{INPUT}} is replaced
    let estimatedTasks: Int     // Rough count of tasks this phase generates
}

struct Playbook: Identifiable, Codable {
    let id: String
    let name: String
    let icon: String            // SF Symbol
    let description: String
    let inputLabel: String      // "Business Name", "Product Name", etc.
    let inputPlaceholder: String
    let phases: [PlaybookPhase]

    var totalEstimatedTasks: Int { phases.map(\.estimatedTasks).reduce(0, +) }
}

// MARK: - Objective (Active Instance of a Playbook)

struct Objective: Identifiable, Codable {
    let id: String
    let playbookId: String
    let input: String               // The novel part — business name, product, etc.
    var status: ObjectiveStatus
    let createdAt: Date
    var currentPhaseIndex: Int      // Which phase Thrawn is working on
    var tasksCreated: Int           // Total tasks spawned so far
    var tasksCompleted: Int         // Tasks marked Done
    var lastActivity: Date
    var notes: String               // Thrawn can append observations

    enum ObjectiveStatus: String, Codable {
        case active     // Running — Thrawn decomposes and delegates
        case paused     // User paused — no new tasks created
        case completed  // All phases done
        case stopped    // User killed it
    }

    var playbookName: String {
        PlaybookLibrary.all.first(where: { $0.id == playbookId })?.name ?? playbookId
    }

    var progressPercent: Double {
        let playbook = PlaybookLibrary.all.first(where: { $0.id == playbookId })
        let totalPhases = playbook?.phases.count ?? 1
        guard totalPhases > 0 else { return 0 }
        let phaseProgress = Double(currentPhaseIndex) / Double(totalPhases)
        let taskProgress = tasksCreated > 0 ? Double(tasksCompleted) / Double(tasksCreated) : 0
        return (phaseProgress * 0.6 + taskProgress * 0.4) * 100
    }
}

// MARK: - Playbook Library (Built-in Playbooks)

enum PlaybookLibrary {
    static let all: [Playbook] = [
        competitiveAnalysis,
        marketResearch,
        contentPipeline,
        productAudit,
        leadGeneration,
        ndaiImprovement,
    ]

    // ── Competitive Analysis ──
    static let competitiveAnalysis = Playbook(
        id: "competitive-analysis",
        name: "Competitive Analysis",
        icon: "chart.bar.xaxis",
        description: "Comprehensive competitive intelligence on a target business. Covers product positioning, pricing, marketing channels, tech stack, content strategy, strengths/weaknesses, and strategic recommendations.",
        inputLabel: "Business / Company Name",
        inputPlaceholder: "e.g. Notion, Linear, Figma",
        phases: [
            PlaybookPhase(
                name: "Discovery & Landscape",
                agent: "Qui-Gon",
                description: "Research the target company: what they do, founding story, funding, team size, recent news. Identify their top 3-5 direct competitors. Map the competitive landscape.",
                taskTemplate: "Research {{INPUT}} — company overview, funding, team, recent news",
                estimatedTasks: 3
            ),
            PlaybookPhase(
                name: "Product & Pricing Analysis",
                agent: "Qui-Gon",
                description: "Deep-dive on {{INPUT}}'s product: features, pricing tiers, free vs paid, integrations, API, platform support. Compare with each identified competitor.",
                taskTemplate: "Analyze {{INPUT}} product features and pricing vs competitors",
                estimatedTasks: 4
            ),
            PlaybookPhase(
                name: "Marketing & Content Audit",
                agent: "Lando",
                description: "Analyze {{INPUT}}'s marketing: website messaging, blog content strategy, social media presence, SEO positioning, ad spend signals, brand voice.",
                taskTemplate: "Audit {{INPUT}} marketing channels and content strategy",
                estimatedTasks: 4
            ),
            PlaybookPhase(
                name: "Technical Assessment",
                agent: "R2-D2",
                description: "Investigate {{INPUT}}'s tech stack (builtwith, job postings, GitHub repos), API quality, developer experience, infrastructure choices.",
                taskTemplate: "Assess {{INPUT}} technical stack and developer experience",
                estimatedTasks: 3
            ),
            PlaybookPhase(
                name: "Data Synthesis",
                agent: "C-3PO",
                description: "Compile all research into structured datasets: feature comparison matrix, pricing comparison table, SWOT analysis, market positioning map.",
                taskTemplate: "Synthesize {{INPUT}} competitive data into structured analysis",
                estimatedTasks: 3
            ),
            PlaybookPhase(
                name: "QA & Fact Check",
                agent: "Boba",
                description: "Validate all claims, check for outdated info, verify pricing, confirm feature accuracy. Flag anything unverifiable.",
                taskTemplate: "Validate {{INPUT}} competitive analysis for accuracy",
                estimatedTasks: 2
            ),
            PlaybookPhase(
                name: "Strategic Recommendations",
                agent: "Lando",
                description: "Based on the full analysis, draft strategic recommendations: differentiation opportunities, messaging angles, feature gaps to exploit, market positioning strategy.",
                taskTemplate: "Draft strategic recommendations from {{INPUT}} analysis",
                estimatedTasks: 2
            ),
            PlaybookPhase(
                name: "Final Report",
                agent: "C-3PO",
                description: "Compile everything into a polished final report with executive summary, detailed sections, data tables, and appendices.",
                taskTemplate: "Compile final {{INPUT}} competitive analysis report",
                estimatedTasks: 1
            ),
        ]
    )

    // ── Market Research ──
    static let marketResearch = Playbook(
        id: "market-research",
        name: "Market Research",
        icon: "globe.americas.fill",
        description: "Deep market analysis for a product category or industry vertical. TAM/SAM/SOM, trends, customer segments, distribution channels, and entry strategy.",
        inputLabel: "Market / Industry",
        inputPlaceholder: "e.g. AI Code Assistants, EdTech for K-12",
        phases: [
            PlaybookPhase(name: "Market Definition", agent: "Qui-Gon", description: "Define the market boundaries, key segments, and adjacent markets for {{INPUT}}.", taskTemplate: "Define market boundaries and segments for {{INPUT}}", estimatedTasks: 2),
            PlaybookPhase(name: "Player Mapping", agent: "Qui-Gon", description: "Identify all significant players in {{INPUT}}: incumbents, challengers, emerging startups.", taskTemplate: "Map all players in {{INPUT}} market", estimatedTasks: 3),
            PlaybookPhase(name: "Customer Research", agent: "Lando", description: "Analyze customer segments, buyer personas, pain points, and purchase drivers in {{INPUT}}.", taskTemplate: "Research {{INPUT}} customer segments and personas", estimatedTasks: 3),
            PlaybookPhase(name: "Sizing & Trends", agent: "C-3PO", description: "Estimate TAM/SAM/SOM for {{INPUT}}. Identify growth trends, inflection points, regulatory factors.", taskTemplate: "Size {{INPUT}} market and identify trends", estimatedTasks: 2),
            PlaybookPhase(name: "Channel Analysis", agent: "Lando", description: "Map distribution and marketing channels that work in {{INPUT}}: SEO, paid, PLG, sales-led, partnerships.", taskTemplate: "Analyze distribution channels for {{INPUT}}", estimatedTasks: 2),
            PlaybookPhase(name: "Validation & Report", agent: "Boba", description: "Cross-check all data, validate claims, compile into final market research report.", taskTemplate: "Validate and compile {{INPUT}} market research report", estimatedTasks: 2),
        ]
    )

    // ── Content Pipeline ──
    static let contentPipeline = Playbook(
        id: "content-pipeline",
        name: "Content Pipeline",
        icon: "doc.text.fill",
        description: "Systematic content production for a brand or topic. SEO research, topic clustering, drafting, editing, and publishing-ready output.",
        inputLabel: "Brand / Topic Focus",
        inputPlaceholder: "e.g. NDAI, Thrawn Console, AI Agents",
        phases: [
            PlaybookPhase(name: "Keyword & Topic Research", agent: "Qui-Gon", description: "Research SEO keywords, trending topics, and content gaps for {{INPUT}}.", taskTemplate: "Research keywords and content opportunities for {{INPUT}}", estimatedTasks: 3),
            PlaybookPhase(name: "Content Calendar", agent: "C-3PO", description: "Create a structured content calendar from the research. Prioritize by impact and difficulty.", taskTemplate: "Build content calendar for {{INPUT}}", estimatedTasks: 1),
            PlaybookPhase(name: "Content Drafting", agent: "Lando", description: "Draft articles, posts, and copy based on the content calendar for {{INPUT}}.", taskTemplate: "Draft content pieces for {{INPUT}}", estimatedTasks: 8),
            PlaybookPhase(name: "QA & Editing", agent: "Boba", description: "Review all drafted content for quality, accuracy, tone consistency, and brand alignment.", taskTemplate: "Review and edit {{INPUT}} content drafts", estimatedTasks: 4),
            PlaybookPhase(name: "Final Assembly", agent: "C-3PO", description: "Format all approved content for publishing. Add metadata, images specs, internal links.", taskTemplate: "Finalize {{INPUT}} content for publishing", estimatedTasks: 2),
        ]
    )

    // ── Product Audit ──
    static let productAudit = Playbook(
        id: "product-audit",
        name: "Product Audit",
        icon: "magnifyingglass.circle.fill",
        description: "Comprehensive audit of a product or codebase. UX review, code quality, performance, security surface, and improvement roadmap.",
        inputLabel: "Product / Repo Name",
        inputPlaceholder: "e.g. thrawn-console, ndai.dev",
        phases: [
            PlaybookPhase(name: "Architecture Review", agent: "R2-D2", description: "Analyze the codebase structure, dependencies, and architectural patterns of {{INPUT}}.", taskTemplate: "Review {{INPUT}} architecture and code structure", estimatedTasks: 3),
            PlaybookPhase(name: "UX Audit", agent: "Lando", description: "Walk through {{INPUT}} from a user perspective. Document friction points, confusing flows, missing features.", taskTemplate: "Audit {{INPUT}} user experience and flows", estimatedTasks: 3),
            PlaybookPhase(name: "Quality Analysis", agent: "Boba", description: "Assess {{INPUT}} test coverage, error handling, edge cases, and known bugs.", taskTemplate: "Assess {{INPUT}} quality and test coverage", estimatedTasks: 3),
            PlaybookPhase(name: "Performance & Security", agent: "R2-D2", description: "Check {{INPUT}} for performance bottlenecks, security surface, and infrastructure concerns.", taskTemplate: "Analyze {{INPUT}} performance and security", estimatedTasks: 2),
            PlaybookPhase(name: "Improvement Roadmap", agent: "C-3PO", description: "Compile findings into a prioritized improvement roadmap with effort estimates.", taskTemplate: "Create {{INPUT}} improvement roadmap", estimatedTasks: 1),
        ]
    )

    // ── Lead Generation (OSINT-style) ──
    static let leadGeneration = Playbook(
        id: "lead-generation",
        name: "Lead Generation",
        icon: "person.crop.rectangle.stack.fill",
        description: "OSINT-style lead generation for NDAI. Systematically sweeps public sources — LinkedIn, Reddit, company websites, Facebook groups, X/Twitter, GitHub, conference lists, job boards — to find, cross-reference, and build dossiers on qualified leads. Every breadcrumb, every platform, every angle.",
        inputLabel: "Target Profile / ICP",
        inputPlaceholder: "e.g. SaaS founders, 10-50 employees, Series A, using AI tools",
        phases: [
            PlaybookPhase(name: "ICP Definition & Source Mapping", agent: "Qui-Gon", description: "Define the ideal customer profile for {{INPUT}} with surgical precision. Map every public platform and community where these people congregate: LinkedIn groups, Reddit subs, Facebook groups, Discord servers, Slack communities, niche forums, conference speaker lists, podcast guest rolls, ProductHunt commenters, GitHub orgs. Build the hunting ground map.", taskTemplate: "Define ICP and map all public lead sources for {{INPUT}}", estimatedTasks: 3),
            PlaybookPhase(name: "Digital Footprint Sweep", agent: "Hunter", description: "Systematically sweep every source from the map. For each platform: scrape public profiles, posts, comments, team pages, about pages, contributor lists. Use curl, site-specific searches, and public APIs. Cast the widest net possible. Every name, every handle, every company mention goes into raw collection. Don't filter yet — collect everything.", taskTemplate: "Sweep public sources for {{INPUT}} leads — raw collection", estimatedTasks: 8),
            PlaybookPhase(name: "Cross-Reference & Enrichment", agent: "Hunter", description: "Cross-reference the raw collection across platforms. Same person on LinkedIn + Reddit + GitHub? Connect them. Find email patterns from company domains (first.last@, f.last@). Check personal websites, GitHub profiles for contact info. Verify company details: size, funding, tech stack, hiring signals. The Don't F*** With Cats methodology — every breadcrumb leads somewhere.", taskTemplate: "Cross-reference and enrich {{INPUT}} leads across platforms", estimatedTasks: 6),
            PlaybookPhase(name: "Qualification & Scoring", agent: "C-3PO", description: "Structure all enriched leads into a scored database. Score on: ICP fit (title, company size, industry), engagement signals (posting about pain points we solve, asking questions in relevant communities), buying signals (job postings for roles we replace, tech stack mentions, budget indicators from funding rounds). Tier into Hot / Warm / Cold.", taskTemplate: "Score and qualify {{INPUT}} leads into tiers", estimatedTasks: 3),
            PlaybookPhase(name: "Dossier Assembly", agent: "Hunter", description: "Build individual lead dossiers for every Hot and Warm lead. Each dossier: full name, title, company, company size, funding stage, all social profiles found, email (verified or pattern-matched), recent public activity relevant to our offering, specific pain points expressed publicly, mutual connections or communities. One file per lead in knowledge dir.", taskTemplate: "Assemble lead dossiers for qualified {{INPUT}} leads", estimatedTasks: 5),
            PlaybookPhase(name: "Outreach Strategy", agent: "Lando", description: "For each dossier, draft a personalized outreach angle. Reference their specific public activity, their pain points, their community context. Not generic templates — each message should make the lead think 'how did they know that about me.' Draft multi-channel sequences: LinkedIn DM, email, community reply. Charm offensive.", taskTemplate: "Draft personalized outreach for {{INPUT}} leads", estimatedTasks: 5),
            PlaybookPhase(name: "QA & Validation", agent: "Boba", description: "Validate every lead dossier. Verify contact info is current, companies still exist, titles are accurate, email patterns check out. Flag stale data, dead links, merged companies. Cross-check scoring accuracy. Final quality gate before any outreach fires.", taskTemplate: "Validate {{INPUT}} lead data and outreach accuracy", estimatedTasks: 3),
        ]
    )

    // ── NDAI Improvement (Fallback Protocol) ──
    static let ndaiImprovement = Playbook(
        id: "ndai-improvement",
        name: "NDAI Improvement",
        icon: "arrow.triangle.2.circlepath",
        description: "Continuous improvement protocol for NDAI as a business. Always running as fallback when no other objectives are active. Covers product, marketing, operations, and strategy.",
        inputLabel: "Focus Area (optional)",
        inputPlaceholder: "Leave blank for general improvement",
        phases: [
            PlaybookPhase(name: "Product Enhancement Scan", agent: "R2-D2", description: "Review Thrawn Console codebase for bugs, UX improvements, missing features, and reliability fixes.", taskTemplate: "Scan NDAI products for improvement opportunities", estimatedTasks: 5),
            PlaybookPhase(name: "Marketing Audit", agent: "Lando", description: "Review NDAI's current marketing presence, messaging, and content. Identify gaps and opportunities.", taskTemplate: "Audit NDAI marketing and identify opportunities", estimatedTasks: 3),
            PlaybookPhase(name: "Operations Review", agent: "C-3PO", description: "Analyze agent performance data, task completion rates, error patterns. Recommend process improvements.", taskTemplate: "Review NDAI operations and agent performance", estimatedTasks: 2),
            PlaybookPhase(name: "Strategic Research", agent: "Qui-Gon", description: "Research AI agent market trends, new techniques, competitor moves relevant to NDAI.", taskTemplate: "Research market trends and opportunities for NDAI", estimatedTasks: 3),
            PlaybookPhase(name: "Implementation", agent: "R2-D2", description: "Implement the highest-priority improvements identified in earlier phases.", taskTemplate: "Implement top NDAI improvements", estimatedTasks: 5),
        ]
    )
}

// MARK: - Objective Store

@MainActor
final class ObjectiveStore: ObservableObject {
    @Published var objectives: [Objective] = []

    private let fm = FileManager.default
    private var scanTimer: Task<Void, Never>?

    private var objectivesFile: URL {
        ThrawnPaths.appSupportDir.appendingPathComponent("workspace/objectives.json")
    }
    private var boardPath: URL {
        ThrawnPaths.opsDir.appendingPathComponent("TASK_BOARD.md")
    }

    init() {
        load()
        startBoardScanner()
    }

    // MARK: - Board Scanner (counts tasks for each objective)

    /// Periodically scan TASK_BOARD.md and update task counts for active objectives.
    private func startBoardScanner() {
        scanTimer = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshFromBoard()
                try? await Task.sleep(nanoseconds: 30_000_000_000) // Every 30 seconds
            }
        }
    }

    /// Parsed view of a single TASK_BOARD.md task block. The scanner
    /// extracts one of these per task, then aggregates against objectives.
    private struct BoardTask {
        let id: String                  // "TASK-042"
        let title: String
        let status: String              // "Ready" / "Blocked" / "Done" (raw)
        let objectiveId: String?        // "OBJ-1713..." from `- Objective:`
        let phaseIndex: Int?            // from `- Phase:`

        var isDone: Bool { status.lowercased() == "done" }
    }

    /// Read the task board, parse every task block, and update task counts
    /// + auto-advance phases for active objectives. Called on a 30-second
    /// timer and on-demand from the view.
    ///
    /// Matching strategy (fixes the old title-substring fragility):
    ///   1. If a task has an explicit `Objective:` field → match by id.
    ///   2. If it also has a `Phase:` field → count into that phase's bucket.
    ///   3. Legacy tasks (no objective field) fall back to case-insensitive
    ///      title substring match on the objective input, attributed to the
    ///      objective's current phase. This keeps pre-upgrade tasks visible.
    ///
    /// Auto-advance: if the current phase has at least one task and ALL
    /// tasks for that phase are Done, the phase index is incremented and
    /// the objective's lastActivity bumped. Phases with zero tasks do NOT
    /// auto-advance — that protects against skipping a phase entirely.
    func refreshFromBoard() {
        guard let board = try? String(contentsOf: boardPath, encoding: .utf8) else {
            FlightRecorder.logEvent(
                category: "objective",
                action: "scan-failed",
                detail: "Cannot read board: \(boardPath.path)"
            )
            return
        }

        let boardTasks = Self.parseBoard(board)

        var changed = false

        for i in objectives.indices {
            let obj = objectives[i]
            guard obj.status == .active || obj.status == .paused else { continue }

            let input = obj.input.lowercased().trimmingCharacters(in: .whitespaces)

            // Collect every task attributable to this objective, grouped by
            // phase index. A nil phase goes into -1 so we still count it
            // toward totals without corrupting per-phase counts.
            var perPhase: [Int: (total: Int, done: Int)] = [:]
            var totalAll = 0
            var doneAll = 0

            for task in boardTasks {
                let attributedPhase: Int?
                if task.objectiveId == obj.id {
                    // Explicit linkage — trust it completely.
                    attributedPhase = task.phaseIndex ?? obj.currentPhaseIndex
                } else if task.objectiveId == nil, !input.isEmpty,
                          task.title.lowercased().contains(input) {
                    // Legacy fallback — no explicit objective field, match
                    // by title substring and attribute to the current phase.
                    attributedPhase = obj.currentPhaseIndex
                } else {
                    continue
                }

                totalAll += 1
                if task.isDone { doneAll += 1 }

                let key = attributedPhase ?? -1
                var bucket = perPhase[key] ?? (0, 0)
                bucket.total += 1
                if task.isDone { bucket.done += 1 }
                perPhase[key] = bucket
            }

            // Update rolling counts
            if objectives[i].tasksCreated != totalAll || objectives[i].tasksCompleted != doneAll {
                let prevTotal = objectives[i].tasksCreated
                let prevDone = objectives[i].tasksCompleted
                objectives[i].tasksCreated = totalAll
                objectives[i].tasksCompleted = doneAll
                if totalAll > prevTotal || doneAll > prevDone {
                    objectives[i].lastActivity = Date()
                }
                changed = true

                FlightRecorder.logEvent(
                    category: "objective",
                    action: "scan-updated",
                    detail: "\(obj.id) \(obj.input): \(doneAll)/\(totalAll) tasks"
                )
            }

            // Auto-advance: only if the current phase has at least one
            // task and all of them are Done. Running agents in .paused
            // status do NOT auto-advance — paused objectives hold still.
            guard objectives[i].status == .active else { continue }

            guard let playbook = PlaybookLibrary.all.first(where: { $0.id == obj.playbookId }) else { continue }
            let currentIdx = objectives[i].currentPhaseIndex
            guard currentIdx < playbook.phases.count else { continue }

            let currentPhaseCounts = perPhase[currentIdx] ?? (0, 0)
            if currentPhaseCounts.total > 0 && currentPhaseCounts.done == currentPhaseCounts.total {
                // Advance internally — don't call advancePhase(id:) because
                // we already hold the index in `i` and we want to avoid
                // re-locking or re-saving twice.
                let fromPhase = currentIdx
                objectives[i].currentPhaseIndex = currentIdx + 1
                objectives[i].lastActivity = Date()
                if objectives[i].currentPhaseIndex >= playbook.phases.count {
                    objectives[i].status = .completed
                    FlightRecorder.logEvent(
                        category: "objective",
                        action: "completed",
                        detail: "\(obj.id) all phases done"
                    )
                } else {
                    let toPhase = objectives[i].currentPhaseIndex
                    let toName = playbook.phases[toPhase].name
                    FlightRecorder.logEvent(
                        category: "objective",
                        action: "auto-advance",
                        detail: "\(obj.id) phase \(fromPhase)→\(toPhase) (\(toName))"
                    )
                }
                changed = true
            }
        }

        if changed { save() }
    }

    // MARK: - Board parsing

    /// Split a raw TASK_BOARD.md into structured BoardTask values.
    /// Handles both `- Field: value` and `- **Field:** value` forms.
    private static func parseBoard(_ board: String) -> [BoardTask] {
        // Split on "### TASK-" headers. First chunk is pre-task preamble.
        let parts = board.components(separatedBy: "### TASK-")
        guard parts.count > 1 else { return [] }

        var tasks: [BoardTask] = []
        for block in parts.dropFirst() {
            // Block starts with the numeric suffix of the task id, e.g. "042\n- Title: ..."
            let lines = block.components(separatedBy: "\n")
            guard let firstLine = lines.first else { continue }
            let idSuffix = firstLine.trimmingCharacters(in: .whitespaces)
            guard !idSuffix.isEmpty else { continue }
            let taskId = "TASK-\(idSuffix)"

            // Stop parsing this block at the next "### " (next task's header
            // without "TASK-") or at end of block — each block is already
            // isolated by the split, so just read every `- Field: value` line.
            var title = ""
            var status = ""
            var objectiveId: String? = nil
            var phaseIndex: Int? = nil

            for raw in lines.dropFirst() {
                // Stop if we hit another section header (defensive — split
                // already isolates TASK- blocks, but non-task ### headers
                // could appear below the last task).
                if raw.hasPrefix("### ") { break }

                guard let (field, value) = Self.parseFieldLine(raw) else { continue }
                let lowerField = field.lowercased()
                switch lowerField {
                case "title":
                    if title.isEmpty { title = value }
                case "status":
                    if status.isEmpty { status = value }
                case "objective", "objective id", "objective-id", "objective_id":
                    if objectiveId == nil { objectiveId = value }
                case "phase", "phase index", "phase-index", "phase_index":
                    if phaseIndex == nil { phaseIndex = Int(value.trimmingCharacters(in: .whitespaces)) }
                default:
                    break
                }
            }

            tasks.append(BoardTask(
                id: taskId,
                title: title,
                status: status,
                objectiveId: objectiveId,
                phaseIndex: phaseIndex
            ))
        }
        return tasks
    }

    /// Parse a single markdown bullet line like `- Title: Foo` or
    /// `- **Status:** Done` into (field, value). Returns nil if the
    /// line isn't a field-style bullet.
    private static func parseFieldLine(_ raw: String) -> (field: String, value: String)? {
        var line = raw.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("- ") else { return nil }
        line = String(line.dropFirst(2))
        // Strip markdown bolding: "**Field:** value" → "Field: value"
        line = line.replacingOccurrences(of: "**", with: "")
        guard let colonIdx = line.firstIndex(of: ":") else { return nil }
        let field = String(line[line.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
        let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
        guard !field.isEmpty else { return nil }
        return (field, value)
    }

    // MARK: - CRUD

    func launch(playbook: Playbook, input: String) {
        let objective = Objective(
            id: "OBJ-\(Int(Date().timeIntervalSince1970))",
            playbookId: playbook.id,
            input: input.isEmpty ? "NDAI" : input,
            status: .active,
            createdAt: Date(),
            currentPhaseIndex: 0,
            tasksCreated: 0,
            tasksCompleted: 0,
            lastActivity: Date(),
            notes: ""
        )
        objectives.append(objective)
        save()

        FlightRecorder.logEvent(
            category: "objective",
            action: "launched",
            detail: "\(objective.id): \(playbook.name) — \(input)",
            metadata: ["playbook": playbook.id, "input": input]
        )
    }

    func pause(_ id: String) {
        guard let idx = objectives.firstIndex(where: { $0.id == id }) else { return }
        objectives[idx].status = .paused
        save()
        FlightRecorder.logEvent(category: "objective", action: "paused", detail: id)
    }

    func resume(_ id: String) {
        guard let idx = objectives.firstIndex(where: { $0.id == id }) else { return }
        objectives[idx].status = .active
        objectives[idx].lastActivity = Date()
        save()
        FlightRecorder.logEvent(category: "objective", action: "resumed", detail: id)
    }

    func stop(_ id: String) {
        guard let idx = objectives.firstIndex(where: { $0.id == id }) else { return }
        objectives[idx].status = .stopped
        save()
        FlightRecorder.logEvent(category: "objective", action: "stopped", detail: id)
    }

    func advancePhase(_ id: String) {
        guard let idx = objectives.firstIndex(where: { $0.id == id }) else { return }
        objectives[idx].currentPhaseIndex += 1
        objectives[idx].lastActivity = Date()

        let playbook = PlaybookLibrary.all.first(where: { $0.id == objectives[idx].playbookId })
        if let playbook, objectives[idx].currentPhaseIndex >= playbook.phases.count {
            objectives[idx].status = .completed
            FlightRecorder.logEvent(category: "objective", action: "completed", detail: id)
        }
        save()
    }

    func incrementTasksCreated(_ id: String, by count: Int = 1) {
        guard let idx = objectives.firstIndex(where: { $0.id == id }) else { return }
        objectives[idx].tasksCreated += count
        objectives[idx].lastActivity = Date()
        save()
    }

    func incrementTasksCompleted(_ id: String, by count: Int = 1) {
        guard let idx = objectives.firstIndex(where: { $0.id == id }) else { return }
        objectives[idx].tasksCompleted += count
        save()
    }

    // MARK: - Active Objectives (for heartbeat consumption)

    var activeObjectives: [Objective] {
        objectives.filter { $0.status == .active }
    }

    var hasActiveObjectives: Bool {
        !activeObjectives.isEmpty
    }

    /// Generate the objectives context block for Thrawn's heartbeat prompt.
    /// This tells Thrawn what to work on.
    func heartbeatContext() -> String? {
        let active = activeObjectives
        guard !active.isEmpty else {
            // Fallback protocol — always have something to do
            return """
            ## Active Objectives: NONE

            **FALLBACK PROTOCOL ACTIVE** — No user-defined objectives are running.
            Default to NDAI Improvement: scan for product improvements, marketing opportunities,
            operational efficiency, and strategic research for NDAI.
            Create tasks from the NDAI Improvement playbook. The factory never stops.
            """
        }

        var context = "## Active Objectives (\(active.count))\n\n"
        for obj in active {
            guard let playbook = PlaybookLibrary.all.first(where: { $0.id == obj.playbookId }) else { continue }
            let currentPhase = obj.currentPhaseIndex < playbook.phases.count
                ? playbook.phases[obj.currentPhaseIndex]
                : nil

            context += "### \(obj.id): \(playbook.name) — \"\(obj.input)\"\n"
            context += "- Progress: Phase \(obj.currentPhaseIndex + 1)/\(playbook.phases.count)"
            context += " | Tasks: \(obj.tasksCompleted)/\(obj.tasksCreated) done\n"

            if let phase = currentPhase {
                context += "- **Current Phase: \(phase.name)** (phase index: \(obj.currentPhaseIndex), assign to \(phase.agent))\n"
                let description = phase.description.replacingOccurrences(of: "{{INPUT}}", with: obj.input)
                context += "- Phase instructions: \(description)\n"
                let taskTitle = phase.taskTemplate.replacingOccurrences(of: "{{INPUT}}", with: obj.input)
                context += "- Task title template: \(taskTitle)\n"
                context += "- When creating tasks for this phase, include `\"objective\": \"\(obj.id)\", \"phase\": \(obj.currentPhaseIndex)` on the create action so the scanner can count them correctly.\n"
            } else {
                context += "- All phases complete — mark this objective as Done\n"
            }
            context += "\n"
        }

        context += """
        **Your job:** For each active objective, check if the current phase has tasks on the board.
        If not, CREATE tasks for the current phase using the task title template. Always include
        `"objective"` and `"phase"` on the create action so the harness can track them.

        **Phase advancement is AUTOMATIC.** The board scanner advances the current phase as soon as
        every task linked to it is marked Done — you do NOT need to manually advance phases. Just
        keep creating tasks for whatever phase index you're shown in the Current Phase line above.

        If tasks are in progress, route/review as normal. Never leave the factory idle.
        """

        return context
    }

    // MARK: - Persistence

    private func save() {
        let dir = objectivesFile.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(objectives) {
            try? data.write(to: objectivesFile, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: objectivesFile) else { return }
        objectives = (try? JSONDecoder().decode([Objective].self, from: data)) ?? []
    }
}
