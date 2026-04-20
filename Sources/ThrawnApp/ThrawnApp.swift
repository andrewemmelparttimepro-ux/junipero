import SwiftUI

@main
struct ThrawnApp: App {
    @StateObject private var threadStore = ThreadStore()
    @StateObject private var bootstrap = ThrawnBootstrap()
    @StateObject private var updateManager = UpdateManager()
    @StateObject private var sparkleUpdater = SparkleUpdaterService()
    @StateObject private var roster = AgentRosterStore()
    @StateObject private var nav = ConsoleNavigationStore()
    @StateObject private var flowTab = FlowTabStore()
    @StateObject private var screenCapture = ScreenCaptureStore()

    // LLM clients
    @StateObject private var ollama = OllamaClient()
    @StateObject private var openaiClient = OpenAIClient(model: ProviderRouter.premiumOpenAIModel)
    @StateObject private var scheduler = AgentScheduler()
    @StateObject private var dispatcher = TaskDispatcher()
    @StateObject private var execution = ExecutionService()
    @StateObject private var objectiveStore = ObjectiveStore()
    @StateObject private var handoffStore = HandoffStore()
    @StateObject private var loadoutStore = StandardLoadoutStore()
    @StateObject private var specStore = AgentSpecStore()
    @StateObject private var rankEvaluator = RankEvaluator()

    // Voice + briefings (native AVSpeechSynthesizer stack)
    @StateObject private var voiceService = VoiceService()
    @StateObject private var briefingService = BriefingService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(threadStore)
                .environmentObject(bootstrap)
                .environmentObject(updateManager)
                .environmentObject(sparkleUpdater)
                .environmentObject(roster)
                .environmentObject(nav)
                .environmentObject(flowTab)
                .environmentObject(ollama)
                .environmentObject(openaiClient)
                .environmentObject(scheduler)
                .environmentObject(dispatcher)
                .environmentObject(screenCapture)
                .environmentObject(execution)
                .environmentObject(objectiveStore)
                .environmentObject(handoffStore)
                .environmentObject(loadoutStore)
                .environmentObject(specStore)
                .environmentObject(rankEvaluator)
                .environmentObject(voiceService)
                .environmentObject(briefingService)
                .frame(minWidth: 1180, minHeight: 720)
                .task {
                    // 0. Flight recorder setup — workspace dirs + log rotation
                    SystemPromptBuilder.ensureWorkspaceDirs()
                    FlightRecorder.rotateOldLogs()
                    FlightRecorder.logEvent(category: "app", action: "launch", detail: "Thrawn Console started")

                    // 1. Deploy operational code from OpsBundle → data directory
                    ThrawnPaths.deployOpsBundle()

                    // 2. Connect to Ollama (local LLM) + OpenAI (premium thread routing)
                    ollama.connect()
                    threadStore.bindOllamaClient(ollama)
                    threadStore.bindOpenAIClient(openaiClient)
                    threadStore.bindExecutionService(execution)
                    bootstrap.bindOllamaClient(ollama)

                    // 3. Agent roster + jewel tracking
                    roster.bindToThreadStore(threadStore)
                    roster.bindToScheduler(scheduler)

                    // 4. Agent specs + standard loadout → tool registry
                    specStore.bind(loadout: loadoutStore)
                    ToolRegistry.specStore = specStore
                    AgentSpecStore.ensureKnowledgeDirs(for: specStore.specs)
                    rankEvaluator.bind(specs: specStore)

                    // 4a. Voice + briefings (native AVSpeech stack)
                    voiceService.bind(specStore: specStore)

                    // 5. Native agent scheduler + task dispatcher
                    handoffStore.bind(objectives: objectiveStore, rankEvaluator: rankEvaluator)
                    scheduler.bind(
                        ollamaClient: ollama,
                        roster: roster,
                        execution: execution,
                        objectives: objectiveStore,
                        handoffs: handoffStore,
                        specs: specStore,
                        openai: openaiClient
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
                    scheduler.start()
                    dispatcher.start()

                    // 5. Execution service health
                    await execution.checkBackendHealth()

                    // 6. Bootstrap (auto-completes — no API key needed)
                    await bootstrap.startIfNeeded()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 840)
    }
}
