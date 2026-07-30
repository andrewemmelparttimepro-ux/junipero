import Foundation

// MARK: - Access Mode
//
// Older preference files may still contain retired access-mode names. Decode
// them into the only active runtime: full operation.

enum AccessMode: String, Codable, CaseIterable, Identifiable {
    case fullOperation = "full_operation"

    var id: String { rawValue }

    var label: String {
        "Full Operation"
    }

    var icon: String {
        "bolt.shield.fill"
    }

    var isFullOperation: Bool { true }

    init(from decoder: Decoder) throws {
        self = .fullOperation
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Liability Mode

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
    var operationStartedAt: Date
    var interactionCount: Int
    var accessMode: AccessMode
    var lastFullOperationAt: Date?
    var fullOperationSessionCount: Int

    static let `default` = ThrawnPreferences(
        liabilityMode: .myFault,
        operationStartedAt: Date(),
        interactionCount: 0,
        accessMode: .fullOperation,
        lastFullOperationAt: Date(),
        fullOperationSessionCount: 1
    )

    var effectiveLiabilityMode: LiabilityMode {
        .myFault
    }

    private enum CodingKeys: String, CodingKey {
        case liabilityMode
        case operationStartedAt
        case interactionCount
        case accessMode
        case lastFullOperationAt
        case fullOperationSessionCount
    }

    init(
        liabilityMode: LiabilityMode,
        operationStartedAt: Date,
        interactionCount: Int,
        accessMode: AccessMode,
        lastFullOperationAt: Date?,
        fullOperationSessionCount: Int
    ) {
        self.liabilityMode = liabilityMode
        self.operationStartedAt = operationStartedAt
        self.interactionCount = interactionCount
        self.accessMode = accessMode
        self.lastFullOperationAt = lastFullOperationAt
        self.fullOperationSessionCount = fullOperationSessionCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        liabilityMode = try container.decodeIfPresent(LiabilityMode.self, forKey: .liabilityMode) ?? .myFault
        operationStartedAt = try container.decodeIfPresent(Date.self, forKey: .operationStartedAt) ?? Date()
        interactionCount = try container.decodeIfPresent(Int.self, forKey: .interactionCount) ?? 0
        accessMode = try container.decodeIfPresent(AccessMode.self, forKey: .accessMode) ?? .fullOperation
        lastFullOperationAt = try container.decodeIfPresent(Date.self, forKey: .lastFullOperationAt)
        fullOperationSessionCount = try container.decodeIfPresent(Int.self, forKey: .fullOperationSessionCount) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(liabilityMode, forKey: .liabilityMode)
        try container.encode(operationStartedAt, forKey: .operationStartedAt)
        try container.encode(interactionCount, forKey: .interactionCount)
        try container.encode(AccessMode.fullOperation, forKey: .accessMode)
        try container.encodeIfPresent(lastFullOperationAt, forKey: .lastFullOperationAt)
        try container.encode(fullOperationSessionCount, forKey: .fullOperationSessionCount)
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
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            FlightRecorder.logError(
                source: "preferences:save",
                message: "createDirectory failed: \(error.localizedDescription)"
            )
            return
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(prefs)
        } catch {
            FlightRecorder.logError(
                source: "preferences:save",
                message: "Encode failed: \(error.localizedDescription)"
            )
            return
        }
        do {
            try data.write(to: fileURL, options: .atomic)
            NotificationCenter.default.post(name: changedNotification, object: nil)
        } catch {
            FlightRecorder.logError(
                source: "preferences:save",
                message: "Write \(fileURL.lastPathComponent) failed: \(error.localizedDescription)"
            )
        }
    }

    static func incrementInteraction() {
        var prefs = load()
        prefs.interactionCount += 1
        save(prefs)
    }

    static func setAccessMode(_ mode: AccessMode) {
        var prefs = load()
        prefs.liabilityMode = .myFault
        prefs.accessMode = .fullOperation
        prefs.lastFullOperationAt = Date()
        prefs.fullOperationSessionCount += 1
        save(prefs)
    }

    static var currentAccessMode: AccessMode {
        .fullOperation
    }
}
