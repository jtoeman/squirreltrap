import Foundation

/// Pure, standalone streak/graph math over already-existing entry data
/// (createdAt for the streak, completedAt for the daily graph) -- no new
/// persisted or synced state. Since IntentEntry itself already syncs via
/// iCloud, deriving these from `entries` makes the streak automatically
/// correct across every Mac you use, with zero new sync code.
struct ActivityStats {
    /// One skipped day pauses the streak without resetting it; two
    /// consecutive skipped days reset it. Walks backward from today.
    static func currentStreak(from entries: [IntentEntry], calendar: Calendar = .current) -> Int {
        let activeDays = Set(entries.map { calendar.startOfDay(for: $0.createdAt) })
        var day = calendar.startOfDay(for: Date())
        var streak = 0
        var graceRemaining = 1
        while true {
            if activeDays.contains(day) {
                streak += 1
            } else if graceRemaining > 0 {
                graceRemaining -= 1
            } else {
                break
            }
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    /// Zero-filled, oldest to newest, one entry per calendar day.
    static func completionCounts(from entries: [IntentEntry], lastDays: Int, calendar: Calendar = .current) -> [(date: Date, count: Int)] {
        let today = calendar.startOfDay(for: Date())
        let counts = Dictionary(
            grouping: entries.filter { $0.completed },
            by: { calendar.startOfDay(for: $0.completedAt ?? $0.createdAt) }
        ).mapValues(\.count)
        return (0..<lastDays).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            return (day, counts[day] ?? 0)
        }
    }
}
