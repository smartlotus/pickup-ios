import BackgroundTasks
import Foundation
import LocalAuthentication
import Observation
import PickupCore
import SwiftUI
import UIKit

public enum PickupTab: String, CaseIterable, Identifiable, Sendable {
    case journal
    case timeline
    case revisit
    case ai
    case data

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .journal: return "book.closed"
        case .timeline: return "calendar"
        case .revisit: return "sparkles"
        case .ai: return "brain.head.profile"
        case .data: return "externaldrive.badge.timemachine"
        }
    }

    public var selectedIcon: String {
        switch self {
        case .journal: return "book.closed.fill"
        case .timeline: return "calendar.circle.fill"
        case .revisit: return "sparkles"
        case .ai: return "brain.head.profile.fill"
        case .data: return "externaldrive.fill.badge.timemachine"
        }
    }
}

@MainActor
@Observable
public final class AppStore {
    public static let backgroundTaskIdentifier = "com.smartlotus.pickup.autobackup"

    public let repository: PickupRepository
    public let journalService: JournalService
    public let revisitService: RevisitService
    public let backupService: BackupService
    public let autoBackupEngine: AutoBackupEngine
    public let dataManagementService: DataManagementService
    public let aiHubService: AiHubService

    public var entries: [CapsuleEntry] = []
    public var aiEntries: [AiEntry] = []
    public var preferences: AppPreferences = AppPreferences()
    public var aiSettings: AiSettings = AiSettings()
    public var snapshots: [BackupSnapshotInfo] = []
    public var runLogs: [BackupRunLogEntry] = []
    public var storageBreakdown: StorageBreakdown?
    public var orphanScan: OrphanScanResult?

    public var selectedTab: PickupTab = .journal
    public var selectedEntryId: String?
    public var searchQuery: String = ""
    public var activeFilter: JournalFilter = .all
    public var selectedTag: String? = nil

    public var showLaunchIntro: Bool = true
    public var isLocked: Bool = false
    public var dailyRevisitSheetEntry: CapsuleEntry? = nil
    public var toastMessage: String? = nil
    public var isBusy: Bool = false

    private var changeBackupTask: Task<Void, Never>?

    public var palette: PickupPalette {
        PickupPalette.palette(for: preferences.themeStyle)
    }

    public var strings: PickupStrings {
        PickupStrings(preferences.language)
    }

    public var filteredEntries: [CapsuleEntry] {
        JournalService.filterEntries(
            entries,
            filter: activeFilter,
            query: searchQuery,
            selectedTag: selectedTag
        )
    }

    public var allTags: [String] {
        Array(Set(entries.flatMap(\.tags))).sorted()
    }

    public var streakDays: Int {
        JournalService.currentStreak(from: entries)
    }

    public var onThisDayEntries: [CapsuleEntry] {
        JournalService.onThisDayMemories(from: entries)
    }

    public init() {
        let repo = try! PickupRepository()
        self.repository = repo
        self.journalService = JournalService(repository: repo)
        self.revisitService = RevisitService(repository: repo)
        self.backupService = BackupService(repository: repo)
        self.autoBackupEngine = AutoBackupEngine(repository: repo)
        self.dataManagementService = DataManagementService(repository: repo)
        self.aiHubService = AiHubService(repository: repo)
    }

    public func bootstrap() async {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--demo-seed") {
            await seedDemoDataIfRequested(forceReset: true)
        }

        await reloadAll()

        if args.contains("--skip-intro") || preferences.skipLaunchIntro {
            showLaunchIntro = false
        }

        if let tabIdx = args.firstIndex(of: "--tab"), args.indices.contains(tabIdx + 1),
           let tab = PickupTab(rawValue: args[tabIdx + 1]) {
            selectedTab = tab
        }

        if let themeIdx = args.firstIndex(of: "--theme"), args.indices.contains(themeIdx + 1) {
            let val = args[themeIdx + 1]
            preferences.themeStyle = (val == "mono") ? .monochrome : .purpleDark
            try? await repository.savePreferences(preferences)
        }

