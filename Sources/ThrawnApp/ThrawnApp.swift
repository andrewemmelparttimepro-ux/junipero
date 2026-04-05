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

    // Native API + agent system (App Store compliant — no external processes)
    @StateObject private var anthropic = AnthropicClient()
    @StateObject private var geminiAPI = GeminiAPIClient()
    @StateObject private var geminiOAuth = GeminiOAuthClient()
    @StateObject private var openAI = OpenAIClient()
    @StateObject private var scheduler = AgentScheduler()
    @StateObject private var dispatcher = TaskDispatcher()
    @StateObject private var execution = ExecutionService()

    // Legacy gateway client — kept for backward compat during migration.
    // Will be fully removed once all callers switch to native API clients.
    @StateObject private var gatewayWS = GatewayWSClient()

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
                .environmentObject(gatewayWS)
                .environmentObject(anthropic)
                .environmentObject(geminiAPI)
                .environmentObject(geminiOAuth)
                .environmentObject(openAI)
                .environmentObject(scheduler)
                .environmentObject(dispatcher)
                .environmentObject(screenCapture)
                .environmentObject(execution)
                .frame(minWidth: 1200, minHeight: 800)
                .sheet(isPresented: $bootstrap.showSetup) {
                    SetupWizardView()
                        .environmentObject(bootstrap)
                        .environmentObject(anthropic)
                        .environmentObject(geminiOAuth)
                        .environmentObject(openAI)
                        .environmentObject(geminiAPI)
                }
                .task {
                    // 1. Deploy operational code from OpsBundle → data directory
                    ThrawnPaths.deployOpsBundle()

                    // 2. Start native API connections
                    anthropic.connect()
                    threadStore.bindAnthropicClient(anthropic)
                    bootstrap.bindAnthropicClient(anthropic)
                    bootstrap.bindGeminiOAuth(geminiOAuth)

                    // 2b. Gemini: bind OAuth → API client, then connect
                    geminiAPI.bindOAuth(geminiOAuth)
                    geminiOAuth.loadStoredTokens()
                    geminiAPI.connect()
                    threadStore.bindGeminiClient(geminiAPI, oauth: geminiOAuth)

                    // 2c. OpenAI: bind + connect
                    openAI.connect()
                    threadStore.bindOpenAIClient(openAI)
                    bootstrap.bindOpenAIClient(openAI)

                    // 3. Legacy gateway (fallback — will be removed)
                    gatewayWS.connectAndPrewarm()
                    threadStore.gatewayWS.connect()
                    threadStore.gatewayWS.refreshNow()

                    // 4. Agent roster + jewel tracking
                    roster.bindToThreadStore(threadStore)
                    roster.bindToGateway(gatewayWS)
                    roster.bindToScheduler(scheduler)

                    // 5. Native agent scheduler + task dispatcher
                    scheduler.bind(client: anthropic, roster: roster, execution: execution,
                                   geminiClient: geminiAPI, geminiOAuth: geminiOAuth,
                                   openAIClient: openAI)
                    scheduler.start()
                    dispatcher.start()

                    // 6. Execution service health
                    await execution.checkBackendHealth()

                    // 7. Bootstrap
                    await bootstrap.startIfNeeded()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 900)
    }
}
