import Foundation

public struct DataManagementService: Sendable {
    public let repository: PickupRepository

    public init(repository: PickupRepository) {
        self.repository = repository
    }

    public func computeStorageBreakdown() async throws -> StorageBreakdown {
        let entries = try await repository.listEntries()
        let aiEntries = try await repository.listAiEntries()
        let mediaFiles = try await repository.listAllMediaFiles()
        let snapshots = try await repository.loadBackupSnapshots()

        let referencedIds = Set(entries.flatMap { entry in
            entry.media.flatMap { item -> [String] in
                if let motion = item.motionVideoMediaId {
                    return [item.mediaId, motion]
                }
                return [item.mediaId]
            }
        })
        let videoIds = Set(entries.flatMap { entry in
            entry.media.flatMap { item -> [String] in
                switch item.type {
                case .video:
                    return [item.mediaId]
                case .motionPhoto:
                    return item.motionVideoMediaId.map { [$0] } ?? []
                case .image, .sketch:
                    return []
                }
            }
        })

        var imagesBytes: Int64 = 0
        var videosBytes: Int64 = 0
        var orphanBytes: Int64 = 0
        for file in mediaFiles {
            if !referencedIds.contains(file.mediaId) {
                orphanBytes += file.byteSize
            } else if videoIds.contains(file.mediaId) || file.mediaId.lowercased().hasSuffix(".mp4") || file.mediaId.lowercased().hasSuffix(".mov") {
                videosBytes += file.byteSize
            } else {
                imagesBytes += file.byteSize
            }
        }

        let entriesBytes = await repository.fileSize(forCoreFile: "entries.json")
        let aiBytes = await repository.fileSize(forCoreFile: "ai_entries.json")
        let draftsBytes = await repository.fileSize(forCoreFile: "draft.json")
        let backupsBytes = snapshots.reduce(Int64(0)) { total, item in
            total + item.byteSize
        }
        let freeBytes = await repository.availableDeviceFreeBytes()

        return StorageBreakdown(
            entriesBytes: entriesBytes,
            aiBytes: aiBytes,
            imagesBytes: imagesBytes + orphanBytes,
            videosBytes: videosBytes,
            draftsBytes: draftsBytes,
            backupsBytes: backupsBytes,
            orphanMediaBytes: orphanBytes,
            deviceFreeBytes: freeBytes,
            entryCount: entries.count,
            aiCount: aiEntries.count,
            mediaFileCount: mediaFiles.count,
            backupCount: snapshots.count
        )
    }

    public func scanOrphansAndHealth() async throws -> OrphanScanResult {
        let entries = try await repository.listEntries()
        let mediaFiles = try await repository.listAllMediaFiles()
        let diskSizes = Dictionary(uniqueKeysWithValues: mediaFiles.map { ($0.mediaId, $0.byteSize) })

        var ownerByMediaId: [String: (entry: CapsuleEntry, isVideo: Bool)] = [:]
        var missingRefs: [(entryId: String, mediaId: String)] = []

        for entry in entries {
            for item in entry.media {
                if diskSizes[item.mediaId] == nil {
                    missingRefs.append((entry.id, item.mediaId))
                } else {
                    ownerByMediaId[item.mediaId] = (entry, item.type == .video)
                }
                if let motionId = item.motionVideoMediaId {
                    if diskSizes[motionId] == nil {
                        missingRefs.append((entry.id, motionId))
                    } else {
                        ownerByMediaId[motionId] = (entry, true)
                    }
                }
            }
        }

        let referencedIds = Set(ownerByMediaId.keys)
        var orphanIds: [String] = []
        var orphanBytes: Int64 = 0
        for file in mediaFiles where !referencedIds.contains(file.mediaId) {
            orphanIds.append(file.mediaId)
            orphanBytes += file.byteSize
        }

        let heavy: [HeavyMediaItem] = mediaFiles
            .sorted { $0.byteSize > $1.byteSize }
            .prefix(25)
            .map { file in
                let owner = ownerByMediaId[file.mediaId]
                let preview = owner?.entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return HeavyMediaItem(
                    id: file.mediaId,
                    byteSize: file.byteSize,
                    isVideo: owner?.isVideo ?? (file.mediaId.lowercased().hasSuffix(".mp4") || file.mediaId.lowercased().hasSuffix(".mov")),
                    entryId: owner?.entry.id,
                    entryPreview: (preview?.isEmpty == false) ? String(preview!.prefix(42)) : "—",
                    timestamp: owner?.entry.timestamp
                )
            }

        return OrphanScanResult(
            orphanMediaIds: orphanIds,
            orphanByteSize: orphanBytes,
            missingMediaRefs: missingRefs,
            heavyMediaItems: heavy
        )
    }

