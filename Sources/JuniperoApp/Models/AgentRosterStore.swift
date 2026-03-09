import Foundation
import SwiftUI

struct AgentPresentation {
    let id: String
    let displayName: String
    let roleTitle: String
    let roleNote: String
    let accentColor: Color
    let symbolName: String
    let isPrimaryIdentity: Bool

    static let ordered: [AgentPresentation] = [
        AgentPresentation(
            id: "obrien",
            displayName: "O'Brien",
            roleTitle: "Personal Assistant",
            roleNote: "Main session / front identity",
            accentColor: Color(red: 0.34, green: 0.92, blue: 1.0),
            symbolName: "sparkles",
            isPrimaryIdentity: true
        ),
        AgentPresentation(
            id: "tywin",
            displayName: "Tywin",
            roleTitle: "Expo / Triage",
            roleNote: "Routes tasks, manages handoffs",
            accentColor: Color(red: 0.93, green: 0.73, blue: 0.34),
            symbolName: "crown.fill",
            isPrimaryIdentity: false
        ),
        AgentPresentation(
            id: "samwell",
            displayName: "Samwell",
            roleTitle: "Researcher",
            roleNote: "Reads everything, large context",
            accentColor: Color(red: 0.96, green: 0.74, blue: 0.36),
            symbolName: "book.closed.fill",
            isPrimaryIdentity: false
        ),
        AgentPresentation(
            id: "bran",
            displayName: "Bran",
            roleTitle: "Web Builder",
            roleNote: "HTML / CSS / JS",
            accentColor: Color(red: 0.54, green: 0.76, blue: 0.98),
            symbolName: "globe",
            isPrimaryIdentity: false
        ),
        AgentPresentation(
            id: "qyburn",
            displayName: "Qyburn",
            roleTitle: "Coder",
            roleNote: "Scripts, APIs, backend, automation",
            accentColor: Color(red: 0.58, green: 0.92, blue: 0.78),
            symbolName: "terminal.fill",
            isPrimaryIdentity: false
        ),
        AgentPresentation(
            id: "tyrion",
            displayName: "Tyrion",
            roleTitle: "Scribe",
            roleNote: "Writing, copy, proposals",
            accentColor: Color(red: 0.86, green: 0.60, blue: 0.54),
            symbolName: "text.quote",
            isPrimaryIdentity: false
        ),
        AgentPresentation(
            id: "varys",
            displayName: "Varys",
            roleTitle: "Ops",
            roleNote: "System tasks, diagnostics, cron",
            accentColor: Color(red: 0.83, green: 0.85, blue: 0.89),
            symbolName: "eye.fill",
            isPrimaryIdentity: false
        ),
    ]

    static let byID: [String: AgentPresentation] = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
}

enum AgentActivitySource: String {
    case currentChat
    case liveSession
    case taskBoard
    case idle
    case unavailable

    var label: String {
        switch self {
        case .currentChat:
            return "Current Chat"
        case .liveSession:
            return "Live Session"
        case .taskBoard:
            return "Task Board"
        case .idle:
            return "Idle"
        case .unavailable:
            return "Unavailable"
        }
    }
}

struct AgentRailEntry: Identifiable {
    let id: String
    let presentation: AgentPresentation
    let displayName: String
    let popoverTitle: String
    let model: String?
    let lastActiveAt: Date?
    let activitySource: AgentActivitySource
    let isActive: Bool
    let workspacePath: String?
    let agentDirPath: String?
    let isDefaultAgent: Bool
    let backingAgentName: String?
}

struct AgentActivitySnapshot {
    let threadSending: Bool
    let mainSessionUpdate: Date?
    let mainSessionReadable: Bool
    let sessionUpdates: [String: Date]
    let unreadableSessionIDs: Set<String>
    let taskBoardActiveOwners: Set<String>
    let taskBoardReadable: Bool
    let now: Date
}

struct OpenClawAgentMetadata: Decodable {
    let id: String
    let name: String?
    let identityName: String?
    let workspace: String?
    let agentDir: String?
    let model: String?
    let isDefault: Bool?
}

enum SessionStoreReadResult {
    case success(Date?)
    case missing
    case failure
}

private struct SessionCandidate {
    let key: String?
    let payload: [String: Any]
}

@MainActor
final class AgentRosterStore: ObservableObject {
    @Published var entries: [AgentRailEntry] = AgentRosterStore.placeholderEntries()
    @Published var lastRefreshAt: Date?
    @Published var rosterAvailable: Bool = false

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let activityWindow: TimeInterval = 600
    private let rosterRefreshInterval: TimeInterval = 60
    private var refreshTask: Task<Void, Never>?
    private var lastKnownThreadSending = false
    private var lastRosterRefreshAt: Date?
    private var metadataByID: [String: OpenClawAgentMetadata] = [:]
    private var defaultAgentID: String?

