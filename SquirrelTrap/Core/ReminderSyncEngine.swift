import EventKit
import Foundation

/// Syncs IntentStore with a single Apple Reminders list. Only ever runs when
/// explicitly invoked via sync() — no background polling, no
/// EKEventStoreChangedNotification observer. Scope is deliberately narrow:
/// title + completion status only (not due dates, favorites, or Squirrel
/// Trap's own in-app reminder timers, which are an unrelated concept).
@MainActor
final class ReminderSyncEngine: ObservableObject {
    @Published private(set) var isSyncing = false

    private let intentStore: IntentStore
    private let preferences: AppPreferences
    private let eventStore = EKEventStore()

    init(intentStore: IntentStore, preferences: AppPreferences) {
        self.intentStore = intentStore
        self.preferences = preferences
    }

    /// Every Reminders list available for picking in Preferences.
    func availableLists() -> [EKCalendar] {
        eventStore.calendars(for: .reminder)
    }

    func requestAccess() async -> Bool {
        do {
            return try await eventStore.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    func sync() async {
        let direction = preferences.reminderSyncDirection
        guard direction != .off else { return }
        guard let listID = preferences.reminderSyncListIdentifier,
              let calendar = eventStore.calendar(withIdentifier: listID) else { return }
        guard await requestAccess() else { return }

        isSyncing = true
        defer { isSyncing = false }

        let reminders = await fetchReminders(in: calendar)
        let remindersByID = Dictionary(uniqueKeysWithValues: reminders.map { ($0.calendarItemIdentifier, $0) })
        let lastSync = preferences.lastReminderSyncAt ?? .distantPast

        if direction.pullEnabled {
            pull(reminders: reminders, remindersByID: remindersByID, direction: direction, lastSync: lastSync)
        }
        if direction.pushEnabled {
            push(calendar: calendar, remindersByID: remindersByID, direction: direction, lastSync: lastSync)
        }

        preferences.lastReminderSyncAt = Date()
    }

    private func fetchReminders(in calendar: EKCalendar) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            let predicate = eventStore.predicateForReminders(in: [calendar])
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    /// New/changed Reminders flow into Squirrel Trap. Sync never deletes
    /// anything on either side (a first pull once wiped out a local list when
    /// a stale/incomplete fetch made linked entries look like their Reminder
    /// had vanished) — a Reminder disappearing has no effect on the local
    /// entry at all. isTombstoned still guards against re-creating an entry
    /// you deleted locally, since that's a creation-skip, not a deletion.
    private func pull(reminders: [EKReminder], remindersByID: [String: EKReminder], direction: ReminderSyncDirection, lastSync: Date) {
        let localEntries = intentStore.entries

        for reminder in reminders {
            let syncID = reminder.calendarItemIdentifier
            let remoteModified = reminder.lastModifiedDate ?? lastSync
            let remoteChanged = remoteModified > lastSync

            if let localEntry = localEntries.first(where: { $0.reminderSyncID == syncID }) {
                guard remoteChanged else { continue }
                if direction == .bidirectional {
                    let localChanged = localEntry.lastModifiedAt > lastSync
                    // Local wins ties and genuine conflicts alike — it'll be pushed out in push().
                    if localChanged && localEntry.lastModifiedAt >= remoteModified { continue }
                }
                intentStore.updateEntry(
                    withReminderSyncID: syncID,
                    text: reminder.title ?? localEntry.text,
                    completed: reminder.isCompleted,
                    modifiedAt: remoteModified
                )
            } else if !intentStore.isTombstoned(reminderSyncID: syncID) {
                intentStore.createEntry(
                    fromPulledReminderID: syncID,
                    text: reminder.title ?? "",
                    completed: reminder.isCompleted,
                    modifiedAt: remoteModified
                )
            }
        }
    }

    /// Local changes flow out to Reminders. Only pending (not-yet-completed)
    /// entries with no existing link get a brand-new Reminder created — an
    /// entry that's already completed and was never synced just isn't worth
    /// creating a reminder for after the fact.
    private func push(calendar: EKCalendar, remindersByID: [String: EKReminder], direction: ReminderSyncDirection, lastSync: Date) {
        // Re-read: pull may have just changed local state above.
        let currentEntries = intentStore.entries

        for entry in currentEntries {
            guard let syncID = entry.reminderSyncID else {
                guard !entry.completed else { continue }
                let reminder = EKReminder(eventStore: eventStore)
                reminder.calendar = calendar
                reminder.title = entry.text
                reminder.isCompleted = entry.completed
                try? eventStore.save(reminder, commit: false)
                intentStore.linkReminderSyncID(id: entry.id, reminderSyncID: reminder.calendarItemIdentifier)
                continue
            }

            guard let reminder = remindersByID[syncID] else { continue }
            guard entry.lastModifiedAt > lastSync else { continue }

            if direction == .bidirectional {
                let remoteModified = reminder.lastModifiedDate ?? lastSync
                let remoteChanged = remoteModified > lastSync
                if remoteChanged && remoteModified > entry.lastModifiedAt { continue } // remote won this one, already pulled above
            }

            reminder.title = entry.text
            reminder.isCompleted = entry.completed
            try? eventStore.save(reminder, commit: false)
        }

        try? eventStore.commit()
    }
}
