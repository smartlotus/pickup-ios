import Foundation

public enum BackupServiceError: Error, Sendable, Equatable, LocalizedError {
    case unrecognizedFormat
    case missingBackupJson
    case missingMediaFile(String)
    case passphraseRequired
    case invalidPassphrase

    public var errorDescription: String? {
        switch self {
        case .unrecognizedFormat:
            return "Unrecognized Pickup backup format."
        case .missingBackupJson:
            return "Backup ZIP archive is missing backup.json."
        case .missingMediaFile(let path):
            return "Referenced media file missing from backup: \(path)."
        case .passphraseRequired:
            return "An encryption passphrase is required for this .pickupvault backup."
        case .invalidPassphrase:
            return "The passphrase for this encrypted backup is incorrect."
        }
    }
}

public struct BackupService: Sendable {
    public let repository: PickupRepository

    public init(repository: PickupRepository) {
        self.repository = repository
    }

    // MARK: - Export

    /// Produces a 100% Android Pickup v2 compatible ZIP (`backup.json` + `media/`),
    /// plus a non-intrusive `ios-extensions.json` preserving iOS-only mood/tags/weather/pin metadata.
    public func exportPortableZip(includeMedia: Bool = true, now: Date = Date()) async throws -> (data: Data, mediaCount: Int, entryCount: Int, aiCount: Int) {
        let entries = try await repository.listEntries()
        let aiEntries = try await repository.listAiEntries()
        let prefs = try await repository.loadPreferences()

        var zipFiles: [String: Data] = [:]
        var pathByMediaId: [String: String] = [:]
        var sequence = 0

        if includeMedia {
            let orderedMediaRefs = entries.flatMap { entry in
                entry.media.flatMap { item -> [(id: String, mime: String, fallback: String)] in
                    var list = [(item.mediaId, item.mimeType, item.sourcePath)]
                    if let motionId = item.motionVideoMediaId {
                        list.append((motionId, "video/quicktime", "\(motionId).mov"))
                    }
                    return list
                }
            }
            for ref in orderedMediaRefs where pathByMediaId[ref.id] == nil {
                if let bytes = try await repository.loadMedia(mediaId: ref.id) {
                    let ext = MediaAttachment.fileExtension(for: ref.mime, fallbackPath: ref.fallback)
                    let portablePath = String(format: "media/media_%04d%@", sequence, ext)
                    sequence += 1
                    pathByMediaId[ref.id] = portablePath
                    zipFiles[portablePath] = bytes
                }
            }
        }

        let wireEntries: [PortableEntryWire] = entries.map { entry in
            var portableMedia: [PortableMediaWire] = []
            var imagePaths: [String] = []
            var videoPaths: [String] = []

            for attachment in entry.media {
                guard let mainPath = pathByMediaId[attachment.mediaId] else {
                    continue
                }
                let motionPath = attachment.motionVideoMediaId.flatMap { pathByMediaId[$0] }
                let typeStr = (attachment.type == .motionPhoto && motionPath == nil)
                    ? "image"
                    : attachment.type.portableTypeString

                portableMedia.append(
                    PortableMediaWire(
                        id: attachment.id,
                        type: typeStr,
                        path: mainPath,
                        motionVideoPath: motionPath
                    )
                )
                if attachment.isImage {
                    imagePaths.append(mainPath)
                }
                if attachment.type == .video {
                    videoPaths.append(mainPath)
                } else if let motionPath {
                    videoPaths.append(motionPath)
                }
            }

            return PortableEntryWire(
                id: entry.id,
                content: entry.content,
                imagePath: imagePaths.first,
                imagePaths: imagePaths,
                videoPaths: videoPaths,
                media: portableMedia,
                songInfo: entry.songInfo,
                timestamp: PortableDateCodec.format(entry.timestamp),
                comments: entry.comments.map {
                    PortableCommentWire(text: $0.text, timestamp: PortableDateCodec.format($0.timestamp))
                }
            )
        }

        let wireAi: [PortableAiEntryWire] = aiEntries.map { item in
            PortableAiEntryWire(
                id: item.id,
                question: item.question,
                answer: item.answer,
                type: item.type.rawValue,
                timestamp: PortableDateCodec.format(item.timestamp),
                comments: item.comments.map {
                    PortableCommentWire(text: $0.text, timestamp: PortableDateCodec.format($0.timestamp))
                }
            )
        }

        let payload = PortableBackupWire(
            format: "pickup-portable-backup",
            formatVersion: 2,
            exportedAt: PortableDateCodec.format(now),
            entries: wireEntries,
            aiEntries: wireAi
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        zipFiles["backup.json"] = try encoder.encode(payload)

        // Separate iOS extension sidecar (keeps backup.json 100% compliant with additionalProperties: false)
        var entryExtensions: [String: IOSEntryExtensionRecord] = [:]
        for entry in entries where entry.hasExtendedMetadata {
            let sketchIds = entry.media.filter { $0.type == .sketch }.map(\.id)
            entryExtensions[entry.id] = IOSEntryExtensionRecord(
                mood: entry.mood,
                weather: entry.weather,
                tags: entry.tags,
                isPinned: entry.isPinned,
                sketchAttachmentIds: sketchIds,
                updatedAt: entry.updatedAt.map { PortableDateCodec.format($0) }
            )
        }
        var aiWindows: [String: IOSAiContextWindowRecord] = [:]
        for item in aiEntries where item.contextStart != nil || item.contextEnd != nil {
            aiWindows[item.id] = IOSAiContextWindowRecord(
                contextStart: item.contextStart.map { PortableDateCodec.format($0) },
                contextEnd: item.contextEnd.map { PortableDateCodec.format($0) }
            )
        }
        let extPayload = IOSExtensionsPayload(
            entryExtensions: entryExtensions,
            aiContextWindows: aiWindows,
            themeStyle: prefs.themeStyle,
            language: prefs.language,
            typographyStyle: prefs.typographyStyle
        )
        zipFiles["ios-extensions.json"] = try encoder.encode(extPayload)

        let zipData = try ZipArchive.encode(files: zipFiles)
        return (zipData, sequence, entries.count, aiEntries.count)
    }

    public func exportEncryptedVault(passphrase: String, includeMedia: Bool = true, now: Date = Date()) async throws -> (data: Data, mediaCount: Int, entryCount: Int, aiCount: Int) {
        let exported = try await exportPortableZip(includeMedia: includeMedia, now: now)
        let sealed = try VaultCrypto.seal(plaintext: exported.data, passphrase: passphrase)
        return (sealed, exported.mediaCount, exported.entryCount, exported.aiCount)
    }

    public func exportMarkdownAnthology(includeMedia: Bool = true, now: Date = Date()) async throws -> Data {
        let entries = try await repository.listEntries().sorted { $0.timestamp > $1.timestamp }
        var files: [String: Data] = [:]
        var md = "# Pickup Journal Anthology\n\n"
        md += "> Exported at \(PortableDateCodec.format(now)) · \(entries.count) memories\n\n---\n\n"

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"

        var mediaSeq = 0
        for entry in entries {
            md += "## \(df.string(from: entry.timestamp))"
            if entry.isPinned { md += " ★" }
            md += "\n\n"

            var metaParts: [String] = []
            if let mood = entry.mood { metaParts.append("Mood: \(mood)") }
            if let weather = entry.weather { metaParts.append("Weather: \(weather)") }
            if let song = entry.songInfo { metaParts.append("♫ \(song)") }
            if !entry.tags.isEmpty { metaParts.append(entry.tags.map { "#\($0)" }.joined(separator: " ")) }
            if !metaParts.isEmpty {
                md += "_" + metaParts.joined(separator: " · ") + "_\n\n"
            }

            if !entry.content.isEmpty {
                md += entry.content + "\n\n"
            }

            if includeMedia {
                for attachment in entry.media {
                    if let bytes = try await repository.loadMedia(mediaId: attachment.mediaId) {
                        let ext = MediaAttachment.fileExtension(for: attachment.mimeType, fallbackPath: attachment.sourcePath)
                        let relPath = String(format: "media/media_%04d%@", mediaSeq, ext)
                        mediaSeq += 1
                        files[relPath] = bytes
                        if attachment.type == .video {
                            md += "- [Video Attachment](\(relPath))\n"
                        } else {
                            md += "![Attachment](\(relPath))\n"
                        }
                    }
                }
                if !entry.media.isEmpty { md += "\n" }
            }

            if !entry.comments.isEmpty {
                md += "**Reflections**\n\n"
                for c in entry.comments {
                    md += "> \(df.string(from: c.timestamp)) — \(c.text)\n\n"
                }
            }
            md += "---\n\n"
        }

        files["Pickup-Journal.md"] = Data(md.utf8)
        return try ZipArchive.encode(files: files)
    }

    // MARK: - Inspect & Import

    public func inspectInput(data: Data, passphrase: String? = nil) async throws -> ImportPreviewReport {
        let parsed = try await parseInput(data: data, passphrase: passphrase)
        let currentEntries = try await repository.listEntries()
        let currentIds = Set(currentEntries.map(\.id))
        let currentFingerprints = Set(currentEntries.map(entryFingerprint))
        var conflicts = 0
        for entry in parsed.entries {
            if currentIds.contains(entry.id) || currentFingerprints.contains(entryFingerprint(entry)) {
                conflicts += 1
            }
        }
        return ImportPreviewReport(
            format: parsed.format,
            entryCount: parsed.entries.count,
            aiEntryCount: parsed.aiEntries.count,
            mediaCount: parsed.mediaBytesByPortablePath.count,
            missingMediaCount: parsed.missingMediaCount,
            conflictCount: conflicts,
            hasIOSExtensions: parsed.hasIOSExtensions,
            exportedAt: parsed.exportedAt
        )
    }

    public func importData(
        _ data: Data,
        mode: ImportMode,
        passphrase: String? = nil
    ) async throws -> ImportReport {
        let parsed = try await parseInput(data: data, passphrase: passphrase)

        switch mode {
        case .merge:
            let existingEntries = try await repository.listEntries()
            let existingAi = try await repository.listAiEntries()
            var seenEntryIds = Set(existingEntries.map(\.id))
            var seenEntryPrints = Set(existingEntries.map(entryFingerprint))
            var seenAiIds = Set(existingAi.map(\.id))
            var seenAiPrints = Set(existingAi.map(aiFingerprint))

            var acceptedEntries: [CapsuleEntry] = []
            var conflicts = 0
            for entry in parsed.entries {
                let fp = entryFingerprint(entry)
                if seenEntryIds.contains(entry.id) || seenEntryPrints.contains(fp) {
                    conflicts += 1
                } else {
                    seenEntryIds.insert(entry.id)
                    seenEntryPrints.insert(fp)
                    acceptedEntries.append(entry)
                }
            }

            var acceptedAi: [AiEntry] = []
            for ai in parsed.aiEntries {
                let fp = aiFingerprint(ai)
                if seenAiIds.contains(ai.id) || seenAiPrints.contains(fp) {
                    conflicts += 1
                } else {
                    seenAiIds.insert(ai.id)
                    seenAiPrints.insert(fp)
                    acceptedAi.append(ai)
                }
            }

            let materialized = try await materializeMedia(
                for: acceptedEntries,
                mediaBytesByPortablePath: parsed.mediaBytesByPortablePath
            )
            for (mediaId, bytes) in materialized.mediaData {
                _ = try await repository.saveMedia(data: bytes, mediaId: mediaId)
            }
            try await repository.saveEntries(existingEntries + materialized.entries)
            try await repository.saveAiEntries(existingAi + acceptedAi)

            return ImportReport(
                importedEntries: materialized.entries.count,
                importedAiEntries: acceptedAi.count,
                importedMedia: materialized.mediaData.count,
                conflictsSkipped: conflicts,
                unavailableMedia: materialized.missingCount,
                safetySnapshotFileName: nil
            )

        case .replace:
            // Create safety backup snapshot automatically BEFORE replacing!
            var safetyFileName: String? = nil
            let existingEntries = try await repository.listEntries()
            if !existingEntries.isEmpty {
                let safety = try await AutoBackupEngine(repository: repository).createSnapshot(
                    trigger: .preRestoreSafety,
                    format: .portableZip,
                    includeMedia: true,
                    externalFolderURL: nil
                )
                safetyFileName = safety.metadata.fileName
            }

            let materialized = try await materializeMedia(
                for: parsed.entries,
                mediaBytesByPortablePath: parsed.mediaBytesByPortablePath
            )
            try await repository.replaceJournalStateAtomically(
                entries: materialized.entries,
                aiEntries: parsed.aiEntries,
                mediaFiles: materialized.mediaData
            )

            return ImportReport(
                importedEntries: materialized.entries.count,
                importedAiEntries: parsed.aiEntries.count,
                importedMedia: materialized.mediaData.count,
                conflictsSkipped: 0,
                unavailableMedia: materialized.missingCount,
                safetySnapshotFileName: safetyFileName
            )
        }
    }

    // MARK: - Internal Parsing

    private struct ParsedInput {
        let format: DetectedBackupFormat
        let entries: [CapsuleEntry]
        let aiEntries: [AiEntry]
        let mediaBytesByPortablePath: [String: Data]
        let missingMediaCount: Int
        let hasIOSExtensions: Bool
        let exportedAt: Date?
    }

    private func parseInput(data: Data, passphrase: String?) async throws -> ParsedInput {
        if VaultCrypto.looksLikeEncryptedVault(data) {
            guard let passphrase, !passphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BackupServiceError.passphraseRequired
            }
            let decryptedZip: Data
            do {
                decryptedZip = try VaultCrypto.open(vaultData: data, passphrase: passphrase)
            } catch {
                throw BackupServiceError.invalidPassphrase
            }
            var inner = try await parseZipInput(decryptedZip)
            inner = ParsedInput(
                format: .encryptedVault,
                entries: inner.entries,
                aiEntries: inner.aiEntries,
                mediaBytesByPortablePath: inner.mediaBytesByPortablePath,
                missingMediaCount: inner.missingMediaCount,
                hasIOSExtensions: inner.hasIOSExtensions,
                exportedAt: inner.exportedAt
            )
            return inner
        }

        if ZipArchive.looksLikeZip(data) {
            return try await parseZipInput(data)
        }

        // JSON input: either Android v2 JSON object OR legacy array of entries
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw BackupServiceError.unrecognizedFormat
        }

