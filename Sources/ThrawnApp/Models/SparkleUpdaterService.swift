import Foundation

// MARK: - App Store Update Stub
// Sparkle has been removed for App Store compliance.
// Apple handles all updates via the Mac App Store.
// This stub preserves the type so existing @EnvironmentObject
// references compile without changes.

@MainActor
final class SparkleUpdaterService: ObservableObject {
    @Published var isAvailable: Bool = false

    func checkForUpdates() {
        // No-op — App Store handles updates automatically.
    }
}
