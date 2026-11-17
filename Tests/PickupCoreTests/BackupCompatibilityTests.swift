import Foundation
import Testing
@testable import PickupCore

@Suite("Android V2 Compatibility & Backup Service Tests")
struct BackupCompatibilityTests {

    private func makeTempRepo() throws -> (PickupRepository, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pickup-test-\(UUID().uuidString)", isDirectory: true)
        let repo = try PickupRepository(rootURL: dir)
        return (repo, dir)
    }

    @Test("Import Android v2 fixture + synthetic media and re-export matching strict schema")
    func androidV2RoundTripAndStrictSchema() async throws {
        let (repo, dir) = try makeTempRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        let contractsDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("contracts/fixtures")

        let androidFixtureData = try Data(contentsOf: contractsDir.appendingPathComponent("android-v2-backup.json"))
        let androidObj = try JSONSerialization.jsonObject(with: androidFixtureData) as! [String: Any]

        // Package Android v2 JSON inside a ZIP with the referenced media files
        let zipInput = try ZipArchive.encode(files: [
            "backup.json": androidFixtureData,
            "media/media_0000.png": Data([0x89, 0x50, 0x4E, 0x47]),
            "media/media_0001.mp4": Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]),
            "media/media_0002.jpg": Data([0xFF, 0xD8, 0xFF, 0xE0]),
            "media/media_0003.mp4": Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70]),
        ])

        let service = BackupService(repository: repo)
        let preview = try await service.inspectInput(data: zipInput)
        #expect(preview.format == .androidV2Zip)
        #expect(preview.entryCount == 1)
        #expect(preview.aiEntryCount == 1)
        #expect(preview.mediaCount == 4)
        #expect(preview.missingMediaCount == 0)

        let report = try await service.importData(zipInput, mode: .replace)
        #expect(report.importedEntries == 1)
        #expect(report.importedAiEntries == 1)
        #expect(report.importedMedia == 4)
        #expect(report.unavailableMedia == 0)

        // Add iOS extended metadata to the imported entry and verify backup.json stays strict
        var entries = try await repo.listEntries()
        #expect(entries.count == 1)
        entries[0].mood = "平静"
        entries[0].weather = "微风"
        entries[0].tags = ["夜游", "散步"]
        entries[0].isPinned = true
        try await repo.saveEntries(entries)

        let exported = try await service.exportPortableZip(includeMedia: true)
        let decodedFiles = try ZipArchive.decode(exported.data)
        let backupJsonData = try #require(decodedFiles["backup.json"])
        let exportedObj = try JSONSerialization.jsonObject(with: backupJsonData) as! [String: Any]

        // Strict schema key assertions (additionalProperties: false)
        #expect(Set(exportedObj.keys) == ["format", "formatVersion", "exportedAt", "entries", "aiEntries"])
        #expect(exportedObj["format"] as? String == "pickup-portable-backup")
        #expect(exportedObj["formatVersion"] as? Int == 2)

        let exportedEntries = exportedObj["entries"] as! [[String: Any]]
        #expect(exportedEntries.count == 1)
        let e0 = exportedEntries[0]
        #expect(Set(e0.keys) == ["id", "content", "imagePath", "imagePaths", "videoPaths", "media", "songInfo", "timestamp", "comments"])
        #expect(e0["id"] as? String == (androidObj["entries"] as! [[String: Any]])[0]["id"] as? String)
        #expect(e0["mood"] == nil) // Must live in ios-extensions.json, never in backup.json!

        // Ensure ios-extensions.json preserves iOS fields across re-import
        #expect(decodedFiles["ios-extensions.json"] != nil)
        let freshDir = FileManager.default.temporaryDirectory.appendingPathComponent("pickup-fresh-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: freshDir) }
        let freshRepo = try PickupRepository(rootURL: freshDir)
        let freshReport = try await BackupService(repository: freshRepo).importData(exported.data, mode: .replace)
        #expect(freshReport.importedEntries == 1)
        let restoredEntries = try await freshRepo.listEntries()
        #expect(restoredEntries[0].mood == "平静")
        #expect(restoredEntries[0].weather == "微风")
        #expect(restoredEntries[0].tags == ["夜游", "散步"])
        #expect(restoredEntries[0].isPinned == true)
    }

    @Test("Import legacy JSON entry array and deduplicate during Merge")
    func legacyArrayAndMergeDeduplication() async throws {
        let (repo, dir) = try makeTempRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        let contractsDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("contracts/fixtures")
        let legacyData = try Data(contentsOf: contractsDir.appendingPathComponent("legacy-entry-array.json"))

        let service = BackupService(repository: repo)
        let first = try await service.importData(legacyData, mode: .merge)
        #expect(first.importedEntries == 1)
        #expect(first.conflictsSkipped == 0)

        let second = try await service.importData(legacyData, mode: .merge)
        #expect(second.importedEntries == 0)
        #expect(second.conflictsSkipped == 1)
    }

    @Test("Replace import automatically creates pre-restore safety snapshot and supports .pickupvault")
    func replaceCreatesSafetySnapshotAndEncryptedVault() async throws {
        let (repo, dir) = try makeTempRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        let journal = JournalService(repository: repo)
        _ = try await journal.createEntry(content: "第一条珍贵记录", songInfo: "Evening breeze", media: [])

        let service = BackupService(repository: repo)
        let vaultExport = try await service.exportEncryptedVault(passphrase: "vault-secret", includeMedia: true)
        #expect(VaultCrypto.looksLikeEncryptedVault(vaultExport.data))

        // Add another entry then restore the earlier encrypted vault via Replace
        _ = try await journal.createEntry(content: "第二条可能会被替换掉的记录", songInfo: nil, media: [])
        #expect((try await repo.listEntries()).count == 2)

        let replaceReport = try await service.importData(vaultExport.data, mode: .replace, passphrase: "vault-secret")
        #expect(replaceReport.safetySnapshotFileName != nil)
        #expect(replaceReport.safetySnapshotFileName?.hasPrefix("pickup-safety-") == true)
        #expect((try await repo.listEntries()).count == 1)

        // Verify Markdown anthology export contains readable prose
        let mdZip = try await service.exportMarkdownAnthology(includeMedia: true)
        let mdFiles = try ZipArchive.decode(mdZip)
        let mdText = String(data: try #require(mdFiles["Pickup-Journal.md"]), encoding: .utf8) ?? ""
        #expect(mdText.contains("第一条珍贵记录"))
        #expect(mdText.contains("Evening breeze"))
    }
}
