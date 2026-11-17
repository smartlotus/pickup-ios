import Foundation

public struct EditorDraft: Codable, Sendable, Equatable {
    public var content: String
    public var songInfo: String
    public var mood: String?
    public var weather: String?
    public var tags: [String]
    public var media: [MediaAttachment]
    public var updatedAt: Date

    public init(
        content: String = "",
        songInfo: String = "",
        mood: String? = nil,
        weather: String? = nil,
        tags: [String] = [],
        media: [MediaAttachment] = [],
        updatedAt: Date = Date()
    ) {
        self.content = content
        self.songInfo = songInfo
        self.mood = mood
        self.weather = weather
        self.tags = tags
        self.media = media
        self.updatedAt = updatedAt
    }

    public var isEffectivelyEmpty: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && songInfo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && mood == nil
            && weather == nil
            && tags.isEmpty
            && media.isEmpty
    }
}

public actor PickupRepository {
    public let rootURL: URL
    public let mediaDirectoryURL: URL
    public let backupsDirectoryURL: URL

    private let entriesFileURL: URL
    private let aiEntriesFileURL: URL
    private let preferencesFileURL: URL
    private let draftFileURL: URL
    private let backupSnapshotsFileURL: URL
    private let backupLogFileURL: URL
    private let aiSettingsFileURL: URL

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootURL: URL? = nil) throws {
        let resolvedRoot: URL
        if let rootURL {
            resolvedRoot = rootURL
        } else {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            resolvedRoot = appSupport.appendingPathComponent("PickupVault", isDirectory: true)
        }
        self.rootURL = resolvedRoot
        self.mediaDirectoryURL = resolvedRoot.appendingPathComponent("Media", isDirectory: true)
        self.backupsDirectoryURL = resolvedRoot.appendingPathComponent("Backups", isDirectory: true)
        self.entriesFileURL = resolvedRoot.appendingPathComponent("entries.json")
        self.aiEntriesFileURL = resolvedRoot.appendingPathComponent("ai_entries.json")
        self.preferencesFileURL = resolvedRoot.appendingPathComponent("preferences.json")
        self.draftFileURL = resolvedRoot.appendingPathComponent("draft.json")
        self.backupSnapshotsFileURL = resolvedRoot.appendingPathComponent("backup_snapshots.json")
        self.backupLogFileURL = resolvedRoot.appendingPathComponent("backup_run_log.json")
        self.aiSettingsFileURL = resolvedRoot.appendingPathComponent("ai_settings.json")

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        try Self.createDirectories(at: [resolvedRoot, mediaDirectoryURL, backupsDirectoryURL])
    }

    private nonisolated static func createDirectories(at urls: [URL]) throws {
        let fm = FileManager.default
        for url in urls {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func ensureDirectories() throws {
        try Self.createDirectories(at: [rootURL, mediaDirectoryURL, backupsDirectoryURL])
    }

    // MARK: - Entries

    public func listEntries() throws -> [CapsuleEntry] {
        guard fileManager.fileExists(atPath: entriesFileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: entriesFileURL)
        return try decoder.decode([CapsuleEntry].self, from: data)
            .sorted { $0.timestamp > $1.timestamp }
    }

    public func saveEntries(_ entries: [CapsuleEntry]) throws {
        try ensureDirectories()
        let sorted = entries.sorted { $0.timestamp > $1.timestamp }
        let data = try encoder.encode(sorted)
        try data.write(to: entriesFileURL, options: .atomic)
    }

    public func upsertEntry(_ entry: CapsuleEntry) throws -> [CapsuleEntry] {
        var entries = try listEntries()
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        } else {
            entries.append(entry)
        }
        try saveEntries(entries)
        return entries.sorted { $0.timestamp > $1.timestamp }
    }

    public func deleteEntry(id: String) throws -> [CapsuleEntry] {
        var entries = try listEntries()
        entries.removeAll { $0.id == id }
        try saveEntries(entries)
        return entries
    }

    // MARK: - AI Entries

    public func listAiEntries() throws -> [AiEntry] {
        guard fileManager.fileExists(atPath: aiEntriesFileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: aiEntriesFileURL)
        return try decoder.decode([AiEntry].self, from: data)
            .sorted { $0.timestamp > $1.timestamp }
    }

    public func saveAiEntries(_ entries: [AiEntry]) throws {
        try ensureDirectories()
        let sorted = entries.sorted { $0.timestamp > $1.timestamp }
        let data = try encoder.encode(sorted)
        try data.write(to: aiEntriesFileURL, options: .atomic)
    }

    public func upsertAiEntry(_ entry: AiEntry) throws -> [AiEntry] {
        var entries = try listAiEntries()
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        } else {
            entries.append(entry)
        }
        try saveAiEntries(entries)
        return entries.sorted { $0.timestamp > $1.timestamp }
    }

    public func deleteAiEntry(id: String) throws -> [AiEntry] {
        var entries = try listAiEntries()
        entries.removeAll { $0.id == id }
        try saveAiEntries(entries)
        return entries
    }

    // MARK: - Preferences & Drafts & AI Settings

    public func loadPreferences() throws -> AppPreferences {
        guard fileManager.fileExists(atPath: preferencesFileURL.path) else {
            return AppPreferences()
        }
        let data = try Data(contentsOf: preferencesFileURL)
        return try decoder.decode(AppPreferences.self, from: data)
    }

    public func savePreferences(_ preferences: AppPreferences) throws {
        try ensureDirectories()
        let data = try encoder.encode(preferences)
        try data.write(to: preferencesFileURL, options: .atomic)
    }

    public func loadDraft() throws -> EditorDraft? {
        guard fileManager.fileExists(atPath: draftFileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: draftFileURL)
        return try decoder.decode(EditorDraft.self, from: data)
    }

    public func saveDraft(_ draft: EditorDraft) throws {
        try ensureDirectories()
        let data = try encoder.encode(draft)
        try data.write(to: draftFileURL, options: .atomic)
    }

    public func clearDraft() throws {
        if fileManager.fileExists(atPath: draftFileURL.path) {
            try fileManager.removeItem(at: draftFileURL)
        }
    }

    public func loadAiSettingsData() throws -> Data? {
        guard fileManager.fileExists(atPath: aiSettingsFileURL.path) else {
            return nil
        }
        return try Data(contentsOf: aiSettingsFileURL)
    }

    public func saveAiSettingsData(_ data: Data) throws {
        try ensureDirectories()
        try data.write(to: aiSettingsFileURL, options: .atomic)
    }

    // MARK: - Media Storage

    public func mediaFileURL(for mediaId: String) -> URL {
        let sanitized = sanitizeFileComponent(mediaId)
        return mediaDirectoryURL.appendingPathComponent(sanitized)
    }

    public func saveMedia(data: Data, mediaId: String) throws -> URL {
        try ensureDirectories()
        let url = mediaFileURL(for: mediaId)
        try data.write(to: url, options: .atomic)
        return url
    }

    public func loadMedia(mediaId: String) throws -> Data? {
        let url = mediaFileURL(for: mediaId)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    public func mediaExists(mediaId: String) -> Bool {
        fileManager.fileExists(atPath: mediaFileURL(for: mediaId).path)
    }

    public func deleteMedia(mediaId: String) throws {
        let url = mediaFileURL(for: mediaId)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    public func listAllMediaFiles() throws -> [(mediaId: String, byteSize: Int64)] {
        try ensureDirectories()
        let urls = try fileManager.contentsOfDirectory(
            at: mediaDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var results: [(String, Int64)] = []
        for url in urls {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values.isRegularFile == true {
                results.append((url.lastPathComponent, Int64(values.fileSize ?? 0)))
            }
        }
        return results
    }

    // MARK: - Backups & Run Logs

    public func backupFileURL(fileName: String) -> URL {
        backupsDirectoryURL.appendingPathComponent(sanitizeFileComponent(fileName))
    }

    public func saveBackupFile(data: Data, fileName: String) throws -> URL {
        try ensureDirectories()
        let url = backupFileURL(fileName: fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    public func deleteBackupFile(fileName: String) throws {
        let url = backupFileURL(fileName: fileName)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    public func loadBackupSnapshots() throws -> [BackupSnapshotMetadata] {
        guard fileManager.fileExists(atPath: backupSnapshotsFileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: backupSnapshotsFileURL)
        return try decoder.decode([BackupSnapshotMetadata].self, from: data)
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func saveBackupSnapshots(_ snapshots: [BackupSnapshotMetadata]) throws {
        try ensureDirectories()
        let sorted = snapshots.sorted { $0.createdAt > $1.createdAt }
        let data = try encoder.encode(sorted)
        try data.write(to: backupSnapshotsFileURL, options: .atomic)
    }

    public func loadBackupRunLog() throws -> [BackupRunLogEntry] {
        guard fileManager.fileExists(atPath: backupLogFileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: backupLogFileURL)
        return try decoder.decode([BackupRunLogEntry].self, from: data)
            .sorted { $0.timestamp > $1.timestamp }
    }

    public func appendBackupRunLog(_ log: BackupRunLogEntry, maxEntries: Int = 60) throws {
        var logs = try loadBackupRunLog()
        logs.insert(log, at: 0)
        if logs.count > maxEntries {
            logs = Array(logs.prefix(maxEntries))
        }
        let data = try encoder.encode(logs)
        try data.write(to: backupLogFileURL, options: .atomic)
    }

    // MARK: - Atomic Replace Support & File Size Helpers

    public func fileSize(forCoreFile name: String) -> Int64 {
        let url = rootURL.appendingPathComponent(name)
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    public func availableDeviceFreeBytes() -> Int64? {
        let values = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 {
            return important
        }
        if let standard = values?.volumeAvailableCapacity {
            return Int64(standard)
        }
        return nil
    }

    public func replaceJournalStateAtomically(
        entries: [CapsuleEntry],
        aiEntries: [AiEntry],
        mediaFiles: [String: Data]
    ) throws {
        try ensureDirectories()
        // 1. Write new media bytes first (with unique IDs or verified targets)
        for (mediaId, data) in mediaFiles {
            _ = try saveMedia(data: data, mediaId: mediaId)
        }
        // 2. Replace entries and AI entries atomically
        try saveEntries(entries)
        try saveAiEntries(aiEntries)
        // 3. Remove unreferenced media files after replacement
        let referencedIds = Set(entries.flatMap { entry in
            entry.media.flatMap { item -> [String] in
                if let motion = item.motionVideoMediaId {
                    return [item.mediaId, motion]
                }
                return [item.mediaId]
            }
        })
        let existing = try listAllMediaFiles()
        for file in existing where !referencedIds.contains(file.mediaId) {
            try deleteMedia(mediaId: file.mediaId)
        }
    }

    private func sanitizeFileComponent(_ name: String) -> String {
        let base = name.split(separator: "/").last.map(String.init) ?? name
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let cleaned = String(base.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            return UUID().uuidString.lowercased()
        }
        return cleaned
    }
}
