import Foundation

/// One independent Timer per task, keyed by entry ID — this is what makes
/// multiple simultaneous reminders "just work" with no extra coordination.
@MainActor
final class ReminderScheduler {
    private var timers: [UUID: Timer] = [:]
    var onFire: ((UUID) -> Void)?

    func schedule(for entryID: UUID, at date: Date) {
        cancel(for: entryID)
        let interval = max(date.timeIntervalSinceNow, 0)
        timers[entryID] = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.fire(entryID)
            }
        }
    }

    func cancel(for entryID: UUID) {
        timers[entryID]?.invalidate()
        timers[entryID] = nil
    }

    private func fire(_ entryID: UUID) {
        timers[entryID] = nil
        onFire?(entryID)
    }

    /// Called once at launch: reminders scheduled before the app was quit don't
    /// have a live Timer anymore, so re-derive them from what's persisted —
    /// firing immediately for anything already past-due, rescheduling the rest.
    func restore(from entries: [IntentEntry]) {
        for entry in entries {
            guard let reminderDate = entry.reminderDate else { continue }
            schedule(for: entry.id, at: reminderDate)
        }
    }
}
