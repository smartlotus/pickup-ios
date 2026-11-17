import Foundation
import Testing
@testable import PickupCore

@Suite("Journal, Timeline, Revisit & AI Disclosure Tests")
struct JournalRevisitAiTests {

    private func makeTempRepo() throws -> (PickupRepository, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pickup-journal-test-\(UUID().uuidString)", isDirectory: true)
        let repo = try PickupRepository(rootURL: dir)
        return (repo, dir)
    }

    @Test("Search, filter chips, calendar day counts, streak & On This Day")
    func journalQueriesAndCalendarMetrics() async throws {
        let (repo, dir) = try makeTempRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10))!
        let yesterday = cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 21))!
        let lastYearSameDay = cal.date(from: DateComponents(year: 2025, month: 11, day: 17, hour: 19))!

        let journal = JournalService(repository: repo)
        let e1 = try await journal.createEntry(
            content: "买了花慢慢走回家",
            songInfo: "晚风",
            media: [],
            mood: "平静",
            tags: ["散步"],
            isPinned: true,
            timestamp: today
        )
        _ = try await journal.createEntry(
            content: "雨夜听唱片",
            songInfo: "晴天",
            media: [MediaAttachment(type: .image, mediaId: "pic.jpg")],
            timestamp: yesterday
        )
        let old = try await journal.createEntry(
            content: "去年今日在海边看落日",
            songInfo: nil,
            media: [],
            timestamp: lastYearSameDay
        )
        _ = try await journal.addReflection(to: old, text: "今年又回来看了")

        let all = try await repo.listEntries()
        #expect(all.count == 3)
        #expect(JournalService.filterEntries(all, filter: .today, query: "", referenceDate: today, calendar: cal).map(\.id) == [e1.id])
        #expect(JournalService.filterEntries(all, filter: .pinned, query: "", referenceDate: today, calendar: cal).count == 1)
        #expect(JournalService.filterEntries(all, filter: .photos, query: "", referenceDate: today, calendar: cal).count == 1)
        #expect(JournalService.filterEntries(all, filter: .reflections, query: "", referenceDate: today, calendar: cal).count == 1)
        #expect(JournalService.filterEntries(all, filter: .all, query: "晚风", referenceDate: today, calendar: cal).count == 1)

        let counts = JournalService.dayCounts(for: all, inMonthOf: today, calendar: cal)
        #expect(counts[17] == 1)
        #expect(counts[16] == 1)

        let streak = JournalService.currentStreak(from: all, referenceDate: today, calendar: cal)
        #expect(streak == 2)

        let echo = JournalService.onThisDayMemories(referenceDate: today, from: all, calendar: cal)
        #expect(echo.count == 1)
        #expect(echo[0].id == old.id)
    }

    @Test("Revisit daily lock triggers once per day and writes back reflections")
    func revisitDailyLockAndWriteBack() async throws {
        let (repo, dir) = try makeTempRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        let journal = JournalService(repository: repo)
        _ = try await journal.createEntry(content: "微小的日常碎片", songInfo: nil, media: [])

        let revisit = RevisitService(repository: repo)
        let date = Date(timeIntervalSince1970: 1_763_370_000)
        let firstPick = try #require(try await revisit.dailyCandidate(date: date))
        try await revisit.markDailyPresented(date: date)

        // Second check on same day returns nil
        let secondPick = try await revisit.dailyCandidate(date: date)
        #expect(secondPick == nil)

        // Write back reflection updates underlying entry
        let updated = try await revisit.writeBackResponse(entry: firstPick, text: "回头看依然闪光")
        #expect(updated.comments.count == 1)
        #expect((try await repo.listEntries()).first?.comments.first?.text == "回头看依然闪光")
    }

    @Test("AI Hub disclosure builds text-only context with zero media bytes")
    func aiDisclosureNeverIncludesMedia() async throws {
        let entries = [
            CapsuleEntry(
                content: "今天在窗边看书，咖啡凉了。",
                timestamp: Date(),
                songInfo: "晴天",
                media: [MediaAttachment(type: .video, mediaId: "secret-video.mp4")],
                comments: [Comment(text: "很宁静")],
                mood: "松弛",
                tags: ["阅读"]
            )
        ]
        let preview = AiHubService.buildDisclosure(
            question: "最近哪些时刻让我平静？",
            scope: .intelligent,
            customStart: nil,
            customEnd: nil,
            entries: entries,
            providerName: "DeepSeek"
        )
        #expect(preview.mediaBytesIncluded == false)
        #expect(preview.recordCount == 1)
        #expect(preview.previewText.contains("今天在窗边看书"))
        #expect(!preview.previewText.contains("secret-video.mp4"))
    }
}
