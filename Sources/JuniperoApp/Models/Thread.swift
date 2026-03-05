import Foundation

enum ChatRole: String, Codable {
    case user
    case assistant
}

enum ChatDeliveryState: String, Codable {
    case pending
    case success
    case failed
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole
    var text: String
    let timestamp: Date

    init(id: UUID = UUID(), role: ChatRole, text: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

struct ChatThread: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]
    var isLoading: Bool
    var state: ChatDeliveryState
    var errorMessage: String?
    var modelUsed: String?
    var latencyMs: Int?
    var unreadCount: Int

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [ChatMessage] = [],
        isLoading: Bool = false,
        state: ChatDeliveryState = .success,
        errorMessage: String? = nil,
        modelUsed: String? = nil,
        latencyMs: Int? = nil,
        unreadCount: Int = 0
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.isLoading = isLoading
        self.state = state
        self.errorMessage = errorMessage
        self.modelUsed = modelUsed
        self.latencyMs = latencyMs
        self.unreadCount = unreadCount
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case messages
        case isLoading
        case state
        case errorMessage
        case modelUsed
        case latencyMs
        case unreadCount
        // Legacy keys (single-turn schema)
        case timestamp
        case userMessage
        case assistantMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.isLoading = try container.decodeIfPresent(Bool.self, forKey: .isLoading) ?? false
        self.state = try container.decodeIfPresent(ChatDeliveryState.self, forKey: .state) ?? (isLoading ? .pending : .success)
        self.errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        self.modelUsed = try container.decodeIfPresent(String.self, forKey: .modelUsed)
        self.latencyMs = try container.decodeIfPresent(Int.self, forKey: .latencyMs)
        self.unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0

        if let decodedMessages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages), !decodedMessages.isEmpty {
            self.messages = decodedMessages
            self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? decodedMessages.first?.timestamp ?? Date()
            self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? decodedMessages.last?.timestamp ?? createdAt
            return
        }

        // Legacy migration path
        let legacyTimestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        let legacyUser = try container.decodeIfPresent(String.self, forKey: .userMessage) ?? ""
        let legacyAssistant = try container.decodeIfPresent(String.self, forKey: .assistantMessage) ?? ""
        var migrated: [ChatMessage] = []
        if !legacyUser.isEmpty {
            migrated.append(ChatMessage(role: .user, text: legacyUser, timestamp: legacyTimestamp))
        }
        if !legacyAssistant.isEmpty {
            migrated.append(ChatMessage(role: .assistant, text: legacyAssistant, timestamp: legacyTimestamp))
        }
        self.messages = migrated
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? legacyTimestamp
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? legacyTimestamp
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(messages, forKey: .messages)
        try container.encode(isLoading, forKey: .isLoading)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try container.encodeIfPresent(modelUsed, forKey: .modelUsed)
        try container.encodeIfPresent(latencyMs, forKey: .latencyMs)
        try container.encode(unreadCount, forKey: .unreadCount)
    }

    var latestUserText: String {
        messages.last(where: { $0.role == .user })?.text ?? ""
    }

    var latestAssistantText: String {
        messages.last(where: { $0.role == .assistant })?.text ?? ""
    }

    var userMessagePreview: String {
        let converted = MSNEmoji.convert(latestUserText)
        if converted.count > 60 {
            return String(converted.prefix(60)) + "…"
        }
        return converted
    }

    var assistantMessagePreview: String {
        let converted = MSNEmoji.convert(latestAssistantText)
        if converted.count > 80 {
            return String(converted.prefix(80)) + "…"
        }
        return converted
    }

    var formattedDate: String {
        Self.dateTimeFormatter.string(from: updatedAt)
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()
}

struct MSNEmoji {
    static func convert(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: ":-(", with: "😢")
        result = result.replacingOccurrences(of: ":-)", with: "😊")
        result = result.replacingOccurrences(of: ":-D", with: "😄")
        result = result.replacingOccurrences(of: ":-P", with: "😛")
        result = result.replacingOccurrences(of: ":O", with: "😮")
        result = result.replacingOccurrences(of: "(y)", with: "👍")
        result = result.replacingOccurrences(of: "(n)", with: "👎")
        result = result.replacingOccurrences(of: "(H)", with: "😎")
        result = result.replacingOccurrences(of: "(L)", with: "❤️")
        result = result.replacingOccurrences(of: "(U)", with: "💔")
        result = result.replacingOccurrences(of: "(K)", with: "💋")
        result = result.replacingOccurrences(of: "(F)", with: "🌸")
        result = result.replacingOccurrences(of: "(W)", with: "⛅")
        result = result.replacingOccurrences(of: "(S)", with: "🌙")
        result = result.replacingOccurrences(of: "(*)", with: "⭐")
        result = result.replacingOccurrences(of: "(8)", with: "🎵")
        return result
    }
}
