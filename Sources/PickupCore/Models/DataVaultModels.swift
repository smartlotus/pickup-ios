import Foundation

public enum PickupThemeStyle: String, Codable, Sendable, CaseIterable {
    case purpleDark
    case monochrome
}

public enum PickupLanguage: String, Codable, Sendable, CaseIterable {
    case zh
    case en
}

public enum PickupTypographyStyle: String, Codable, Sendable, CaseIterable {
    case editorialSerif
    case cleanSans
}

public enum BackupFrequency: String, Codable, Sendable, CaseIterable {
    case manualOnly
    case every6Hours
    case daily
    case weekly
    case onEntryChange
    case onAppBackground

    public var timeInterval: TimeInterval? {
        switch self {
        case .every6Hours:
            return 6 * 3600
        case .daily:
            return 24 * 3600
        case .weekly:
            return 7 * 24 * 3600
        case .manualOnly, .onEntryChange, .onAppBackground:
            return nil
        }
    }
}

public enum BackupFormatKind: String, Codable, Sendable, CaseIterable {
    case portableZip
    case encryptedVault
    case markdownAnthology
}

public enum BackupTriggerKind: String, Codable, Sendable {
    case manual
    case scheduled
    case entryChange
    case background
    case preRestoreSafety
}

public struct AutoBackupSettings: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var frequency: BackupFrequency
    public var preferredHour: Int
    public var preferredMinute: Int
    public var retentionCount: Int // 0 means keep all
    public var includeMedia: Bool
    public var format: BackupFormatKind
    public var externalFolderDisplayName: String?
    public var externalBookmarkBase64: String?
    public var lastSuccessAt: Date?
    public var lastAttemptAt: Date?
    public var lastStatusMessage: String?
    public var lastErrorMessage: String?
    public var consecutiveFailures: Int

    public init(
        isEnabled: Bool = true,
        frequency: BackupFrequency = .daily,
        preferredHour: Int = 22,
        preferredMinute: Int = 30,
        retentionCount: Int = 7,
        includeMedia: Bool = true,
        format: BackupFormatKind = .portableZip,
        externalFolderDisplayName: String? = nil,
        externalBookmarkBase64: String? = nil,
        lastSuccessAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        lastStatusMessage: String? = nil,
        lastErrorMessage: String? = nil,
        consecutiveFailures: Int = 0
    ) {
        self.isEnabled = isEnabled
        self.frequency = frequency
        self.preferredHour = preferredHour
        self.preferredMinute = preferredMinute
        self.retentionCount = retentionCount
        self.includeMedia = includeMedia
        self.format = format
        self.externalFolderDisplayName = externalFolderDisplayName
        self.externalBookmarkBase64 = externalBookmarkBase64
        self.lastSuccessAt = lastSuccessAt
        self.lastAttemptAt = lastAttemptAt
        self.lastStatusMessage = lastStatusMessage
        self.lastErrorMessage = lastErrorMessage
        self.consecutiveFailures = consecutiveFailures
    }
}

public struct BackupRunLogEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let trigger: BackupTriggerKind
    public let format: BackupFormatKind
    public let fileName: String
    public let byteSize: Int64
    public let sha256: String
    public let succeeded: Bool
    public let writtenToExternal: Bool
    public let message: String

    public init(
        id: String = UUID().uuidString.lowercased(),
        timestamp: Date = Date(),
        trigger: BackupTriggerKind,
        format: BackupFormatKind,
        fileName: String,
        byteSize: Int64,
        sha256: String,
        succeeded: Bool,
        writtenToExternal: Bool,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.trigger = trigger
        self.format = format
        self.fileName = fileName
        self.byteSize = byteSize
        self.sha256 = sha256
        self.succeeded = succeeded
        self.writtenToExternal = writtenToExternal
        self.message = message
    }
}

public struct BackupSnapshotMetadata: Codable, Sendable, Equatable {
    public let id: String
    public let fileName: String
    public let createdAt: Date
    public let byteSize: Int64
    public let format: BackupFormatKind
    public let trigger: BackupTriggerKind
    public let sha256: String
    public let entryCount: Int
    public let aiCount: Int
    public let mediaCount: Int
    public var isPinned: Bool
    public let copiedToExternal: Bool

    public init(
        id: String = UUID().uuidString.lowercased(),
        fileName: String,
        createdAt: Date = Date(),
        byteSize: Int64,
        format: BackupFormatKind,
        trigger: BackupTriggerKind,
        sha256: String,
        entryCount: Int,
        aiCount: Int,
        mediaCount: Int,
        isPinned: Bool = false,
        copiedToExternal: Bool = false
    ) {
        self.id = id
        self.fileName = fileName
        self.createdAt = createdAt
        self.byteSize = byteSize
        self.format = format
        self.trigger = trigger
        self.sha256 = sha256
        self.entryCount = entryCount
        self.aiCount = aiCount
        self.mediaCount = mediaCount
        self.isPinned = isPinned
        self.copiedToExternal = copiedToExternal
    }
}

public struct BackupSnapshotInfo: Sendable, Equatable, Identifiable {
    public let metadata: BackupSnapshotMetadata
    public let fileURL: URL
    public let fileExists: Bool

    public var id: String { metadata.id }

