import SwiftUI

@main
struct JuniperoApp: App {
    @StateObject private var threadStore = ThreadStore()
    @StateObject private var bootstrap = JuniperoBootstrap()
    @StateObject private var updateManager = UpdateManager()
    @StateObject private var sparkleUpdater = SparkleUpdaterService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(threadStore)
                .environmentObject(bootstrap)
                .environmentObject(updateManager)
                .environmentObject(sparkleUpdater)
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
                    Text("Junipero \(updateManager.latestVersion) is available. Download the latest build for best stability.")
                }
                .task {
                    await bootstrap.startIfNeeded()
                    await updateManager.checkOnLaunchIfNeeded()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 900)
    }
}
