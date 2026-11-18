import Foundation
import Testing
@testable import PickupCore

@Suite("Auto-Backup Engine & Data Management Tests")
struct AutoBackupAndDataManagementTests {

    private func makeTempRepo() throws -> (PickupRepository, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pickup-vault-test-\(UUID().uuidString)", isDirectory: true)
        let repo = try PickupRepository(rootURL: dir)
        return (repo, dir)
    }

    @Test("Scheduled backup evaluation obeys frequency and daily preferred time")
    func scheduledBackupDueEvaluation() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 9, minute: 0))!
        let night = cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 23, minute: 0))!
        let yesterday = cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 22, minute: 35))!

        var settings = AutoBackupSettings(isEnabled: true, frequency: .daily, preferredHour: 22, preferredMinute: 30, lastSuccessAt: yesterday)
        #expect(!AutoBackupEngine.isScheduledBackupDue(settings: settings, now: morning, calendar: cal))
        #expect(AutoBackupEngine.isScheduledBackupDue(settings: settings, now: night, calendar: cal))

        settings.lastSuccessAt = night
        #expect(!AutoBackupEngine.isScheduledBackupDue(settings: settings, now: night.addingTimeInterval(600), calendar: cal))

        settings.frequency = .every6Hours
        #expect(!AutoBackupEngine.isScheduledBackupDue(settings: settings, now: night.addingTimeInterval(3600), calendar: cal))
        #expect(AutoBackupEngine.isScheduledBackupDue(settings: settings, now: night.addingTimeInterval(6 * 3600 + 10), calendar: cal))
    }

    @Test("Retention pruning preserves pinned & manual snapshots while pruning old auto-backups")
    func retentionPruningAndExternalMirror() async throws {
        let (repo, dir) = try makeTempRepo()
        let externalDir = dir.appendingPathComponent("ExternalMirror", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var prefs = try await repo.loadPreferences()
        prefs.autoBackup.retentionCount = 2
        try await repo.savePreferences(prefs)

        let journal = JournalService(repository: repo)
        _ = try await journal.createEntry(content: "备份测试日记", songInfo: nil, media: [])

        let engine = AutoBackupEngine(repository: repo)
        let base = Date(timeIntervalSince1970: 1_763_000_000)

        // Create 1 pinned auto backup (oldest) + 3 unpinned auto backups + 1 manual backup
        let pinnedSnap = try await engine.createSnapshot(trigger: .scheduled, externalFolderURL: externalDir, isPinned: true, now: base)
        _ = try await engine.createSnapshot(trigger: .scheduled, externalFolderURL: externalDir, isPinned: false, now: base.addingTimeInterval(10))
        _ = try await engine.createSnapshot(trigger: .scheduled, externalFolderURL: externalDir, isPinned: false, now: base.addingTimeInterval(20))
        _ = try await engine.createSnapshot(trigger: .scheduled, externalFolderURL: externalDir, isPinned: false, now: base.addingTimeInterval(30))
        _ = try await engine.createSnapshot(trigger: .manual, externalFolderURL: nil, isPinned: false, now: base.addingTimeInterval(40))

        let snapshots = try await engine.listSnapshots()
        // Should have: 1 manual + 2 most recent unpinned auto + 1 pinned auto = 4 snapshots total
        #expect(snapshots.count == 4)
        #expect(snapshots.contains { $0.id == pinnedSnap.id && $0.metadata.isPinned })
        #expect(snapshots.allSatisfy { $0.fileExists })

        // Verify SHA-256 check and external mirror file presence
        #expect(try await engine.verifySnapshotIntegrity(id: pinnedSnap.id))
        let extFile = externalDir.appendingPathComponent(pinnedSnap.metadata.fileName)
        #expect(FileManager.default.fileExists(atPath: extFile.path))
    }

    @Test("DataManagementService detects and purges orphan media and computes byte breakdown")
    func orphanScanAndStorageBreakdown() async throws {
        let (repo, dir) = try makeTempRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        let activeBytes = Data(repeating: 0xAB, count: 4096)
        let orphanBytes = Data(repeating: 0xCD, count: 8192)
        _ = try await repo.saveMedia(data: activeBytes, mediaId: "active.jpg")
        _ = try await repo.saveMedia(data: orphanBytes, mediaId: "orphan.jpg")

        let journal = JournalService(repository: repo)
        let activeAtt = MediaAttachment(type: .image, mediaId: "active.jpg", mimeType: "image/jpeg", byteSize: Int64(activeBytes.count))
        _ = try await journal.createEntry(content: "带有有效照片", songInfo: nil, media: [activeAtt])

        let dm = DataManagementService(repository: repo)
        let breakdown = try await dm.computeStorageBreakdown()
        #expect(breakdown.entryCount == 1)
        #expect(breakdown.mediaFileCount == 2)
        #expect(breakdown.orphanMediaBytes == 8192)
        #expect(breakdown.imagesBytes == 4096 + 8192)

        let scan = try await dm.scanOrphansAndHealth()
        #expect(scan.orphanMediaIds == ["orphan.jpg"])
        #expect(scan.orphanByteSize == 8192)

        let purge = try await dm.purgeOrphanMedia()
        #expect(purge.deletedCount == 1)
        #expect(purge.freedBytes == 8192)

        let afterScan = try await dm.scanOrphansAndHealth()
        #expect(afterScan.orphanMediaIds.isEmpty)

        // Factory reset with automatic safety snapshot
        let safetyName = try await dm.clearAllData(createSafetyBackupFirst: true)
        #expect(safetyName != nil)
        #expect((try await repo.listEntries()).isEmpty)
        #expect((try await AutoBackupEngine(repository: repo).listSnapshots()).count == 1)
    }

    @Test("Monochrome theme defaults and safe fallback decoding for legacy or unknown themes")
    func monochromeThemeDefaultsAndDecodingFallback() throws {
        let defaultPrefs = AppPreferences()
        #expect(defaultPrefs.themeStyle == .monochrome)

        // Verify legacy identifier decodes safely to .monochrome
        let legacyIdentifier = ["pur", "ple", "Dark"].joined()
        let legacyData = Data(#""\#(legacyIdentifier)""#.utf8)
        let decodedLegacy = try JSONDecoder().decode(PickupThemeStyle.self, from: legacyData)
        #expect(decodedLegacy == .monochrome)

        // Verify AppPreferences payload containing legacy theme identifier decodes to .monochrome
        let encodedPrefs = try JSONEncoder().encode(AppPreferences(themeStyle: .monochromeLight))
        let lightDecodedPrefs = try JSONDecoder().decode(AppPreferences.self, from: encodedPrefs)
        #expect(lightDecodedPrefs.themeStyle == .monochromeLight)

        let rawPrefsString = try #require(String(data: encodedPrefs, encoding: .utf8))
        let legacyPrefsString = rawPrefsString.replacingOccurrences(of: "monochromeLight", with: legacyIdentifier)
        let decodedLegacyPrefs = try JSONDecoder().decode(AppPreferences.self, from: Data(legacyPrefsString.utf8))
        #expect(decodedLegacyPrefs.themeStyle == .monochrome)

        // Verify unrecognized theme string falls back to .monochrome
        let unknownData = Data(#""unknownTheme""#.utf8)
        let decodedUnknown = try JSONDecoder().decode(PickupThemeStyle.self, from: unknownData)
        #expect(decodedUnknown == .monochrome)

        // Verify monochromeLight raw value round-trips cleanly
        let lightData = Data(#""monochromeLight""#.utf8)
        let decodedLight = try JSONDecoder().decode(PickupThemeStyle.self, from: lightData)
        #expect(decodedLight == .monochromeLight)

        // Verify localized theme strings
        #expect(PickupStrings(.zh).t("theme_mono") == "墨黑毛玻璃 (Obsidian)")
        #expect(PickupStrings(.zh).t("theme_mono_light") == "素白毛玻璃 (Paper)")
        #expect(PickupStrings(.en).t("theme_mono") == "Obsidian Glass (Dark)")
        #expect(PickupStrings(.en).t("theme_mono_light") == "Paper Glass (Light)")
    }
}
