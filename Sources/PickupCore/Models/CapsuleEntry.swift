import Foundation

public struct CapsuleEntry: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public var content: String
    public var timestamp: Date
    public var songInfo: String?
    public var media: [MediaAttachment]
    public var comments: [Comment]

    // iOS extended metadata (stored locally + in ios-extensions.json inside backups)
    public var mood: String?
    public var weather: String?
    public var tags: [String]
    public var isPinned: Bool
    public var updatedAt: Date?

    public var imagePaths: [String] {
        media.filter { $0.isImage }.map { $0.sourcePath }
    }

    public var videoPaths: [String] {
        media.filter { $0.isVideo }.compactMap { $0.videoSourcePath }
    }

    public init(
        id: String = UUID().uuidString.lowercased(),
        content: String,
        timestamp: Date = Date(),
        songInfo: String? = nil,
        media: [MediaAttachment] = [],
        comments: [Comment] = [],
        mood: String? = nil,
        weather: String? = nil,
        tags: [String] = [],
        isPinned: Bool = false,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.songInfo = songInfo
        self.media = media
        self.comments = comments
        self.mood = mood
        self.weather = weather
        self.tags = tags
        self.isPinned = isPinned
        self.updatedAt = updatedAt
    }

    public var hasExtendedMetadata: Bool {
        mood != nil || weather != nil || !tags.isEmpty || isPinned || media.contains { $0.type == .sketch }
    }
}