        if let dict = jsonObject as? [String: Any], dict["entries"] != nil {
            let parsed = try parsePortablePayloadDict(dict, files: [:])
            return ParsedInput(
                format: .portableJson,
                entries: parsed.entries,
                aiEntries: parsed.aiEntries,
                mediaBytesByPortablePath: [:],
                missingMediaCount: parsed.missingMediaCount,
                hasIOSExtensions: false,
                exportedAt: parsed.exportedAt
            )
        }

        if let array = jsonObject as? [[String: Any]] {
            let entries = try array.map(parseRawEntry)
            return ParsedInput(
                format: .legacyJsonArray,
                entries: entries,
                aiEntries: [],
                mediaBytesByPortablePath: [:],
                missingMediaCount: 0,
                hasIOSExtensions: false,
                exportedAt: nil
            )
        }

        throw BackupServiceError.unrecognizedFormat
    }

    private func parseZipInput(_ zipData: Data) async throws -> ParsedInput {
        let files = try ZipArchive.decode(zipData)
        guard let backupJsonData = files["backup.json"] else {
            throw BackupServiceError.missingBackupJson
        }
        guard let dict = try JSONSerialization.jsonObject(with: backupJsonData) as? [String: Any] else {
            throw BackupServiceError.unrecognizedFormat
        }

        var iosExt: IOSExtensionsPayload? = nil
        if let extData = files["ios-extensions.json"] {
            iosExt = try? JSONDecoder().decode(IOSExtensionsPayload.self, from: extData)
        }

        var parsed = try parsePortablePayloadDict(dict, files: files)

        // Merge iOS-extended metadata if present
        if let iosExt {
            parsed.entries = parsed.entries.map { entry in
                guard let ext = iosExt.entryExtensions[entry.id] else { return entry }
                var next = entry
                next.mood = ext.mood
                next.weather = ext.weather
                next.tags = ext.tags
                next.isPinned = ext.isPinned
                if let updatedStr = ext.updatedAt {
                    next.updatedAt = PortableDateCodec.parse(updatedStr)
                }
                if !ext.sketchAttachmentIds.isEmpty {
                    let sketchSet = Set(ext.sketchAttachmentIds)
                    next.media = next.media.map { item in
                        if sketchSet.contains(item.id) {
                            return MediaAttachment(
                                id: item.id,
                                type: .sketch,
                                mediaId: item.mediaId,
                                motionVideoMediaId: item.motionVideoMediaId,
                                legacySource: item.legacySource,
                                mimeType: item.mimeType,
                                byteSize: item.byteSize
                            )
                        }
                        return item
                    }
                }
                return next
            }
            parsed.aiEntries = parsed.aiEntries.map { ai in
                guard let win = iosExt.aiContextWindows[ai.id] else { return ai }
                return AiEntry(
                    id: ai.id,
                    question: ai.question,
                    answer: ai.answer,
                    type: ai.type,
                    timestamp: ai.timestamp,
                    contextStart: win.contextStart.flatMap(PortableDateCodec.parse),
                    contextEnd: win.contextEnd.flatMap(PortableDateCodec.parse),
                    comments: ai.comments
                )
            }
        }

        return ParsedInput(
            format: .androidV2Zip,
            entries: parsed.entries,
            aiEntries: parsed.aiEntries,
            mediaBytesByPortablePath: files.filter { $0.key.hasPrefix("media/") },
            missingMediaCount: parsed.missingMediaCount,
            hasIOSExtensions: iosExt != nil,
            exportedAt: parsed.exportedAt
        )
    }

    private func parsePortablePayloadDict(
        _ dict: [String: Any],
        files: [String: Data]
    ) throws -> (entries: [CapsuleEntry], aiEntries: [AiEntry], missingMediaCount: Int, exportedAt: Date?) {
        guard let rawEntries = dict["entries"] as? [[String: Any]] else {
            throw BackupServiceError.unrecognizedFormat
        }
        let entries = try rawEntries.map(parseRawEntry)
        let rawAi = (dict["aiEntries"] as? [[String: Any]]) ?? []
        let aiEntries = try rawAi.map(parseRawAiEntry)
        let exportedAt = (dict["exportedAt"] as? String).flatMap(PortableDateCodec.parse)

        var missing = 0
        if !files.isEmpty {
            for entry in entries {
                for item in entry.media {
                    if files[item.sourcePath] == nil { missing += 1 }
                    if let motion = item.motionVideoMediaId, files[motion] == nil { missing += 1 }
                }
            }
        }
        return (entries, aiEntries, missing, exportedAt)
    }

    private func parseRawEntry(_ raw: [String: Any]) throws -> CapsuleEntry {
        guard let tsRaw = raw["timestamp"] as? String,
              let timestamp = PortableDateCodec.parse(tsRaw) else {
            throw BackupServiceError.unrecognizedFormat
        }
        let id = (raw["id"] as? String) ?? UUID().uuidString.lowercased()
        let content = (raw["content"] as? String) ?? ""
        let songInfo = (raw["songInfo"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let comments = parseComments(raw["comments"])

        var attachments: [MediaAttachment] = []
        if let rawMedia = raw["media"] as? [[String: Any]], !rawMedia.isEmpty {
            for m in rawMedia {
                if let path = (m["path"] as? String) ?? (m["mediaId"] as? String), !path.isEmpty {
                    let typeStr = (m["type"] as? String) ?? "image"
                    let type = MediaAttachmentType(rawValue: typeStr) ?? .image
                    let motionPath = (m["motionVideoPath"] as? String) ?? (m["motionVideoMediaId"] as? String)
                    attachments.append(
                        MediaAttachment(
                            id: (m["id"] as? String) ?? UUID().uuidString.lowercased(),
                            type: type,
                            mediaId: path,
                            motionVideoMediaId: (motionPath?.isEmpty == false) ? motionPath : nil,
                            legacySource: path
                        )
                    )
                }
            }
        } else {
            var images = (raw["imagePaths"] as? [String])?.filter { !$0.isEmpty } ?? []
            if let single = raw["imagePath"] as? String, !single.isEmpty, !images.contains(single) {
                images.insert(single, at: 0)
            }
            let videos = (raw["videoPaths"] as? [String])?.filter { !$0.isEmpty } ?? []
            for p in images {
                attachments.append(MediaAttachment(type: .image, mediaId: p, legacySource: p))
            }
            for v in videos {
                attachments.append(MediaAttachment(type: .video, mediaId: v, legacySource: v))
            }
        }

        return CapsuleEntry(
            id: id,
            content: content,
            timestamp: timestamp,
            songInfo: (songInfo?.isEmpty == false) ? songInfo : nil,
            media: attachments,
            comments: comments
        )
    }

    private func parseRawAiEntry(_ raw: [String: Any]) throws -> AiEntry {
        guard let question = raw["question"] as? String,
              let answer = raw["answer"] as? String,
              let tsRaw = raw["timestamp"] as? String,
              let timestamp = PortableDateCodec.parse(tsRaw) else {
            throw BackupServiceError.unrecognizedFormat
        }
        let id = (raw["id"] as? String) ?? UUID().uuidString.lowercased()
        let typeStr = (raw["type"] as? String) ?? "recall"
        let type = AiEntryType(rawValue: typeStr) ?? .recall
        return AiEntry(
            id: id,
            question: question,
            answer: answer,
            type: type,
            timestamp: timestamp,
            comments: parseComments(raw["comments"])
        )
    }

    private func parseComments(_ raw: Any?) -> [Comment] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { item in
            guard let text = item["text"] as? String,
                  let tsStr = item["timestamp"] as? String,
                  let ts = PortableDateCodec.parse(tsStr) else {
                return nil
            }
            return Comment(text: text, timestamp: ts)
        }
    }

    private func materializeMedia(
        for entries: [CapsuleEntry],
        mediaBytesByPortablePath: [String: Data]
    ) async throws -> (entries: [CapsuleEntry], mediaData: [String: Data], missingCount: Int) {
        var newIdByPath: [String: String] = [:]
        var mediaData: [String: Data] = [:]
        var missingCount = 0

        let rewrittenEntries: [CapsuleEntry] = entries.map { entry in
            var next = entry
            next.media = entry.media.compactMap { item in
                let source = item.sourcePath
                guard let mainBytes = mediaBytesByPortablePath[source] else {
                    missingCount += 1
                    return nil
                }
                let mainId: String
                if let existing = newIdByPath[source] {
                    mainId = existing
                } else {
                    let ext = MediaAttachment.fileExtension(for: item.mimeType, fallbackPath: source)
                    let generated = "media_\(UUID().uuidString.lowercased())\(ext)"
                    newIdByPath[source] = generated
                    mediaData[generated] = mainBytes
                    mainId = generated
                }

                var motionId: String? = nil
                var finalType = item.type
                if let motionSrc = item.motionVideoMediaId {
                    if let motionBytes = mediaBytesByPortablePath[motionSrc] {
                        if let existingM = newIdByPath[motionSrc] {
                            motionId = existingM
                        } else {
                            let generatedM = "motion_\(UUID().uuidString.lowercased()).mov"
                            newIdByPath[motionSrc] = generatedM
                            mediaData[generatedM] = motionBytes
                            motionId = generatedM
                        }
                    } else if finalType == .motionPhoto {
                        finalType = .image
                    }
                }

                return MediaAttachment(
                    id: item.id,
                    type: finalType,
                    mediaId: mainId,
                    motionVideoMediaId: motionId,
                    legacySource: nil,
                    mimeType: item.mimeType,
                    byteSize: Int64(mainBytes.count)
                )
            }
            return next
        }

        return (rewrittenEntries, mediaData, missingCount)
    }

    private func entryFingerprint(_ entry: CapsuleEntry) -> String {
        let ts = PortableDateCodec.format(entry.timestamp)
        let comments = entry.comments.map { "\($0.text)@\(PortableDateCodec.format($0.timestamp))" }.joined(separator: "|")
        let mediaTypes = entry.media.map { $0.type.portableTypeString }.joined(separator: ",")
        return "\(ts)::\(entry.content)::\(entry.songInfo ?? "")::\(comments)::\(mediaTypes)"
    }

    private func aiFingerprint(_ entry: AiEntry) -> String {
        let ts = PortableDateCodec.format(entry.timestamp)
        let comments = entry.comments.map { "\($0.text)@\(PortableDateCodec.format($0.timestamp))" }.joined(separator: "|")
        return "\(ts)::\(entry.type.rawValue)::\(entry.question)::\(entry.answer)::\(comments)"
    }
}
