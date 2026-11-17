import Foundation

public enum DetectedBackupFormat: String, Sendable, Equatable {
    case androidV2Zip
    case encryptedVault
    case portableJson
    case legacyJsonArray
}

public enum ImportMode: String, Sendable, Equatable {
    case merge
    case replace
}

public struct ImportPreviewReport: Sendable, Equatable {
    public let format: DetectedBackupFormat
    public let entryCount: Int
    public let aiEntryCount: Int
    public let mediaCount: Int
    public let missingMediaCount: Int
    public let conflictCount: Int
    public let hasIOSExtensions: Bool
    public let exportedAt: Date?

    public init(
        format: DetectedBackupFormat,
        entryCount: Int,
        aiEntryCount: Int,
        mediaCount: Int,
        missingMediaCount: Int,
        conflictCount: Int,
        hasIOSExtensions: Bool,
        exportedAt: Date?
    ) {
        self.format = format
        self.entryCount = entryCount
        self.aiEntryCount = aiEntryCount
        self.mediaCount = mediaCount
        self.missingMediaCount = missingMediaCount
        self.conflictCount = conflictCount
        self.hasIOSExtensions = hasIOSExtensions
        self.exportedAt = exportedAt
    }
}

public struct ImportReport: Sendable, Equatable {
    public let importedEntries: Int
    public let importedAiEntries: Int
    public let importedMedia: Int
    public let conflictsSkipped: Int
    public let unavailableMedia: Int
    public let safetySnapshotFileName: String?

    public init(
        importedEntries: Int,
        importedAiEntries: Int,
        importedMedia: Int,
        conflictsSkipped: Int,
        unavailableMedia: Int,
        safetySnapshotFileName: String? = nil
    ) {
        self.importedEntries = importedEntries
        self.importedAiEntries = importedAiEntries
        self.importedMedia = importedMedia
        self.conflictsSkipped = conflictsSkipped
        self.unavailableMedia = unavailableMedia
        self.safetySnapshotFileName = safetySnapshotFileName
    }
}

// MARK: - Strict Android V2 Schema Wire Types (additionalProperties: false)

public struct PortableCommentWire: Codable, Sendable, Equatable {
    public let text: String
    public let timestamp: String
}

public struct PortableMediaWire: Codable, Sendable, Equatable {
    public let id: String
    public let type: String
    public let path: String
    public let motionVideoPath: String?

    public init(id: String, type: String, path: String, motionVideoPath: String? = nil) {
        self.id = id
        self.type = type
        self.path = path
        self.motionVideoPath = motionVideoPath
    }
}

public struct PortableEntryWire: Codable, Sendable, Equatable {
    public let id: String
    public let content: String
    public let imagePath: String?
    public let imagePaths: [String]
    public let videoPaths: [String]
    public let media: [PortableMediaWire]
    public let songInfo: String?
    public let timestamp: String
    public let comments: [PortableCommentWire]

    /// Explicitly emit all required schema keys including `"imagePath": null` and `"songInfo": null`
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(content, forKey: .content)
        try c.encode(imagePath, forKey: .imagePath)
        try c.encode(imagePaths, forKey: .imagePaths)
        try c.encode(videoPaths, forKey: .videoPaths)
        try c.encode(media, forKey: .media)
        try c.encode(songInfo, forKey: .songInfo)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(comments, forKey: .comments)
    }

    enum CodingKeys: String, CodingKey {
        case id, content, imagePath, imagePaths, videoPaths, media, songInfo, timestamp, comments
    }
}

public struct PortableAiEntryWire: Codable, Sendable, Equatable {
    public let id: String
    public let question: String
    public let answer: String
    public let type: String
    public let timestamp: String
    public let comments: [PortableCommentWire]
}

public struct PortableBackupWire: Codable, Sendable, Equatable {
    public let format: String
    public let formatVersion: Int
    public let exportedAt: String
    public let entries: [PortableEntryWire]
    public let aiEntries: [PortableAiEntryWire]
}

public struct IOSEntryExtensionRecord: Codable, Sendable, Equatable {
    public let mood: String?
    public let weather: String?
    public let tags: [String]
    public let isPinned: Bool
    public let sketchAttachmentIds: [String]
    public let updatedAt: String?

    public init(
        mood: String?,
        weather: String?,
        tags: [String],
        isPinned: Bool,
        sketchAttachmentIds: [String],
        updatedAt: String?
    ) {
        self.mood = mood
        self.weather = weather
        self.tags = tags
        self.isPinned = isPinned
        self.sketchAttachmentIds = sketchAttachmentIds
        self.updatedAt = updatedAt
    }
}

public struct IOSAiContextWindowRecord: Codable, Sendable, Equatable {
    public let contextStart: String?
    public let contextEnd: String?
}

public struct IOSExtensionsPayload: Codable, Sendable, Equatable {
    public let format: String
    public let version: Int
    public let entryExtensions: [String: IOSEntryExtensionRecord]
    public let aiContextWindows: [String: IOSAiContextWindowRecord]
    public let themeStyle: PickupThemeStyle?
    public let language: PickupLanguage?
    public let typographyStyle: PickupTypographyStyle?

    public init(
        format: String = "pickup-ios-extensions",
        version: Int = 1,
        entryExtensions: [String: IOSEntryExtensionRecord],
        aiContextWindows: [String: IOSAiContextWindowRecord],
        themeStyle: PickupThemeStyle?,
        language: PickupLanguage?,
        typographyStyle: PickupTypographyStyle?
    ) {
        self.format = format
        self.version = version
        self.entryExtensions = entryExtensions
        self.aiContextWindows = aiContextWindows
        self.themeStyle = themeStyle
        self.language = language
        self.typographyStyle = typographyStyle
    }
}

public enum PortableDateCodec {
    public static func format(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }

    public static func parse(_ string: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: string) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: string) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            df.dateFormat = fmt
            if let d = df.date(from: string) { return d }
        }
        return nil
    }
}
