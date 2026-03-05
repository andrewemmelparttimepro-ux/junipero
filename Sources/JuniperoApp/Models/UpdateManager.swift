import Foundation
#if os(macOS)
import AppKit
#endif

@MainActor
final class UpdateManager: ObservableObject {
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""
    @Published var releaseNotes: String = ""
    @Published var downloadURL: URL?
    @Published var checkStatusText: String = "Update check idle"

    private let latestReleaseAPI = URL(string: "https://api.github.com/repos/andrewemmelparttimepro-ux/junipero/releases/latest")!
    private var hasChecked = false

    func checkOnLaunchIfNeeded() async {
        guard !hasChecked else { return }
        hasChecked = true
        await checkForUpdates()
    }

    func checkForUpdates() async {
        checkStatusText = "Checking for updates…"
        do {
            let (data, response) = try await URLSession.shared.data(from: latestReleaseAPI)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                checkStatusText = "Update check unavailable"
                return
            }

            guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                checkStatusText = "Update check parse failed"
                return
            }

            let tag = ((payload["tag_name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = (payload["body"] as? String) ?? ""
            let assetURL = Self.findDMGURL(in: payload)
            let latest = normalizeVersion(tag)
            let current = normalizeVersion(Self.currentVersion)

            latestVersion = latest
            releaseNotes = notes
            downloadURL = assetURL

            if isVersion(latest, newerThan: current), assetURL != nil {
                updateAvailable = true
                checkStatusText = "Update available: \(latest)"
            } else {
                updateAvailable = false
                checkStatusText = "You are up to date"
            }
        } catch {
            checkStatusText = "Update check failed"
        }
    }

    func openLatestDownload() {
        guard let url = downloadURL else { return }
#if os(macOS)
        NSWorkspace.shared.open(url)
#endif
    }

    private static func findDMGURL(in payload: [String: Any]) -> URL? {
        guard let assets = payload["assets"] as? [[String: Any]] else { return nil }
        for asset in assets {
            guard let name = asset["name"] as? String else { continue }
            if name.lowercased().hasSuffix(".dmg"),
               let value = asset["browser_download_url"] as? String,
               let url = URL(string: value)
            {
                return url
            }
        }
        return nil
    }

    private static var currentVersion: String {
        if let value = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !value.isEmpty {
            return value
        }
        if let value = Bundle.main.infoDictionary?["CFBundleVersion"] as? String, !value.isEmpty {
            return value
        }
        return "0.0.0"
    }

    private func normalizeVersion(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            return String(trimmed.dropFirst())
        }
        return trimmed.isEmpty ? "0.0.0" : trimmed
    }

    private func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let l = lhs.split(separator: ".").compactMap { Int($0) }
        let r = rhs.split(separator: ".").compactMap { Int($0) }
        let maxCount = max(l.count, r.count)
        for i in 0..<maxCount {
            let lv = i < l.count ? l[i] : 0
            let rv = i < r.count ? r[i] : 0
            if lv != rv {
                return lv > rv
            }
        }
        return false
    }
}