    public init(metadata: BackupSnapshotMetadata, fileURL: URL, fileExists: Bool) {
        self.metadata = metadata
        self.fileURL = fileURL
        self.fileExists = fileExists
    }
}

public struct AppPreferences: Codable, Sendable, Equatable {
    public var themeStyle: PickupThemeStyle
    public var language: PickupLanguage
    public var typographyStyle: PickupTypographyStyle
    public var tutorialCompleted: Bool
    public var skipLaunchIntro: Bool
    public var biometricLockEnabled: Bool
    public var passphraseLockSaltBase64: String?
    public var passphraseLockHashBase64: String?
    public var lastRevisitDateKey: String?
    public var autoBackup: AutoBackupSettings

    public var isPassphraseLockEnabled: Bool {
        passphraseLockSaltBase64 != nil && passphraseLockHashBase64 != nil
    }

    public init(
        themeStyle: PickupThemeStyle = .purpleDark,
        language: PickupLanguage = .zh,
        typographyStyle: PickupTypographyStyle = .editorialSerif,
        tutorialCompleted: Bool = false,
        skipLaunchIntro: Bool = false,
        biometricLockEnabled: Bool = false,
        passphraseLockSaltBase64: String? = nil,
        passphraseLockHashBase64: String? = nil,
        lastRevisitDateKey: String? = nil,
        autoBackup: AutoBackupSettings = AutoBackupSettings()
    ) {
        self.themeStyle = themeStyle
        self.language = language
        self.typographyStyle = typographyStyle
        self.tutorialCompleted = tutorialCompleted
        self.skipLaunchIntro = skipLaunchIntro
        self.biometricLockEnabled = biometricLockEnabled
        self.passphraseLockSaltBase64 = passphraseLockSaltBase64
        self.passphraseLockHashBase64 = passphraseLockHashBase64
        self.lastRevisitDateKey = lastRevisitDateKey
        self.autoBackup = autoBackup
    }
}

public struct StorageBreakdown: Sendable, Equatable {
    public let entriesBytes: Int64
    public let aiBytes: Int64
    public let imagesBytes: Int64
    public let videosBytes: Int64
    public let draftsBytes: Int64
    public let backupsBytes: Int64
    public let orphanMediaBytes: Int64
    public let deviceFreeBytes: Int64?
    public let entryCount: Int
    public let aiCount: Int
    public let mediaFileCount: Int
    public let backupCount: Int

    public var totalUsedBytes: Int64 {
        entriesBytes + aiBytes + imagesBytes + videosBytes + draftsBytes + backupsBytes
    }

    public init(
        entriesBytes: Int64,
        aiBytes: Int64,
        imagesBytes: Int64,
        videosBytes: Int64,
        draftsBytes: Int64,
        backupsBytes: Int64,
        orphanMediaBytes: Int64,
        deviceFreeBytes: Int64?,
        entryCount: Int,
        aiCount: Int,
        mediaFileCount: Int,
        backupCount: Int
    ) {
        self.entriesBytes = entriesBytes
        self.aiBytes = aiBytes
        self.imagesBytes = imagesBytes
        self.videosBytes = videosBytes
        self.draftsBytes = draftsBytes
        self.backupsBytes = backupsBytes
        self.orphanMediaBytes = orphanMediaBytes
        self.deviceFreeBytes = deviceFreeBytes
        self.entryCount = entryCount
        self.aiCount = aiCount
        self.mediaFileCount = mediaFileCount
        self.backupCount = backupCount
    }
}

public struct HeavyMediaItem: Sendable, Equatable, Identifiable {
    public let id: String // mediaId
    public let byteSize: Int64
    public let isVideo: Bool
    public let entryId: String?
    public let entryPreview: String
    public let timestamp: Date?

    public init(
        id: String,
        byteSize: Int64,
        isVideo: Bool,
        entryId: String?,
        entryPreview: String,
        timestamp: Date?
    ) {
        self.id = id
        self.byteSize = byteSize
        self.isVideo = isVideo
        self.entryId = entryId
        self.entryPreview = entryPreview
        self.timestamp = timestamp
    }
}

public struct OrphanScanResult: Sendable, Equatable {
    public let orphanMediaIds: [String]
    public let orphanByteSize: Int64
    public let missingMediaRefs: [(entryId: String, mediaId: String)]
    public let heavyMediaItems: [HeavyMediaItem]

    public static func == (lhs: OrphanScanResult, rhs: OrphanScanResult) -> Bool {
        lhs.orphanMediaIds == rhs.orphanMediaIds &&
        lhs.orphanByteSize == rhs.orphanByteSize &&
        lhs.heavyMediaItems == rhs.heavyMediaItems &&
        lhs.missingMediaRefs.map { "\($0.entryId):\($0.mediaId)" } == rhs.missingMediaRefs.map { "\($0.entryId):\($0.mediaId)" }
    }

    public init(
        orphanMediaIds: [String],
        orphanByteSize: Int64,
        missingMediaRefs: [(entryId: String, mediaId: String)],
        heavyMediaItems: [HeavyMediaItem]
    ) {
        self.orphanMediaIds = orphanMediaIds
        self.orphanByteSize = orphanByteSize
        self.missingMediaRefs = missingMediaRefs
        self.heavyMediaItems = heavyMediaItems
    }
}
