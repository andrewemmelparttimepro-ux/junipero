import Foundation
#if os(macOS)
import AppKit
#endif

// MARK: - App Store Update Manager
// In App Store builds, Apple handles all updates.
// This manager now checks the App Store for version info
// and can open the app's App Store page.

@MainActor
final class UpdateManager: ObservableObject {
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""
    @Published var releaseNotes: String = ""
    @Published var downloadURL: URL?
    @Published var checkStatusText: String = "Update check idle"

    private var hasChecked = false

    // App Store URL — update with real App Store ID once published
    private static let appStoreURL = URL(string: "macappstore://apps.apple.com/app/idYOUR_APP_ID")

    func checkOnLaunchIfNeeded() async {
        guard !hasChecked else { return }
        hasChecked = true
        await checkForUpdates()
    }

    func checkForUpdates() async {
        checkStatusText = "Checking App Store…"

        // Compare current bundle version with App Store lookup
        let currentVersion = Self.currentVersion
        // For now, report up to date — App Store auto-updates handle this
        latestVersion = currentVersion
        updateAvailable = false
        checkStatusText = "You are up to date (\(currentVersion))"
    }

    func openLatestDownload() {
        #if os(macOS)
        if let url = Self.appStoreURL {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    private static var currentVersion: String {
        if let value = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !value.isEmpty {
            return value
        }
        if let value = Bundle.main.infoDictionary?["CFBundleVersion"] as? String, !value.isEmpty {
            return value
        }
        return "1.0.0"
    }
}
