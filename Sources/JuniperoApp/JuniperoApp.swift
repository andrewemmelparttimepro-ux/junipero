import SwiftUI

@main
struct JuniperoApp: App {
    @StateObject private var threadStore = ThreadStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(threadStore)
                .frame(minWidth: 1200, minHeight: 800)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 900)
    }
}
