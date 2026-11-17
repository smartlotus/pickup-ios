import Foundation

public struct Comment: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let text: String
    public let timestamp: Date

    public var id: String {
        "\(timestamp.timeIntervalSince1970)-\(text.hashValue)"
    }

    public init(text: String, timestamp: Date = Date()) {
        self.text = text
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case text
        case timestamp
    }
}
