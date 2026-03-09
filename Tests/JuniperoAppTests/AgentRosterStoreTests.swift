#if canImport(Testing)
import Testing
@testable import JuniperoApp

struct AgentRosterStoreTests {
    @Test
    func parseAgentMetadataDecodesCLIJSON() throws {
        let data = Data(
            """
            [
              {
                "id": "tywin",
                "name": "Tywin Lannister",
                "identityName": "O'Brien",
                "workspace": "/Users/test/.openclaw/workspace",
                "agentDir": "/Users/test/.openclaw/agents/tywin",
                "model": "anthropic/claude-sonnet-4-6",
                "isDefault": true
              },
              {
                "id": "qyburn",
                "name": "Qyburn",
                "workspace": "/Users/test/.openclaw/workspace-qyburn",
                "agentDir": "/Users/test/.openclaw/agents/qyburn",
                "model": "ollama/qwen2.5-coder:7b",
                "isDefault": false
              }
            ]
            """.utf8
        )

        let decoded = try AgentRosterStore.parseAgentMetadata(from: data)

        #expect(decoded.count == 2)
        #expect(decoded.first?.id == "tywin")
        #expect(decoded.first?.identityName == "O'Brien")
        #expect(decoded.last?.model == "ollama/qwen2.5-coder:7b")
    }

    @Test
    func parseLatestSessionUpdateHandlesDictionaryStore() {
        let data = Data(
            """
            {
              "agent:tywin:main": {
                "sessionId": "abc",
                "updatedAt": 1773009028821
              },
              "agent:tywin:heartbeat": {
                "sessionId": "def",
                "updatedAt": 1773008028821
              }
            }
            """.utf8
        )

        let latest = AgentRosterStore.parseLatestSessionUpdate(from: data)

        #expect(latest != nil)
        #expect(abs((latest?.timeIntervalSince1970 ?? 0) - 1773009028.821) < 0.001)
    }

    @Test
    func parseLatestSessionUpdateIgnoresHeartbeatAndCronSessions() {
        let data = Data(
            """
            {
              "agent:tywin:main": {
                "sessionId": "abc",
                "updatedAt": 1773009028821,
                "lastTo": "heartbeat",
                "origin": {
                  "provider": "heartbeat",
                  "label": "heartbeat",
                  "from": "heartbeat",
                  "to": "heartbeat"
                },
                "deliveryContext": {
                  "to": "heartbeat"
                }
              },
              "agent:tywin:cron:1": {
                "sessionId": "def",
                "updatedAt": 1773009128821
              },
              "agent:tywin:handoff": {
                "sessionId": "ghi",
                "updatedAt": 1773009228821,
                "lastTo": "obrien",
                "origin": {
                  "provider": "agent",
                  "label": "handoff"
                }
              }
            }
            """.utf8
        )

        let latest = AgentRosterStore.parseLatestSessionUpdate(from: data)

        #expect(latest != nil)
        #expect(abs((latest?.timeIntervalSince1970 ?? 0) - 1773009228.821) < 0.001)
    }

    @Test
    func parseLatestSessionUpdateReturnsNilForHeartbeatOnlyStores() {
        let data = Data(
            """
            {
              "agent:tywin:main": {
                "sessionId": "abc",
                "updatedAt": 1773009028821,
                "lastTo": "heartbeat",
                "origin": {
                  "provider": "heartbeat"
                }
              },
              "agent:tywin:cron:1": {
                "sessionId": "def",
                "updatedAt": 1773009128821
              }
            }
            """.utf8
        )

        let latest = AgentRosterStore.parseLatestSessionUpdate(from: data)

        #expect(latest == nil)
    }

    @Test
    func parseLatestSessionUpdateHandlesWrappedSessionsArray() {
        let data = Data(
            """
            {
              "sessions": [
                {
                  "key": "agent:main:openai:1",
                  "updatedAt": 1773010552339
                },
                {
                  "key": "agent:main:openai:2",
                  "updatedAt": 1773010460930
                }
              ]
            }
            """.utf8
        )

        let latest = AgentRosterStore.parseLatestSessionUpdate(from: data)

        #expect(latest != nil)
        #expect(abs((latest?.timeIntervalSince1970 ?? 0) - 1773010552.339) < 0.001)
    }

