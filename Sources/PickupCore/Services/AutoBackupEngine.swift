import Foundation

public struct AutoBackupEngine: Sendable {
    public let repository: PickupRepository

    public init(repository: PickupRepository) {
        self.repository = repository
    }

    /// Determines whether an automatic scheduled backup is due right now based on settings & clock.
    public static func isScheduledBackupDue(
        settings: AutoBackupSettings,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard settings.isEnabled else { return false }
        switch settings.frequency {
        case .manualOnly, .onEntryChange, .onAppBackground:
            return false
        case .every6Hours:
            guard let last = settings.lastSuccessAt else { return true }
            return now.timeIntervalSince(last) >= 6 * 3600
        case .daily:
            guard let last = settings.lastSuccessAt else {
                // Due once preferred time today has arrived (or anytime on day 1 if desired? Wait: check preferred time today)
                let preferredToday = calendar.date(
                    bySettingHour: settings.preferredHour,
                    minute: settings.preferredMinute,
                    second: 0,
                    of: now
                ) ?? now
                return now >= preferredToday
            }
            if calendar.isDate(last, inSameDayAs: now) {
                return false
            }
            let preferredToday = calendar.date(
                bySettingHour: settings.preferredHour,
                minute: settings.preferredMinute,
                second: 0,
                of: now
            ) ?? now
            return now >= preferredToday || now.timeIntervalSince(last) >= 24 * 3600
        case .weekly:
            guard let last = settings.lastSuccessAt else { return true }
            return now.timeIntervalSince(last) >= 7 * 24 * 3600
        }
    }

    public func createSnapshot(
        trigger: BackupTriggerKind,
        format: BackupFormatKind? = nil,
        includeMedia: Bool? = nil,
        passphrase: String? = nil,
        externalFolderURL: URL? = nil,
        isPinned: Bool = false,
        now: Date = Date()
    ) async throws -> BackupSnapshotInfo {
        var prefs = try await repository.loadPreferences()
        let actualFormat = format ?? prefs.autoBackup.format
        let actualIncludeMedia = includeMedia ?? prefs.autoBackup.includeMedia

        let backupService = BackupService(repository: repository)
        let data: Data
        let mediaCount: Int
        let entryCount: Int
        let aiCount: Int
        let ext: String

        switch actualFormat {
        case .portableZip:
            let res = try await backupService.exportPortableZip(includeMedia: actualIncludeMedia, now: now)
            data = res.data
            mediaCount = res.mediaCount
            entryCount = res.entryCount
            aiCount = res.aiCount
            ext = "zip"
        case .encryptedVault:
            guard let passphrase, !passphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackupServiceError.passphraseRequired
            }
            let res = try await backupService.exportEncryptedVault(passphrase: passphrase, includeMedia: actualIncludeMedia, now: now)
            data = res.data
            mediaCount = res.mediaCount
            entryCount = res.entryCount
            aiCount = res.aiCount
            ext = "pickupvault"
        case .markdownAnthology:
            data = try await backupService.exportMarkdownAnthology(includeMedia: actualIncludeMedia, now: now)
            entryCount = try await repository.listEntries().count
            aiCount = try await repository.listAiEntries().count
            mediaCount = actualIncludeMedia ? (try await repository.listAllMediaFiles().count) : 0
            ext = "md.zip"
        }

        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        df.locale = Locale(identifier: "en_US_POSIX")
        let prefix: String
        switch trigger {
        case .preRestoreSafety:
            prefix = "pickup-safety"
        case .manual:
            prefix = "pickup-manual"
        case .scheduled, .entryChange, .background:
            prefix = "pickup-auto"
        }
        let uniqueSuffix = String(UUID().uuidString.prefix(4).lowercased())
        let fileName = "\(prefix)-\(df.string(from: now))-\(uniqueSuffix).\(ext)"
        let localURL = try await repository.saveBackupFile(data: data, fileName: fileName)
        let sha = VaultCrypto.sha256Hex(data)

        var wroteExternal = false
        if let externalFolderURL {
            let accessed = externalFolderURL.startAccessingSecurityScopedResource()
            defer {
                if accessed { externalFolderURL.stopAccessingSecurityScopedResource() }
            }
            let extDest = externalFolderURL.appendingPathComponent(fileName)
            do {
                try data.write(to: extDest, options: .atomic)
                wroteExternal = true
            } catch {
                wroteExternal = false
            }
        }

        let meta = BackupSnapshotMetadata(
            fileName: fileName,
            createdAt: now,
            byteSize: Int64(data.count),
            format: actualFormat,
            trigger: trigger,
            sha256: sha,
            entryCount: entryCount,
            aiCount: aiCount,
            mediaCount: mediaCount,
            isPinned: isPinned || trigger == .preRestoreSafety,
            copiedToExternal: wroteExternal
        )

        var snapshots = try await repository.loadBackupSnapshots()
        snapshots.insert(meta, at: 0)
        snapshots = try await pruneRetention(
            snapshots: snapshots,
            retentionCount: prefs.autoBackup.retentionCount
        )
        try await repository.saveBackupSnapshots(snapshots)

