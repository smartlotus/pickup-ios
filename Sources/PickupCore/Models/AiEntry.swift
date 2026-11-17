import Foundation

public enum AiEntryType: String, Codable, Sendable, CaseIterable {
    case recall
    case summary
}

public struct AiEntry: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let question: String
    public let answer: String
    public let type: AiEntryType
    public let timestamp: Date
    public let contextStart: Date?
    public let contextEnd: Date?
    public var comments: [Comment]

    public init(
        id: String = UUID().uuidString.lowercased(),
        question: String,
        answer: String,
        type: AiEntryType,
        timestamp: Date = Date(),
        contextStart: Date? = nil,
        contextEnd: Date? = nil,
        comments: [Comment] = []
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.type = type
        self.timestamp = timestamp
        self.contextStart = contextStart
        self.contextEnd = contextEnd
        self.comments = comments
    }
}