    deinit {
        refreshTask?.cancel()
    }

    func start(threadSending: Bool = false) {
        lastKnownThreadSending = threadSending
        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh(threadSending: threadSending)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await self.refresh(threadSending: self.lastKnownThreadSending)
            }
        }
    }

    func refresh(threadSending: Bool) async {
        lastKnownThreadSending = threadSending
        let now = Date()
        if shouldRefreshRoster(now: now) {
            await loadRosterMetadata(now: now)
        }

        let mainSessionPath = home
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent("main", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("sessions.json")

        let mainSessionRead = Self.readLatestSessionUpdate(at: mainSessionPath)

        var sessionUpdates: [String: Date] = [:]
        var unreadableSessionIDs = Set<String>()

        for presentation in AgentPresentation.ordered where presentation.id != "obrien" {
            let metadata = metadataByID[presentation.id]
            let sessionPath = Self.sessionStorePath(for: presentation.id, metadata: metadata, home: home)
            switch Self.readLatestSessionUpdate(at: sessionPath) {
            case .success(let date):
                if let date {
                    sessionUpdates[presentation.id] = date
                }
            case .missing:
                unreadableSessionIDs.insert(presentation.id)
            case .failure:
                unreadableSessionIDs.insert(presentation.id)
            }
        }

        let taskBoardPath = home
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("workspace-main", isDirectory: true)
            .appendingPathComponent("TASK_BOARD.md")
        let taskBoardContent = try? String(contentsOf: taskBoardPath, encoding: .utf8)
        let taskBoardReadable = (taskBoardContent != nil)
        let activeOwners = taskBoardContent.map(Self.parseActiveTaskBoardOwners(from:)) ?? []

        let snapshot = AgentActivitySnapshot(
            threadSending: threadSending,
            mainSessionUpdate: {
                if case .success(let date) = mainSessionRead { return date }
                return nil
            }(),
            mainSessionReadable: {
                if case .success = mainSessionRead { return true }
                return false
            }(),
            sessionUpdates: sessionUpdates,
            unreadableSessionIDs: unreadableSessionIDs,
            taskBoardActiveOwners: activeOwners,
            taskBoardReadable: taskBoardReadable,
            now: now
        )

        entries = Self.composeEntries(
            metadataByID: metadataByID,
            defaultAgentID: defaultAgentID,
            snapshot: snapshot,
            home: home,
            activityWindow: activityWindow
        )
        lastRefreshAt = now
    }

    private func shouldRefreshRoster(now: Date) -> Bool {
        guard let lastRosterRefreshAt else { return true }
        return now.timeIntervalSince(lastRosterRefreshAt) >= rosterRefreshInterval
    }

    private func loadRosterMetadata(now: Date) async {
        let result = await ShellCommand.run("openclaw agents list --json")
        defer { lastRosterRefreshAt = now }

        guard result.exitCode == 0,
              let data = result.stdout.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([OpenClawAgentMetadata].self, from: data) else {
            rosterAvailable = false
            return
        }

        metadataByID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
        defaultAgentID = decoded.first(where: { $0.isDefault == true })?.id
        rosterAvailable = true
    }

    static func placeholderEntries() -> [AgentRailEntry] {
        composeEntries(
            metadataByID: [:],
            defaultAgentID: nil,
            snapshot: AgentActivitySnapshot(
                threadSending: false,
                mainSessionUpdate: nil,
                mainSessionReadable: false,
                sessionUpdates: [:],
                unreadableSessionIDs: Set(AgentPresentation.ordered.map(\.id)),
                taskBoardActiveOwners: [],
                taskBoardReadable: false,
                now: Date()
            ),
            home: FileManager.default.homeDirectoryForCurrentUser,
            activityWindow: 600
        )
    }

    static func parseAgentMetadata(from data: Data) throws -> [OpenClawAgentMetadata] {
        try JSONDecoder().decode([OpenClawAgentMetadata].self, from: data)
    }

    static func parseLatestSessionUpdate(from data: Data) -> Date? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }

        if let dictionary = object as? [String: Any] {
            if let sessions = dictionary["sessions"] as? [[String: Any]] {
                return latestSessionDate(
                    from: sessions.map { SessionCandidate(key: $0["key"] as? String, payload: $0) }
                )
            }
            let sessions = dictionary.compactMap { key, value -> SessionCandidate? in
                guard let payload = value as? [String: Any] else { return nil }
                return SessionCandidate(key: key, payload: payload)
            }
            return latestSessionDate(from: sessions)
        }

        if let sessions = object as? [[String: Any]] {
            return latestSessionDate(
                from: sessions.map { SessionCandidate(key: $0["key"] as? String, payload: $0) }
            )
        }

        return nil
    }

    static func parseActiveTaskBoardOwners(from markdown: String) -> Set<String> {
        var activeOwners = Set<String>()
        var inRelevantSection = false
        var sectionStatusHint: String?
        var blockOwner: String?
        var blockStatus: String?

        func flushBlock() {
            guard let owner = blockOwner else { return }
            let resolvedStatus = normalizeTaskStatus(blockStatus) ?? sectionStatusHint
            guard resolvedStatus == "IN_PROGRESS" || resolvedStatus == "REVIEW" else {
                blockOwner = nil
                blockStatus = nil
                return
            }
            guard let ownerID = normalizeOwner(owner) else {
                blockOwner = nil
                blockStatus = nil
                return
            }
            activeOwners.insert(ownerID)
            blockOwner = nil
            blockStatus = nil
        }

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                flushBlock()
                if line == "## Active Tasks" {
                    inRelevantSection = true
                    sectionStatusHint = "IN_PROGRESS"
                } else if line == "## In Review" {
                    inRelevantSection = true
                    sectionStatusHint = "REVIEW"
                } else {
                    inRelevantSection = false
                    sectionStatusHint = nil
                }
                continue
            }
            guard inRelevantSection else { continue }

            if line.hasPrefix("### ") {
                flushBlock()
                continue
            }

            if line.hasPrefix("|") {
                let columns = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                guard columns.count >= 3 else { continue }
                let owner = columns[1]
                let status = normalizeTaskStatus(columns[2]) ?? columns[2].uppercased()
                guard status == "IN_PROGRESS" || status == "REVIEW" else { continue }
                guard let ownerID = normalizeOwner(owner) else { continue }
                activeOwners.insert(ownerID)
                continue
            }

            if let owner = markdownFieldValue(line, label: "Owner") {
                blockOwner = owner
                continue
            }

            if let status = markdownFieldValue(line, label: "Status") {
                blockStatus = status
                continue
            }
        }

        flushBlock()
        return activeOwners
    }

    static func composeEntries(
        metadataByID: [String: OpenClawAgentMetadata],
        defaultAgentID: String?,
        snapshot: AgentActivitySnapshot,
        home: URL,
        activityWindow: TimeInterval
    ) -> [AgentRailEntry] {
        let defaultAgent = defaultAgentID.flatMap { metadataByID[$0] } ?? metadataByID["tywin"]
        return AgentPresentation.ordered.map { presentation in
            let metadata: OpenClawAgentMetadata?
            if presentation.id == "obrien" {
                metadata = defaultAgent
            } else {
                metadata = metadataByID[presentation.id]
            }

            let isDefaultBackingAgent = (presentation.id != "obrien" && presentation.id == defaultAgentID)
            let fullTitle = popoverTitle(for: presentation.id, metadata: metadata)
            let model = metadata?.model
            let workspacePath = metadata?.workspace ?? fallbackWorkspacePath(for: presentation.id, home: home)
            let agentDirPath = metadata?.agentDir ?? fallbackAgentDirPath(for: presentation.id, home: home)

            let resolved: (Bool, AgentActivitySource, Date?) = {
                if presentation.id == "obrien" {
                    if snapshot.threadSending {
                        return (true, .currentChat, snapshot.now)
                    }
                    if let updatedAt = snapshot.mainSessionUpdate,
                       snapshot.now.timeIntervalSince(updatedAt) <= activityWindow {
                        return (true, .liveSession, updatedAt)
                    }
                    if snapshot.mainSessionReadable {
                        return (false, .idle, snapshot.mainSessionUpdate)
                    }
                    return (false, .unavailable, nil)
                }

                if let updatedAt = snapshot.sessionUpdates[presentation.id],
                   snapshot.now.timeIntervalSince(updatedAt) <= activityWindow {
                    return (true, .liveSession, updatedAt)
                }
                if snapshot.taskBoardActiveOwners.contains(presentation.id) {
                    return (true, .taskBoard, snapshot.now)
                }

                let sessionKnownUnavailable = snapshot.unreadableSessionIDs.contains(presentation.id)
                if sessionKnownUnavailable && !snapshot.taskBoardReadable {
                    return (false, .unavailable, nil)
                }
                return (false, .idle, snapshot.sessionUpdates[presentation.id])
            }()

            return AgentRailEntry(
                id: presentation.id,
                presentation: presentation,
                displayName: presentation.displayName,
                popoverTitle: fullTitle,
                model: model,
                lastActiveAt: resolved.2,
                activitySource: resolved.1,
                isActive: resolved.0,
                workspacePath: workspacePath,
                agentDirPath: agentDirPath,
                isDefaultAgent: isDefaultBackingAgent,
                backingAgentName: metadata?.name
            )
        }
    }

    private static func latestSessionDate(from sessions: [SessionCandidate]) -> Date? {
        let relevantSessions = sessions.filter { !isBackgroundSession($0) }

        return relevantSessions.compactMap { item in
            sessionDate(from: item.payload)
        }.max()
    }

    static func readLatestSessionUpdate(at url: URL) -> SessionStoreReadResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url) else { return .failure }
        return .success(parseLatestSessionUpdate(from: data))
    }

    private static func sessionDate(from item: [String: Any]) -> Date? {
        if let updatedAt = item["updatedAt"] as? NSNumber {
            return Date(timeIntervalSince1970: updatedAt.doubleValue / 1000.0)
        }
        if let updatedAt = item["updatedAt"] as? Double {
            return Date(timeIntervalSince1970: updatedAt / 1000.0)
        }
        if let updatedAt = item["updatedAt"] as? Int {
            return Date(timeIntervalSince1970: Double(updatedAt) / 1000.0)
        }
        return nil
    }

    private static func isBackgroundSession(_ session: SessionCandidate) -> Bool {
        if let key = session.key?.lowercased(),
           key.contains(":cron:")
            || key.hasSuffix(":cron")
            || key.contains(":heartbeat:")
            || key.hasSuffix(":heartbeat")
        {
            return true
        }

        if normalizedSessionValue(session.payload["lastTo"]) == "heartbeat" {
            return true
        }

        if let deliveryContext = session.payload["deliveryContext"] as? [String: Any],
           normalizedSessionValue(deliveryContext["to"]) == "heartbeat"
        {
            return true
        }

        if let origin = session.payload["origin"] as? [String: Any] {
            let markers = [
                normalizedSessionValue(origin["provider"]),
                normalizedSessionValue(origin["label"]),
                normalizedSessionValue(origin["from"]),
                normalizedSessionValue(origin["to"]),
            ]
            if markers.contains("heartbeat") || markers.contains("cron") {
                return true
            }
        }

        return false
    }

    private static func normalizedSessionValue(_ value: Any?) -> String? {
        (value as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func sessionStorePath(for id: String, metadata: OpenClawAgentMetadata?, home: URL) -> URL {
        if let agentDir = metadata?.agentDir {
            return URL(fileURLWithPath: agentDir, isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
                .appendingPathComponent("sessions.json")
        }

        return fallbackAgentDirURL(for: id, home: home)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("sessions.json")
    }

    static func normalizeOwner(_ rawOwner: String) -> String? {
        let cleaned = rawOwner
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "—", with: "")

        let aliases: [String: String] = [
            "o'brien": "obrien",
            "obrien": "obrien",
            "tywin": "tywin",
            "tywin lannister": "tywin",
            "samwell": "samwell",
            "samwell tarly": "samwell",
            "bran": "bran",
            "bran stark": "bran",
            "qyburn": "qyburn",
            "tyrion": "tyrion",
            "tyrion lannister": "tyrion",
            "varys": "varys",
        ]

        return aliases[cleaned]
    }

    private static func markdownFieldValue(_ line: String, label: String) -> String? {
        let prefix = "**\(label):**"
        guard line.hasPrefix(prefix) else { return nil }
        return line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeTaskStatus(_ rawStatus: String?) -> String? {
        guard let rawStatus else { return nil }
        let cleaned = rawStatus
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func popoverTitle(for id: String, metadata: OpenClawAgentMetadata?) -> String {
        if id == "obrien" {
            return "O'Brien"
        }
        if let metadataName = metadata?.name, !metadataName.isEmpty {
            return metadataName
        }

        switch id {
        case "tywin":
            return "Tywin Lannister"
        case "samwell":
            return "Samwell Tarly"
        case "bran":
            return "Bran Stark"
        case "qyburn":
            return "Qyburn"
        case "tyrion":
            return "Tyrion Lannister"
        case "varys":
            return "Varys"
        default:
            return id.capitalized
        }
    }

    private static func fallbackWorkspacePath(for id: String, home: URL) -> String {
        let base = home.appendingPathComponent(".openclaw", isDirectory: true)
        if id == "obrien" || id == "tywin" {
            return base.appendingPathComponent("workspace").path
        }
        return base.appendingPathComponent("workspace-\(id)").path
    }

    private static func fallbackAgentDirPath(for id: String, home: URL) -> String {
        if id == "obrien" {
            return fallbackAgentDirURL(for: "tywin", home: home).path
        }
        return fallbackAgentDirURL(for: id, home: home).path
    }

    private static func fallbackAgentDirURL(for id: String, home: URL) -> URL {
        home.appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }
}
