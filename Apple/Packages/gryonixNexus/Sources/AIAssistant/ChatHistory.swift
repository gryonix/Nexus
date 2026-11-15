import Foundation

public struct AIChatMessage: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var role: AIRole
    public var text: String
    public var createdAt: Double
    public var inputTokens: Int?
    public var outputTokens: Int?
    /// Stored picture files sent with this message
    public var imageIDs: [String]?

    public init(role: AIRole, text: String, at date: Date = Date(),
                inputTokens: Int? = nil, outputTokens: Int? = nil, imageIDs: [String]? = nil) {
        id = UUID().uuidString
        self.role = role
        self.text = text
        self.imageIDs = imageIDs
        createdAt = date.timeIntervalSince1970
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public struct AIChat: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var updatedAt: Double
    public var messages: [AIChatMessage]

    public init(title: String, messages: [AIChatMessage] = [], at date: Date = Date()) {
        id = UUID().uuidString
        self.title = title
        self.messages = messages
        updatedAt = date.timeIntervalSince1970
    }
}

public enum AIDateGroup: String, Sendable, CaseIterable {
    case today, yesterday, lastWeek, earlier
}

/// All chats of this device, newest first.
public struct AIChatHistory: Codable, Equatable, Sendable {
    public var chats: [AIChat] = []

    public init() {}

    public mutating func upsert(_ chat: AIChat) {
        chats.removeAll { $0.id == chat.id }
        chats.insert(chat, at: 0)
        chats.sort { $0.updatedAt > $1.updatedAt }
    }

    public mutating func delete(id: String) { chats.removeAll { $0.id == id } }

    public func groups(now: Date, calendar: Calendar = .current) -> [(AIDateGroup, [AIChat])] {
        let today = calendar.startOfDay(for: now)
        func group(_ chat: AIChat) -> AIDateGroup {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: chat.updatedAt))
            let age = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            if age <= 0 { return .today }
            if age == 1 { return .yesterday }
            return age < 7 ? .lastWeek : .earlier
        }
        return AIDateGroup.allCases.compactMap { name in
            let inGroup = chats.filter { group($0) == name }
            return inGroup.isEmpty ? nil : (name, inGroup)
        }
    }
}

/// A JSON file holding the history; never synced.
public struct AIChatFileStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() -> AIChatHistory {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(AIChatHistory.self, from: $0) }
            ?? AIChatHistory()
    }

    public func save(_ history: AIChatHistory) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        var location = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? location.setResourceValues(values)
    }
}