    @Test
    func parseActiveTaskBoardOwnersReadsOnlyInProgressAndReview() {
        let markdown =
            """
            # TASK_BOARD.md

            ## Active Tasks

            | TASK-ID | Owner | Status | Description | Assigned By | Notes |
            |---------|-------|--------|-------------|-------------|-------|
            | TASK-001 | Qyburn | IN_PROGRESS | Build automation | Tywin | — |
            | TASK-002 | Samwell Tarly | QUEUED | Research | Tywin | — |

            ## In Review

            | TASK-ID | Owner | Status | Description | Output Location |
            |---------|-------|--------|-------------|-----------------|
            | TASK-003 | Tyrion | REVIEW | Draft proposal | /tmp/out.md |
            """

        let owners = AgentRosterStore.parseActiveTaskBoardOwners(from: markdown)

        #expect(owners == Set(["qyburn", "tyrion"]))
    }

    @Test
    func parseActiveTaskBoardOwnersReadsBlockFormatTasks() {
        let markdown =
            """
            # TASK_BOARD.md

            ## Active Tasks

            ### TASK-101 — Build automation
            **Status:** IN_PROGRESS
            **Owner:** Qyburn
            **Dispatched:** Mar 8
            **Due:** next session

            ### TASK-102 — Landing page copy
            **Status:** QUEUED
            **Owner:** Tyrion

            ## In Review

            ### TASK-103 — Research pass
            **Status:** REVIEW
            **Owner:** Samwell Tarly
            """

        let owners = AgentRosterStore.parseActiveTaskBoardOwners(from: markdown)

        #expect(owners == Set(["qyburn", "samwell"]))
    }

    @Test
    func parseActiveTaskBoardOwnersUsesSectionHintForReviewBlocks() {
        let markdown =
            """
            # TASK_BOARD.md

            ## In Review

            ### TASK-201 — Ops audit
            **Owner:** Varys
            **Output:** /tmp/ops.md
            """

        let owners = AgentRosterStore.parseActiveTaskBoardOwners(from: markdown)

        #expect(owners == Set(["varys"]))
    }

    @Test
    func composeEntriesKeepsFixedSevenOrder() {
        let metadata = makeMetadataMap(ids: ["qyburn", "tywin", "varys", "bran", "samwell", "tyrion"])
        let entries = AgentRosterStore.composeEntries(
            metadataByID: metadata,
            defaultAgentID: "tywin",
            snapshot: makeSnapshot(),
            home: URL(fileURLWithPath: "/Users/test"),
            activityWindow: 600
        )

        #expect(entries.map(\.displayName) == ["O'Brien", "Tywin", "Samwell", "Bran", "Qyburn", "Tyrion", "Varys"])
    }

    @Test
    func composeEntriesLightsOnlyOBrienWhenThreadIsSending() {
        let entries = AgentRosterStore.composeEntries(
            metadataByID: makeMetadataMap(ids: ["tywin", "samwell", "bran", "qyburn", "tyrion", "varys"]),
            defaultAgentID: "tywin",
            snapshot: makeSnapshot(threadSending: true),
            home: URL(fileURLWithPath: "/Users/test"),
            activityWindow: 600
        )

        #expect(entry(id: "obrien", in: entries).isActive)
        #expect(entry(id: "obrien", in: entries).activitySource == .currentChat)
        #expect(entries.filter { $0.id != "obrien" }.allSatisfy { !$0.isActive })
    }

