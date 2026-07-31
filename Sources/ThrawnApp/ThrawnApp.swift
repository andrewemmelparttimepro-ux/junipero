import SwiftUI

@main
struct ThrawnApp: App {
    private let didResetV2AtBoot = ThrawnV2ResetService.performIfNeeded()

    @StateObject private var threadStore = ThreadStore()
    @StateObject private var bootstrap = ThrawnBootstrap()
    @StateObject private var updateManager = UpdateManager()
    @StateObject private var sparkleUpdater = SparkleUpdaterService()
    @StateObject private var roster = AgentRosterStore()
    @StateObject private var nav = ConsoleNavigationStore()
    @StateObject private var productBoards = ProductBoardStore()
    @StateObject private var flowTab = FlowTabStore()
    @StateObject private var screenCapture = ScreenCaptureStore()

    // LLM clients
    @StateObject private var ollama = OllamaClient()
    @StateObject private var openaiClient = OpenAIClient(
        model: ProviderRouter.premiumOpenAIModel,
        reasoningEffort: ProviderRouter.premiumOpenAIReasoningEffort
    )
    @StateObject private var openclaw = GatewayWSClient()
    @StateObject private var agentRuntime = AgentRuntimeCoordinator()
    @StateObject private var scheduler = AgentScheduler()
    @StateObject private var dispatcher = TaskDispatcher()
    @StateObject private var execution = ExecutionService()
    @StateObject private var objectiveStore = ObjectiveStore()
    @StateObject private var handoffStore = HandoffStore()
    @StateObject private var loadoutStore = StandardLoadoutStore()
    @StateObject private var devOpsBrain = DevOpsBrainStore()
    @StateObject private var specStore = AgentSpecStore()
    @StateObject private var rankEvaluator = RankEvaluator()

    // Voice + briefings (native AVSpeechSynthesizer stack)
    @StateObject private var voiceService = VoiceService()
    @StateObject private var voiceConversation = VoiceConversationService()
    @StateObject private var briefingService = BriefingService()

