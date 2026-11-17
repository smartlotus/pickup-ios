import Foundation

public enum JournalFilter: String, Sendable, CaseIterable {
    case all
    case today
    case photos
    case reflections
    case pinned
}

public enum JournalValidationError: Error, Sendable, Equatable, LocalizedError {
    case emptyEntry

    public var errorDescription: String? {
        switch self {
        case .emptyEntry:
            return "Please write something or attach media before saving."
        }
    }
}

public struct JournalService: Sendable {
    public let repository: PickupRepository

    public init(repository: PickupRepository) {
        self.repository = repository
    }

    public static func filterEntries(
        _ entries: [CapsuleEntry],
        filter: JournalFilter,
        query: String,
        selectedTag: String? = nil,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [CapsuleEntry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        return entries.filter { entry in
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .today:
                matchesFilter = calendar.isDate(entry.timestamp, inSameDayAs: referenceDate)
            case .photos:
                matchesFilter = !entry.imagePaths.isEmpty
            case .reflections:
                matchesFilter = !entry.comments.isEmpty
            case .pinned:
                matchesFilter = entry.isPinned
            }
            guard matchesFilter else { return false }

            if let selectedTag, !selectedTag.isEmpty, !entry.tags.contains(selectedTag) {
                return false
            }

            guard !normalizedQuery.isEmpty else { return true }
            let searchableParts = [
                entry.content,
                entry.songInfo ?? "",
                entry.mood ?? "",
                entry.weather ?? "",
                entry.tags.joined(separator: " "),
                dateFormatter.string(from: entry.timestamp),
                entry.comments.map(\.text).joined(separator: " "),
            ]
            return searchableParts.joined(separator: " ").lowercased().contains(normalizedQuery)
        }
    }

    public static func dayCounts(
        for entries: [CapsuleEntry],
        inMonthOf monthDate: Date,
        calendar: Calendar = .current
    ) -> [Int: Int] {
        let targetComponents = calendar.dateComponents([.year, .month], from: monthDate)
        var counts: [Int: Int] = [:]
        for entry in entries {
            let comps = calendar.dateComponents([.year, .month, .day], from: entry.timestamp)
            if comps.year == targetComponents.year, comps.month == targetComponents.month, let day = comps.day {
                counts[day, default: 0] += 1
            }
        }
        return counts
    }

    public static func entriesOnDay(
        _ date: Date,
        from entries: [CapsuleEntry],
        calendar: Calendar = .current
    ) -> [CapsuleEntry] {
        entries.filter { calendar.isDate($0.timestamp, inSameDayAs: date) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Finds past entries on the exact same month/day from previous years OR same day from previous months ("往年今日 / 往月今日")
    public static func onThisDayMemories(
        referenceDate: Date = Date(),
        from entries: [CapsuleEntry],
        calendar: Calendar = .current
    ) -> [CapsuleEntry] {
        let ref = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        return entries.filter { entry in
            let comp = calendar.dateComponents([.year, .month, .day], from: entry.timestamp)
            guard let ey = comp.year, let ry = ref.year, let em = comp.month, let rm = ref.month, let ed = comp.day, let rd = ref.day else {
                return false
            }
            if ey == ry && em == rm && ed == rd {
                return false // exclude today itself
            }
            // Same month+day in past years, OR same day of month in previous months
            return (em == rm && ed == rd && ey < ry) || (ed == rd && (ey < ry || em < rm))
        }
        .sorted { $0.timestamp > $1.timestamp }
    }

    /// Calculates current consecutive-day journaling streak ending today or yesterday.
    public static func currentStreak(
        from entries: [CapsuleEntry],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        guard !entries.isEmpty else { return 0 }
        let uniqueDays = Set(entries.map { calendar.startOfDay(for: $0.timestamp) })
        let today = calendar.startOfDay(for: referenceDate)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            return uniqueDays.contains(today) ? 1 : 0
        }

        var cursor: Date?
        if uniqueDays.contains(today) {
            cursor = today
        } else if uniqueDays.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var streak = 0
        while let day = cursor, uniqueDays.contains(day) {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: day)
        }
        return streak
    }

    public func createEntry(
        content: String,
        songInfo: String?,
        media: [MediaAttachment],
        mood: String? = nil,
        weather: String? = nil,
        tags: [String] = [],
        isPinned: Bool = false,
        timestamp: Date = Date()
    ) async throws -> CapsuleEntry {
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanContent.isEmpty && media.isEmpty {
            throw JournalValidationError.emptyEntry
        }
        let cleanSong = songInfo?.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = CapsuleEntry(
            content: cleanContent,
            timestamp: timestamp,
            songInfo: (cleanSong?.isEmpty == false) ? cleanSong : nil,
            media: media,
            comments: [],
            mood: mood?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            weather: weather?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            tags: tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            isPinned: isPinned,
            updatedAt: timestamp
        )
        _ = try await repository.upsertEntry(entry)
        return entry
    }

    public func updateEntry(
        original: CapsuleEntry,
        content: String,
        songInfo: String?,
        media: [MediaAttachment],
        mood: String? = nil,
        weather: String? = nil,
        tags: [String] = [],
        isPinned: Bool? = nil
    ) async throws -> CapsuleEntry {
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanContent.isEmpty && media.isEmpty {
            throw JournalValidationError.emptyEntry
        }
        let cleanSong = songInfo?.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = original
        updated.content = cleanContent
        updated.songInfo = (cleanSong?.isEmpty == false) ? cleanSong : nil
        updated.media = media
        updated.mood = mood?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updated.weather = weather?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updated.tags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if let isPinned {
            updated.isPinned = isPinned
        }
        updated.updatedAt = Date()
        _ = try await repository.upsertEntry(updated)
        return updated
    }

    public func addReflection(to entry: CapsuleEntry, text: String, at timestamp: Date = Date()) async throws -> CapsuleEntry {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return entry }
        var updated = entry
        updated.comments.append(Comment(text: clean, timestamp: timestamp))
        updated.updatedAt = timestamp
        _ = try await repository.upsertEntry(updated)
        return updated
    }

    public func togglePin(_ entry: CapsuleEntry) async throws -> CapsuleEntry {
        var updated = entry
        updated.isPinned.toggle()
        updated.updatedAt = Date()
        _ = try await repository.upsertEntry(updated)
        return updated
    }

    public func deleteEntry(_ entry: CapsuleEntry) async throws {
        _ = try await repository.deleteEntry(id: entry.id)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
