import Foundation

public struct RevisitService: Sendable {
    public let repository: PickupRepository

    public init(repository: PickupRepository) {
        self.repository = repository
    }

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = String(format: "%04d", comps.year ?? 2026)
        let m = String(format: "%02d", comps.month ?? 1)
        let d = String(format: "%02d", comps.day ?? 1)
        return "\(y)-\(m)-\(d)"
    }

    public func dailyCandidate(date: Date = Date()) async throws -> CapsuleEntry? {
        let prefs = try await repository.loadPreferences()
        let key = Self.dayKey(for: date)
        if prefs.lastRevisitDateKey == key {
            return nil
        }
        return try await randomEntry(excludingId: nil)
    }

    public func markDailyPresented(date: Date = Date()) async throws {
        var prefs = try await repository.loadPreferences()
        prefs.lastRevisitDateKey = Self.dayKey(for: date)
        try await repository.savePreferences(prefs)
    }

    public func randomEntry(excludingId: String?) async throws -> CapsuleEntry? {
        let entries = try await repository.listEntries()
        guard !entries.isEmpty else { return nil }
        if entries.count == 1 { return entries.first }
        let pool = excludingId.map { ex in entries.filter { $0.id != ex } } ?? entries
        return (pool.isEmpty ? entries : pool).randomElement()
    }

    public func writeBackResponse(entry: CapsuleEntry, text: String, at timestamp: Date = Date()) async throws -> CapsuleEntry {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return entry }
        var updated = entry
        updated.comments.append(Comment(text: clean, timestamp: timestamp))
        updated.updatedAt = timestamp
        _ = try await repository.upsertEntry(updated)
        return updated
    }
}
