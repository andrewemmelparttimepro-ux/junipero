import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class SparkleUpdaterService: ObservableObject {
    @Published var isAvailable: Bool = false

#if canImport(Sparkle)
    private let updaterController: SPUStandardUpdaterController?
#endif

    init() {
#if canImport(Sparkle)
        // Starts Sparkle's updater lifecycle for automatic checks if feed is configured.
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.isAvailable = true
#else
        self.isAvailable = false
#endif
    }

    func checkForUpdates() {
#if canImport(Sparkle)
        updaterController?.checkForUpdates(nil)
#endif
    }
}
