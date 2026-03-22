import Foundation

enum LiabilityMode: String, Codable, CaseIterable, Identifiable {
    case idiot = "im_an_idiot"
    case myFault = "its_my_fault"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .idiot:
            return "I'm an idiot"
        case .myFault:
            return "It's my fault"
        }
    }
}

struct ThrawnPreferences: Codable {
    var liabilityMode: LiabilityMode
    var probationStartedAt: Date
    var interactionCount: Int

    static let `default` = ThrawnPreferences(
        liabilityMode: .idiot,
        probationStartedAt: Date(),
        interactionCount: 0
    )

    var probationComplete: Bool {
        interactionCount >= 8 || Date().timeIntervalSince(probationStartedAt) >= 21_600
    }

    var effectiveLiabilityMode: LiabilityMode {
        probationComplete ? liabilityMode : .idiot
    }
}

enum ThrawnPreferencesStore {
    static let changedNotification = Notification.Name("ThrawnPreferencesChanged")

    private static var fileURL: URL {
        ThrawnPaths.appSupportDir.appendingPathComponent("preferences.json")
    }

    static func load() -> ThrawnPreferences {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(ThrawnPreferences.self, from: data) else {
            return .default
        }
        return decoded
    }

    static func save(_ prefs: ThrawnPreferences) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(prefs) {
            try? data.write(to: fileURL, options: .atomic)
            NotificationCenter.default.post(name: changedNotification, object: nil)
        }
    }

    static func incrementInteraction() {
        var prefs = load()
        prefs.interactionCount += 1
        save(prefs)
    }
}