    @Test
    func composeEntriesLightsMatchingAgentForRecentSession() {
        let now = Date(timeIntervalSince1970: 1_773_010_600)
        let entries = AgentRosterStore.composeEntries(
            metadataByID: makeMetadataMap(ids: ["tywin", "samwell", "bran", "qyburn", "tyrion", "varys"]),
            defaultAgentID: "tywin",
            snapshot: makeSnapshot(
                sessionUpdates: ["qyburn": now.addingTimeInterval(-120)],
                unreadableSessionIDs: ["samwell", "bran", "tyrion", "varys"],
                now: now
            ),
            home: URL(fileURLWithPath: "/Users/test"),
            activityWindow: 600
        )

        #expect(entry(id: "qyburn", in: entries).isActive)
        #expect(entry(id: "qyburn", in: entries).activitySource == .liveSession)
        #expect(!entry(id: "tyrion", in: entries).isActive)
    }

    @Test
    func composeEntriesLightsTaskBoardOwnerWithoutSessionFile() {
        let entries = AgentRosterStore.composeEntries(
            metadataByID: makeMetadataMap(ids: ["tywin", "samwell", "bran", "qyburn", "tyrion", "varys"]),
            defaultAgentID: "tywin",
            snapshot: makeSnapshot(
                unreadableSessionIDs: ["samwell", "bran", "qyburn", "tyrion", "varys"],
                taskBoardActiveOwners: ["tyrion"],
                taskBoardReadable: true
            ),
            home: URL(fileURLWithPath: "/Users/test"),
            activityWindow: 600
        )

        #expect(entry(id: "tyrion", in: entries).isActive)
        #expect(entry(id: "tyrion", in: entries).activitySource == .taskBoard)
    }

    @Test
    func composeEntriesDimsStaleSessionWhenOutsideActivityWindow() {
        let now = Date(timeIntervalSince1970: 1_773_010_600)
        let entries = AgentRosterStore.composeEntries(
            metadataByID: makeMetadataMap(ids: ["tywin", "samwell", "bran", "qyburn", "tyrion", "varys"]),
            defaultAgentID: "tywin",
            snapshot: makeSnapshot(
                sessionUpdates: ["samwell": now.addingTimeInterval(-1200)],
                unreadableSessionIDs: ["bran", "qyburn", "tyrion", "varys"],
                now: now
            ),
            home: URL(fileURLWithPath: "/Users/test"),
            activityWindow: 600
        )

        #expect(!entry(id: "samwell", in: entries).isActive)
        #expect(entry(id: "samwell", in: entries).activitySource == .idle)
    }

    private func makeSnapshot(
        threadSending: Bool = false,
        mainSessionUpdate: Date? = nil,
        mainSessionReadable: Bool = true,
        sessionUpdates: [String: Date] = [:],
        unreadableSessionIDs: Set<String> = ["samwell", "bran", "qyburn", "tyrion", "varys"],
        taskBoardActiveOwners: Set<String> = [],
        taskBoardReadable: Bool = true,
        now: Date = Date(timeIntervalSince1970: 1_773_010_600)
    ) -> AgentActivitySnapshot {
        AgentActivitySnapshot(
            threadSending: threadSending,
            mainSessionUpdate: mainSessionUpdate,
            mainSessionReadable: mainSessionReadable,
            sessionUpdates: sessionUpdates,
            unreadableSessionIDs: unreadableSessionIDs,
            taskBoardActiveOwners: taskBoardActiveOwners,
            taskBoardReadable: taskBoardReadable,
            now: now
        )
    }

    private func makeMetadataMap(ids: [String]) -> [String: OpenClawAgentMetadata] {
        Dictionary(uniqueKeysWithValues: ids.map { id in
            (
                id,
                OpenClawAgentMetadata(
                    id: id,
                    name: fullName(for: id),
                    identityName: id == "tywin" ? "O'Brien" : nil,
                    workspace: "/Users/test/.openclaw/workspace-\(id)",
                    agentDir: "/Users/test/.openclaw/agents/\(id)",
                    model: id == "qyburn" ? "ollama/qwen2.5-coder:7b" : "anthropic/claude-sonnet-4-6",
                    isDefault: id == "tywin"
                )
            )
        })
    }

    private func fullName(for id: String) -> String {
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

    private func entry(id: String, in entries: [AgentRailEntry]) -> AgentRailEntry {
        entries.first(where: { $0.id == id })!
    }
}
#endif
