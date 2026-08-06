import Foundation

/// Pure, standalone streak/graph math over already-existing entry data
/// (createdAt for the streak, completedAt for the daily graph) -- no new
/// persisted or synced state. Since IntentEntry itself already syncs via
/// iCloud, deriving these from `entries` makes the streak automatically
/// correct across every Mac you use, with zero new sync code.
struct ActivityStats {
    /// One skipped day pauses the streak without resetting it; two
    /// consecutive skipped days reset it. Walks backward from today.
    static func streak(from entries: [IntentEntry], calendar: Calendar = .current) -> (current: Int, longest: Int) {
        let activeDays = Set(entries.map { calendar.startOfDay(for: $0.createdAt) })
        let current = currentStreak(activeDays: activeDays, today: calendar.startOfDay(for: Date()), calendar: calendar)
        let longest = longestStreak(activeDays: activeDays, calendar: calendar)
        return (current, longest)
    }

    private static func currentStreak(activeDays: Set<Date>, today: Date, calendar: Calendar) -> Int {
        var day = today
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

    /// Same one-grace-per-run rule, scanning every run across the whole
    /// history chronologically; grace resets when a run actually breaks.
    private static func longestStreak(activeDays: Set<Date>, calendar: Calendar) -> Int {
        guard !activeDays.isEmpty else { return 0 }
        let sorted = activeDays.sorted()
        var longest = 0
        var current = 0
        var graceRemaining = 1
        var previous: Date?
        for day in sorted {
            if let previous {
                let gapDays = calendar.dateComponents([.day], from: previous, to: day).day ?? 0
                if gapDays == 1 {
                    current += 1
                } else if gapDays == 2, graceRemaining > 0 {
                    graceRemaining -= 1
                    current += 1
                } else {
                    current = 1
                    graceRemaining = 1
                }
            } else {
                current = 1
            }
            longest = max(longest, current)
            previous = day
        }
        return longest
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