    // Voice action + low-latency lanes
    @StateObject private var voiceTools = VoiceTools()
    @StateObject private var voiceFastLane = VoiceFastLane()
    @StateObject private var voiceRealtime = VoiceRealtimeService()
    @StateObject private var autonomyStore = AgentAutonomyStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(threadStore)
                .environmentObject(bootstrap)
                .environmentObject(updateManager)
                .environmentObject(sparkleUpdater)
                .environmentObject(roster)
                .environmentObject(nav)
                .environmentObject(productBoards)
                .environmentObject(flowTab)
                .environmentObject(ollama)
                .environmentObject(openaiClient)
                .environmentObject(openclaw)
                .environmentObject(agentRuntime)
                .environmentObject(scheduler)
                .environmentObject(dispatcher)
                .environmentObject(screenCapture)
                .environmentObject(execution)
                .environmentObject(objectiveStore)
                .environmentObject(handoffStore)
                .environmentObject(loadoutStore)
                .environmentObject(devOpsBrain)
                .environmentObject(specStore)
                .environmentObject(rankEvaluator)
                .environmentObject(voiceService)
                .environmentObject(voiceConversation)
                .environmentObject(briefingService)
                .environmentObject(voiceTools)
                .environmentObject(voiceFastLane)
                .environmentObject(voiceRealtime)
                .environmentObject(autonomyStore)
                .frame(minWidth: 1180, minHeight: 720)
                .task {
                    // 0. Flight recorder setup — workspace dirs + log rotation
                    let didResetV2 = didResetV2AtBoot
                    if didResetV2 {
                        roster.resetToV2Defaults()
                        specStore.resetToV2Defaults()
                        scheduler.resetToV2Defaults()
                        objectiveStore.resetToEmpty()
                        handoffStore.resetToEmpty()
                    }
                    ThrawnV2ResetService.removeLegacyV1Residue()
                    SystemPromptBuilder.ensureWorkspaceDirs()
                    FlightRecorder.rotateOldLogs()
                    FlightRecorder.logEvent(category: "app", action: "launch", detail: "Thrawn Console started")

                    // 1. Deploy operational code from OpsBundle → data directory
                    ThrawnPaths.deployOpsBundle()

                    // 2. Start the subscription-backed provider-agent runtime.
                    // Codex owns its credentials and model catalog; Thrawn only
                    // launches app-server and stores provider thread ids.
                    await agentRuntime.start()

                    // Keep explicit API/OpenClaw/Ollama adapters available for
                    // providers and unattended fallback routes.
                    ollama.connect()
                    openaiClient.connect()
                    openclaw.connect()
                    threadStore.bindOllamaClient(ollama)
                    threadStore.bindOpenAIClient(openaiClient)
                    threadStore.bindOpenClawClient(openclaw)
                    threadStore.bindAgentRuntime(agentRuntime)
                    threadStore.bindDevOpsBrain(devOpsBrain)
                    threadStore.bindExecutionService(execution)
                    bootstrap.bindOllamaClient(ollama)
                    bootstrap.bindOpenClawClient(openclaw)
                    bootstrap.bindAgentRuntime(agentRuntime)

                    // 3. Agent roster + jewel tracking
                    roster.bindToThreadStore(threadStore)
                    roster.bindToScheduler(scheduler)

                    // 4. Agent specs + standard loadout → tool registry
                    specStore.bind(loadout: loadoutStore)
                    ToolRegistry.specStore = specStore
                    threadStore.bindAgentSpecs(specStore)
                    AgentSpecStore.ensureKnowledgeDirs(for: specStore.specs)
                    rankEvaluator.bind(specs: specStore)

                    // 4a. Voice + briefings (native AVSpeech stack)
                    voiceService.bind(specStore: specStore)
                    voiceConversation.bind(threadStore: threadStore, voiceService: voiceService, nav: nav)

                    // 4b. Voice action layer + low-latency lanes.
                    // Tools run natively (no shell) and are gated by the same
                    // autonomy ceilings the heartbeats obey; the fast lane
                    // answers conversation locally; realtime takes over when
                    // an OpenAI key is present.
                    voiceTools.bind(scheduler: scheduler, dispatcher: dispatcher)
                    voiceFastLane.bind(tools: voiceTools, voice: voiceService)
                    voiceRealtime.bind(tools: voiceTools)
                    voiceRealtime.refreshConfiguration()
                    voiceConversation.bindVoiceStack(
                        tools: voiceTools,
                        fastLane: voiceFastLane,
                        realtime: voiceRealtime
                    )

                    // 5. Native agent scheduler + task dispatcher
                    handoffStore.bind(objectives: objectiveStore, rankEvaluator: rankEvaluator)
                    scheduler.bind(
                        ollamaClient: ollama,
                        roster: roster,
                        execution: execution,
                        objectives: objectiveStore,
                        handoffs: handoffStore,
                        specs: specStore,
                        devOpsBrain: devOpsBrain,
                        openclaw: openclaw,
                        openai: openaiClient,
                        agentRuntime: agentRuntime
                    )
                    // BriefingService needs the scheduler for one-shot sends,
                    // spec store for the play order, and voice for file render.
                    briefingService.bind(
                        specStore: specStore,
                        scheduler: scheduler,
                        voice: voiceService
                    )
                    // Scheduler also gets a back-ref so its tick loop can
                    // auto-fire SOD at 07:00 and EOD at 19:00 local.
                    scheduler.bind(briefing: briefingService)
                    // Voice service: heartbeat open/close announcements
                    scheduler.bind(voice: voiceService)
                    let automationDisabled =
                        ProcessInfo.processInfo.environment["THRAWN_DISABLE_AUTOMATION"] == "1"
                    if automationDisabled {
                        FlightRecorder.logEvent(
                            category: "app",
                            action: "automation_disabled",
                            detail: "Scheduled automation disabled by THRAWN_DISABLE_AUTOMATION"
                        )
                    } else {
                        scheduler.start()
                        dispatcher.start()
                    }

                    // 5. Execution service health
                    await execution.checkBackendHealth()

                    // 6. Bootstrap/readiness.
                    await bootstrap.startIfNeeded()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 840)
    }
}
