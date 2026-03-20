import SwiftUI

@main
struct ThrawnApp: App {
    @StateObject private var threadStore = ThreadStore()
    @StateObject private var bootstrap = ThrawnBootstrap()
    @StateObject private var updateManager = UpdateManager()
    @StateObject private var sparkleUpdater = SparkleUpdaterService()
    @StateObject private var roster = AgentRosterStore()
    @StateObject private var gatewayWS = GatewayWSClient()
    @StateObject private var nav = ConsoleNavigationStore()
    @StateObject private var flowTab = FlowTabStore()
    @StateObject private var screenCapture = ScreenCaptureStore()

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
                .environmentObject(screenCapture)
                .frame(minWidth: 1200, minHeight: 800)
                .sheet(isPresented: $bootstrap.showSetup) {
                    SetupWizardView()
                        .environmentObject(bootstrap)
                }
                .alert("Update Available", isPresented: $updateManager.updateAvailable) {
                    Button("Update Now") {
                        updateManager.openLatestDownload()
                    }
                    Button("Later", role: .cancel) {}
                } message: {
                    Text("Thrawn \(updateManager.latestVersion) is available. Download the latest build for best stability.")
                }
                .task {
                    gatewayWS.connectAndPrewarm()
                    threadStore.gatewayWS.connect()
                    threadStore.gatewayWS.refreshNow()
                    roster.bindToThreadStore(threadStore)
                    roster.bindToGateway(gatewayWS)
                    async let bootstrapTask: Void = bootstrap.startIfNeeded()
                    async let updateTask: Void = updateManager.checkOnLaunchIfNeeded()
                    _ = await (bootstrapTask, updateTask)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 900)
    }
}