        prefs.autoBackup.lastAttemptAt = now
        prefs.autoBackup.lastSuccessAt = now
        prefs.autoBackup.consecutiveFailures = 0
        prefs.autoBackup.lastErrorMessage = nil
        prefs.autoBackup.lastStatusMessage = "\(fileName) (\(entryCount))"
        try await repository.savePreferences(prefs)

        try await repository.appendBackupRunLog(
            BackupRunLogEntry(
                timestamp: now,
                trigger: trigger,
                format: actualFormat,
                fileName: fileName,
                byteSize: Int64(data.count),
                sha256: sha,
                succeeded: true,
                writtenToExternal: wroteExternal,
                message: wroteExternal ? "Saved locally & synced to external folder" : "Saved locally"
            )
        )

        return BackupSnapshotInfo(metadata: meta, fileURL: localURL, fileExists: true)
    }

    public func runScheduledCheckIfNeeded(
        externalFolderURL: URL? = nil,
        passphrase: String? = nil,
        now: Date = Date()
    ) async throws -> BackupSnapshotInfo? {
        let prefs = try await repository.loadPreferences()
        guard Self.isScheduledBackupDue(settings: prefs.autoBackup, now: now) else {
            return nil
        }
        // Only fall back to portableZip if encryptedVault has no available passphrase in background
        let format: BackupFormatKind = (prefs.autoBackup.format == .encryptedVault && (passphrase ?? "").isEmpty)
            ? .portableZip
            : prefs.autoBackup.format
        return try await createSnapshot(
            trigger: .scheduled,
            format: format,
            includeMedia: prefs.autoBackup.includeMedia,
            passphrase: passphrase,
            externalFolderURL: externalFolderURL,
            now: now
        )
    }

    public func listSnapshots() async throws -> [BackupSnapshotInfo] {
        let metas = try await repository.loadBackupSnapshots()
        let fm = FileManager.default
        var result: [BackupSnapshotInfo] = []
        for meta in metas {
            let url = await repository.backupFileURL(fileName: meta.fileName)
            result.append(BackupSnapshotInfo(metadata: meta, fileURL: url, fileExists: fm.fileExists(atPath: url.path)))
        }
        return result
    }

    public func verifySnapshotIntegrity(id: String) async throws -> Bool {
        let metas = try await repository.loadBackupSnapshots()
        guard let meta = metas.first(where: { $0.id == id }) else {
            return false
        }
        let url = await repository.backupFileURL(fileName: meta.fileName)
        guard let data = try? Data(contentsOf: url) else {
            return false
        }
        return VaultCrypto.sha256Hex(data) == meta.sha256
    }

    public func togglePin(snapshotId: String) async throws -> [BackupSnapshotInfo] {
        var metas = try await repository.loadBackupSnapshots()
        if let idx = metas.firstIndex(where: { $0.id == snapshotId }) {
            metas[idx].isPinned.toggle()
            try await repository.saveBackupSnapshots(metas)
        }
        return try await listSnapshots()
    }

    public func deleteSnapshot(id: String) async throws -> [BackupSnapshotInfo] {
        var metas = try await repository.loadBackupSnapshots()
        if let idx = metas.firstIndex(where: { $0.id == id }) {
            let target = metas[idx]
            try await repository.deleteBackupFile(fileName: target.fileName)
            metas.remove(at: idx)
            try await repository.saveBackupSnapshots(metas)
        }
        return try await listSnapshots()
    }

    public func restoreSnapshot(
        id: String,
        mode: ImportMode,
        passphrase: String? = nil
    ) async throws -> ImportReport {
        let metas = try await repository.loadBackupSnapshots()
        guard let meta = metas.first(where: { $0.id == id }) else {
            throw BackupServiceError.missingBackupJson
        }
        let url = await repository.backupFileURL(fileName: meta.fileName)
        let data = try Data(contentsOf: url)
        return try await BackupService(repository: repository).importData(data, mode: mode, passphrase: passphrase)
    }

    private func pruneRetention(
        snapshots: [BackupSnapshotMetadata],
        retentionCount: Int
    ) async throws -> [BackupSnapshotMetadata] {
        guard retentionCount > 0 else { return snapshots }
        let sorted = snapshots.sorted { $0.createdAt > $1.createdAt }
        var keptUnpinnedCount = 0
        var surviving: [BackupSnapshotMetadata] = []

        for snap in sorted {
            // Never automatically delete pinned snapshots or manual exports
            if snap.isPinned || snap.trigger == .manual || snap.trigger == .preRestoreSafety {
                surviving.append(snap)
                continue
            }
            if keptUnpinnedCount < retentionCount {
                keptUnpinnedCount += 1
                surviving.append(snap)
            } else {
                try? await repository.deleteBackupFile(fileName: snap.fileName)
            }
        }
        return surviving
    }
}
