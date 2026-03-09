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

struct ChatAttachment: Identifiable, Codable, Hashable {
    let id: UUID
    let fileName: String
    let filePath: String
    let fileSizeBytes: Int64
    let previewText: String?

    init(
        id: UUID = UUID(),
        fileName: String,
        filePath: String,
        fileSizeBytes: Int64,
        previewText: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.fileSizeBytes = fileSizeBytes
        self.previewText = previewText
    }

    var promptSegment: String {
        var lines: [String] = []
        lines.append("[Attachment]")
        lines.append("Name: \(fileName)")
        lines.append("Path: \(filePath)")
        lines.append("Size: \(fileSizeBytes) bytes")
        if let previewText, !previewText.isEmpty {
            lines.append("Preview:")
            lines.append(previewText)
        }
        return lines.joined(separator: "\n")
    }
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole
    var text: String
    var attachments: [ChatAttachment]
    let timestamp: Date

    init(id: UUID = UUID(), role: ChatRole, text: String, attachments: [ChatAttachment] = [], timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.attachments = attachments
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case attachments
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.role = try container.decode(ChatRole.self, forKey: .role)
        self.text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.attachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
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

    var displayErrorMessage: String? {
        errorMessage.map(Self.presentableErrorMessage)
    }

    var formattedDate: String {
        Self.dateTimeFormatter.string(from: updatedAt)
    }

    static func presentableErrorMessage(_ raw: String) -> String {
        let lower = raw.lowercased()

        if lower.contains("overloaded") || lower.contains("rate limit") || lower.contains("cooldown") {
            return "Provider is overloaded right now. Retry in a moment or use local fallback."
        }

        if lower.contains("image exceeds 5 mb") || lower.contains("exceeds 5 mb maximum") {
            return "Attachment is too large (max 5 MB). Resize or compress, then try again."
        }

        if lower.contains("timed out")
            || lower.contains("request timed out")
            || lower.contains("nsurlerrordomain code=-1001")
        {
            return "The reply took too long and timed out. Retry, or pick a faster model in Setup."
        }

        if lower.contains("unauthorized") || lower.contains("authentication token") || lower.contains("openclaw rejected authentication") {
            return "Authentication failed. Open Setup and verify your provider token."
        }

        if lower.contains("could not connect to the server")
            || lower.contains("cannot connect to host")
            || lower.contains("not connected to internet")
            || lower.contains("nsurlerrordomain code=-1004")
            || lower.contains("kcferror")
        {
            return "Cannot reach OpenClaw right now. Use Heal or check that OpenClaw is running."
        }

        if lower.contains("primary and fallback both failed") {
            let fallbackMissingModel = lower.contains("model")
                && lower.contains("not found")
                && (lower.contains("kimi") || lower.contains("ollama"))
            if fallbackMissingModel {
                return "Primary is offline and local fallback model is missing. Open Setup and tap Fix Missing Model."
            }
            return "Primary and fallback both failed. Open Setup, run diagnostics, then retry."
        }

        if lower.contains("openclaw error 404") && lower.contains("model") && lower.contains("not found") {
            return "Configured model was not found. Open Setup and select/install an available model."
        }

        if raw.count > 220 {
            return "Request failed. Open Setup > Run Diagnostics for full details."
        }

        return raw
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
