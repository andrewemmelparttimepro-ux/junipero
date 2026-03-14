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
    @StateObject private var gatewayClient = GatewayClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(threadStore)
                .environmentObject(bootstrap)
                .environmentObject(updateManager)
                .environmentObject(sparkleUpdater)
                .environmentObject(roster)
                .environmentObject(nav)
                .environmentObject(gatewayClient)
                .environmentObject(gatewayWS)
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
                    await bootstrap.startIfNeeded()
                    await updateManager.checkOnLaunchIfNeeded()
                    gatewayClient.refreshPlaceholderState()
                    let wsPrefs = ThrawnPreferencesStore.load()
                    _ = wsPrefs
                    let wsBaseURL = UserDefaults.standard.string(forKey: "ThrawnGatewayURL") ?? "http://127.0.0.1:18789"
                    let wsToken = UserDefaults.standard.string(forKey: "ThrawnGatewayToken")
                    gatewayWS.configure(baseURL: wsBaseURL, token: wsToken)
                    gatewayWS.connect()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 900)
    }
}