    public func purgeOrphanMedia() async throws -> (deletedCount: Int, freedBytes: Int64) {
        let scan = try await scanOrphansAndHealth()
        for mediaId in scan.orphanMediaIds {
            try await repository.deleteMedia(mediaId: mediaId)
        }
        return (scan.orphanMediaIds.count, scan.orphanByteSize)
    }

    public func removeHeavyMediaItem(mediaId: String) async throws {
        var entries = try await repository.listEntries()
        var changed = false
        for i in entries.indices {
            let before = entries[i].media.count
            entries[i].media.removeAll { $0.mediaId == mediaId || $0.motionVideoMediaId == mediaId }
            if entries[i].media.count != before {
                changed = true
            }
        }
        if changed {
            try await repository.saveEntries(entries)
        }
        try await repository.deleteMedia(mediaId: mediaId)
    }

    public func repairMissingMediaReferences() async throws -> Int {
        let entries = try await repository.listEntries()
        let diskFiles = Set((try await repository.listAllMediaFiles()).map(\.mediaId))
        var repaired = 0
        var updated: [CapsuleEntry] = []

        for var entry in entries {
            var nextMedia: [MediaAttachment] = []
            for item in entry.media {
                if !diskFiles.contains(item.mediaId) {
                    repaired += 1
                    continue
                }
                if let motionId = item.motionVideoMediaId, !diskFiles.contains(motionId) {
                    repaired += 1
                    nextMedia.append(
                        MediaAttachment(
                            id: item.id,
                            type: item.type == .motionPhoto ? .image : item.type,
                            mediaId: item.mediaId,
                            motionVideoMediaId: nil,
                            legacySource: item.legacySource,
                            mimeType: item.mimeType,
                            byteSize: item.byteSize
                        )
                    )
                } else {
                    nextMedia.append(item)
                }
            }
            entry.media = nextMedia
            updated.append(entry)
        }
        if repaired > 0 {
            try await repository.saveEntries(updated)
        }
        return repaired
    }

    public func deleteEntries(in range: ClosedRange<Date>) async throws -> Int {
        let existing = try await repository.listEntries()
        let surviving = existing.filter { !range.contains($0.timestamp) }
        let removed = existing.count - surviving.count
        if removed > 0 {
            try await repository.saveEntries(surviving)
            _ = try await purgeOrphanMedia()
        }
        return removed
    }

    public func clearAiHistory() async throws {
        try await repository.saveAiEntries([])
    }

    public func clearAllData(createSafetyBackupFirst: Bool = true) async throws -> String? {
        var safetyName: String? = nil
        let existing = try await repository.listEntries()
        if createSafetyBackupFirst && !existing.isEmpty {
            let snap = try await AutoBackupEngine(repository: repository).createSnapshot(
                trigger: .preRestoreSafety,
                format: .portableZip,
                includeMedia: true,
                externalFolderURL: nil
            )
            safetyName = snap.metadata.fileName
        }
        try await repository.replaceJournalStateAtomically(entries: [], aiEntries: [], mediaFiles: [:])
        try await repository.clearDraft()
        return safetyName
    }
}