        if preferences.isPassphraseLockEnabled || preferences.biometricLockEnabled {
            isLocked = !args.contains("--skip-intro")
        }

        await checkScheduledAutoBackup(trigger: .scheduled)
    }

    public func reloadAll() async {
        do {
            entries = try await repository.listEntries()
            aiEntries = try await repository.listAiEntries()
            preferences = try await repository.loadPreferences()
            aiSettings = await aiHubService.loadSettings()
            snapshots = try await autoBackupEngine.listSnapshots()
            runLogs = try await repository.loadBackupRunLog()
            storageBreakdown = try await dataManagementService.computeStorageBreakdown()
            orphanScan = try await dataManagementService.scanOrphansAndHealth()
            if selectedEntryId == nil {
                selectedEntryId = entries.first?.id
            }
        } catch {
            showToast("Failed to load local vault: \(error.localizedDescription)")
        }
    }

    public func updatePreferences(_ mutate: (inout AppPreferences) -> Void) async {
        mutate(&preferences)
        try? await repository.savePreferences(preferences)
    }

    // MARK: - Journal CRUD

    public func saveNewEntry(
        content: String,
        songInfo: String?,
        media: [MediaAttachment],
        mood: String?,
        weather: String?,
        tags: [String],
        isPinned: Bool
    ) async throws -> CapsuleEntry {
        let created = try await journalService.createEntry(
            content: content,
            songInfo: songInfo,
            media: media,
            mood: mood,
            weather: weather,
            tags: tags,
            isPinned: isPinned
        )
        try? await repository.clearDraft()
        await reloadAll()
        selectedEntryId = created.id
        scheduleBackupOnEntryChangeIfNeeded()
        return created
    }

    public func updateExistingEntry(
        original: CapsuleEntry,
        content: String,
        songInfo: String?,
        media: [MediaAttachment],
        mood: String?,
        weather: String?,
        tags: [String],
        isPinned: Bool?
    ) async throws -> CapsuleEntry {
        let updated = try await journalService.updateEntry(
            original: original,
            content: content,
            songInfo: songInfo,
            media: media,
            mood: mood,
            weather: weather,
            tags: tags,
            isPinned: isPinned
        )
        await reloadAll()
        scheduleBackupOnEntryChangeIfNeeded()
        return updated
    }

    public func addReflection(to entry: CapsuleEntry, text: String) async {
        do {
            _ = try await journalService.addReflection(to: entry, text: text)
            await reloadAll()
            scheduleBackupOnEntryChangeIfNeeded()
        } catch {
            showToast(error.localizedDescription)
        }
    }

    public func togglePin(entry: CapsuleEntry) async {
        do {
            _ = try await journalService.togglePin(entry)
            await reloadAll()
        } catch {
            showToast(error.localizedDescription)
        }
    }

    public func deleteEntry(_ entry: CapsuleEntry) async {
        do {
            try await journalService.deleteEntry(entry)
            if selectedEntryId == entry.id {
                selectedEntryId = nil
            }
            await reloadAll()
            scheduleBackupOnEntryChangeIfNeeded()
        } catch {
            showToast(error.localizedDescription)
        }
    }

    // MARK: - Media Persistence

    public func persistMedia(data: Data, fileExtension: String, type: MediaAttachmentType, motionVideoData: Data? = nil) async throws -> MediaAttachment {
        let id = "m_\(UUID().uuidString.lowercased()).\(fileExtension)"
        _ = try await repository.saveMedia(data: data, mediaId: id)
        var motionId: String? = nil
        if let motionVideoData {
            let mId = "mv_\(UUID().uuidString.lowercased()).mov"
            _ = try await repository.saveMedia(data: motionVideoData, mediaId: mId)
            motionId = mId
        }
        return MediaAttachment(
            type: type,
            mediaId: id,
            motionVideoMediaId: motionId,
            mimeType: MediaAttachment.defaultMimeType(for: type, path: id),
            byteSize: Int64(data.count + (motionVideoData?.count ?? 0))
        )
    }

    public func loadMediaData(mediaId: String) async -> Data? {
        try? await repository.loadMedia(mediaId: mediaId)
    }

    // MARK: - Daily Revisit

    public func checkDailyRevisitAfterLaunch() async {
        guard dailyRevisitSheetEntry == nil, !isLocked, !showLaunchIntro, preferences.tutorialCompleted else {
            return
        }
        if let candidate = try? await revisitService.dailyCandidate() {
            dailyRevisitSheetEntry = candidate
            try? await revisitService.markDailyPresented()
        }
    }

    // MARK: - Auto-Backup & External Bookmark

    public func resolveExternalFolderURL() -> URL? {
        guard let b64 = preferences.autoBackup.externalBookmarkBase64,
              let data = Data(base64Encoded: b64) else {
            return nil
        }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }
        if stale {
            if let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                preferences.autoBackup.externalBookmarkBase64 = refreshed.base64EncodedString()
                Task { try? await repository.savePreferences(preferences) }
            }
        }
        return url
    }

    public func setExternalBackupFolder(_ url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            await updatePreferences { prefs in
                prefs.autoBackup.externalFolderDisplayName = url.lastPathComponent
                prefs.autoBackup.externalBookmarkBase64 = bookmark.base64EncodedString()
            }
            showToast(preferences.language == .zh ? "已绑定外部备份目录：\(url.lastPathComponent)" : "External folder linked: \(url.lastPathComponent)")
        } catch {
            showToast("Bookmark failed: \(error.localizedDescription)")
        }
    }

    public func clearExternalBackupFolder() async {
        await updatePreferences { prefs in
            prefs.autoBackup.externalFolderDisplayName = nil
            prefs.autoBackup.externalBookmarkBase64 = nil
        }
    }

    public func runBackupNow(trigger: BackupTriggerKind = .manual, format: BackupFormatKind? = nil, passphrase: String? = nil) async -> BackupSnapshotInfo? {
        isBusy = true
        defer { isBusy = false }
        do {
            let extURL = resolveExternalFolderURL()
            let snap = try await autoBackupEngine.createSnapshot(
                trigger: trigger,
                format: format,
                includeMedia: preferences.autoBackup.includeMedia,
                passphrase: passphrase,
                externalFolderURL: extURL
            )
            await reloadAll()
            let msg = preferences.language == .zh
                ? "备份完成：\(snap.metadata.fileName)"
                : "Snapshot saved: \(snap.metadata.fileName)"
            showToast(msg)
            return snap
        } catch {
            showToast(error.localizedDescription)
            return nil
        }
    }

    public func checkScheduledAutoBackup(trigger: BackupTriggerKind = .scheduled) async {
        guard preferences.autoBackup.isEnabled else { return }
        let extURL = resolveExternalFolderURL()
        if trigger == .background && preferences.autoBackup.frequency == .onAppBackground {
            _ = try? await autoBackupEngine.createSnapshot(
                trigger: .background,
                format: .portableZip,
                includeMedia: preferences.autoBackup.includeMedia,
                externalFolderURL: extURL
            )
            await reloadAll()
            return
        }
        if let snap = try? await autoBackupEngine.runScheduledCheckIfNeeded(externalFolderURL: extURL) {
            await reloadAll()
            showToast(preferences.language == .zh ? "已完成定时自动备份：\(snap.metadata.fileName)" : "Auto-backup saved: \(snap.metadata.fileName)")
        }
    }

    private func scheduleBackupOnEntryChangeIfNeeded() {
        guard preferences.autoBackup.isEnabled, preferences.autoBackup.frequency == .onEntryChange else {
            return
        }
        changeBackupTask?.cancel()
        changeBackupTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            _ = await runBackupNow(trigger: .entryChange)
        }
    }

    public func scheduleBackgroundRefreshTask() {
        guard preferences.autoBackup.isEnabled, preferences.autoBackup.frequency != .manualOnly else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: preferences.autoBackup.frequency.timeInterval ?? 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Biometric Unlock

    public func attemptBiometricUnlock() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        do {
            let reason = preferences.language == .zh ? "解锁 Pickup 本地日记保险箱" : "Unlock your local Pickup journal vault"
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            if ok {
                isLocked = false
                await checkDailyRevisitAfterLaunch()
            }
            return ok
        } catch {
            return false
        }
    }

    public func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(3.2))
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    // MARK: - Rich Demo Seed (for Simulator screenshots & immediate tryout)

    public func seedDemoDataIfRequested(forceReset: Bool = false) async {
        let existing = (try? await repository.listEntries()) ?? []
        if !forceReset && !existing.isEmpty {
            return
        }
        let img1 = Self.renderArtworkPNG(
            topHex: 0x261B47,
            bottomHex: 0x0E0D15,
            accentHex: 0xA78BFA,
            title: "Evening Walk",
            subtitle: "19:42 · Corner Florist"
        )
        let img2 = Self.renderArtworkPNG(
            topHex: 0x2E191B,
            bottomHex: 0x100E12,
            accentHex: 0xF46862,
            title: "Window Sunlight",
            subtitle: "15:18 · Coffee & Pages"
        )

        let media1 = try? await persistMedia(data: img1, fileExtension: "png", type: .image)
        let media2 = try? await persistMedia(data: img2, fileExtension: "png", type: .motionPhoto, motionVideoData: Data("synthetic-motion-clip".utf8))

        let cal = Calendar.current
        let now = Date()
        let d0 = now.addingTimeInterval(-3600 * 2)
        let d1 = cal.date(byAdding: .day, value: -1, to: now) ?? now
        let d2 = cal.date(byAdding: .day, value: -3, to: now) ?? now
        let d3 = cal.date(byAdding: .day, value: -6, to: now) ?? now
        let dLastYear = cal.date(byAdding: .year, value: -1, to: now) ?? now

        let demoEntries: [CapsuleEntry] = [
            CapsuleEntry(
                id: "demo-1",
                content: "下班换了一条绕远的路。路过转角花店还亮着灯，挑了一束洋甘菊慢慢走回家。晚风把一天的紧绷都吹散了。",
                timestamp: d0,
                songInfo: "晚风 — 夜间电台",
                media: media1.map { [$0] } ?? [],
                comments: [Comment(text: "回头看，偶尔绕点远路是对的。", timestamp: d0.addingTimeInterval(1800))],
                mood: "松弛",
                weather: "微风 18°C",
                tags: ["散步", "花店"],
                isPinned: true
            ),
            CapsuleEntry(
                id: "demo-2",
                content: "在窗边读了几页书，咖啡渐渐凉掉，阳光从桌面这一头斜斜地移到了另一头。没有赶时间的一整个下午。",
                timestamp: d1,
                songInfo: "晴天 — Acoustic Demo",
                media: media2.map { [$0] } ?? [],
                comments: [Comment(text: "这一刻值得被红笔圈起来。", timestamp: d1.addingTimeInterval(7200))],
                mood: "平静",
                weather: "晴",
                tags: ["阅读", "咖啡"],
                isPinned: false
            ),
            CapsuleEntry(
                id: "demo-3",
                content: "和很久没联系的老朋友通了半小时电话。聊的都是琐碎小事，挂断后却觉得今晚格外充实。",
                timestamp: d2,
                songInfo: "夜航船 — Lo-Fi Mix",
                media: [],
                comments: [],
                mood: "温暖",
                weather: "多云",
                tags: ["朋友", "深夜"],
                isPinned: false
            ),
            CapsuleEntry(
                id: "demo-4",
                content: "凌晨两点下了一场急雨，打开阳台的窗听雨声敲在空调外机上，顺手记下这句：生活不必每页都波澜壮阔。",
                timestamp: d3,
                songInfo: "Rainy Taxi",
                media: [],
                comments: [],
                mood: "沉静",
                weather: "夜雨",
                tags: ["雨夜"],
                isPinned: false
            ),
            CapsuleEntry(
                id: "demo-last-year",
                content: "去年今日在海边吹风到日落，沙子灌满了帆布鞋。那时许愿说希望一年后还能保持对日常的敏感。",
                timestamp: dLastYear,
                songInfo: "Sea Glass",
                media: [],
                comments: [Comment(text: "一年后的今天，依然在好好拾起日子。", timestamp: now)],
                mood: "怀旧",
                weather: "海风",
                tags: ["海边", "往年今日"],
                isPinned: true
            ),
        ]

        let demoAi = [
            AiEntry(
                id: "demo-ai-1",
                question: "最近哪些瞬间让我觉得特别平静？",
                answer: "从最近的记录里看，让你感到平静的时刻几乎都带着「慢下来」的质感：绕远路买回家的洋甘菊、窗边咖啡渐凉的午后阅读，还有听着雨声写下的句子。你很擅长在这些微小片段里给自己留一处停靠点。",
                type: .recall,
                timestamp: d0.addingTimeInterval(-900),
                comments: [Comment(text: "说得真准。", timestamp: d0)]
            )
        ]

        try? await repository.saveEntries(demoEntries)
        try? await repository.saveAiEntries(demoAi)

        var prefs = try? await repository.loadPreferences()
        prefs?.tutorialCompleted = true
        prefs?.skipLaunchIntro = true
        prefs?.autoBackup.isEnabled = true
        prefs?.autoBackup.frequency = .daily
        prefs?.autoBackup.preferredHour = 22
        prefs?.autoBackup.preferredMinute = 30
        if let prefs {
            try? await repository.savePreferences(prefs)
        }

        _ = try? await autoBackupEngine.createSnapshot(trigger: .scheduled, isPinned: true, now: d1)
        _ = try? await autoBackupEngine.createSnapshot(trigger: .manual, now: d0)
    }

    private static func renderArtworkPNG(topHex: UInt32, bottomHex: UInt32, accentHex: UInt32, title: String, subtitle: String) -> Data {
        let size = CGSize(width: 960, height: 640)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let cs = CGColorSpaceCreateDeviceRGB()
            let c1 = UIColor(Color(hex: topHex)).cgColor
            let c2 = UIColor(Color(hex: bottomHex)).cgColor
            if let grad = CGGradient(colorsSpace: cs, colors: [c1, c2] as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(grad, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            // Subtle refractive orb
            cg.setFillColor(UIColor(Color(hex: accentHex, alpha: 0.25)).cgColor)
            cg.fillEllipse(in: CGRect(x: 560, y: 90, width: 320, height: 320))
            // Minimal mountain horizon lines
            cg.setStrokeColor(UIColor(Color(hex: 0xF4F3ED, alpha: 0.35)).cgColor)
            cg.setLineWidth(3)
            cg.move(to: CGPoint(x: 0, y: 460))
            cg.addCurve(to: CGPoint(x: 960, y: 420), control1: CGPoint(x: 310, y: 310), control2: CGPoint(x: 620, y: 520))
            cg.strokePath()

            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 38, weight: .semibold),
                .foregroundColor: UIColor(Color(hex: 0xF4F3ED)),
            ]
            let subAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .regular),
                .foregroundColor: UIColor(Color(hex: 0xA2A19A)),
            ]
            NSString(string: title).draw(at: CGPoint(x: 54, y: 54), withAttributes: titleAttr)
            NSString(string: subtitle).draw(at: CGPoint(x: 54, y: 108), withAttributes: subAttr)
        }
        return image.pngData() ?? Data()
    }
}
