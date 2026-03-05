import SwiftUI

@main
struct JuniperoApp: App {
    @StateObject private var threadStore = ThreadStore()
    @StateObject private var bootstrap = JuniperoBootstrap()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(threadStore)
                .environmentObject(bootstrap)
                .frame(minWidth: 1200, minHeight: 800)
                .sheet(isPresented: $bootstrap.showSetup) {
                    SetupWizardView()
                        .environmentObject(bootstrap)
                }
                .task {
                    await bootstrap.startIfNeeded()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 900)
    }
}
