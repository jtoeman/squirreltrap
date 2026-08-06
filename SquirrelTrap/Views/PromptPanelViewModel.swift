import Foundation

@MainActor
final class PromptPanelViewModel: ObservableObject {
    @Published var draftText: String = ""
    @Published var focusToken = UUID()
    @Published var isShowingFavorites = false
    // Not persisted — only meaningful for the current panel session, set when a
    // reminder fires so the relevant row can call itself out visually.
    @Published var highlightedEntryID: UUID?
    // Briefly true right when a submission extends the streak to a new day --
    // drives a one-second highlight on the streak line, then clears itself.
    // Not persisted; this is a transient celebration moment, not state.
    @Published var justExtendedStreak = false

    let intentStore: IntentStore
    private let reminderScheduler: ReminderScheduler
    private let preferences: AppPreferences

    init(intentStore: IntentStore, reminderScheduler: ReminderScheduler, preferences: AppPreferences) {
        self.intentStore = intentStore
        self.reminderScheduler = reminderScheduler
        self.preferences = preferences
    }

    func setReminder(for entryID: UUID, duration: TimeInterval) {
        let date = Date().addingTimeInterval(duration)
        intentStore.setReminder(id: entryID, date: date)
        reminderScheduler.schedule(for: entryID, at: date)
    }

    func cancelReminder(for entryID: UUID) {
        intentStore.setReminder(id: entryID, date: nil)
        reminderScheduler.cancel(for: entryID)
    }

    /// Called every time the panel is about to be shown: clears the draft, bumps
    /// focusToken so the text field reliably re-focuses even if the panel view's
    /// identity didn't change, and drops back out of favorites mode from any
    /// previous show. `entryID` carries a reminder-triggered highlight through;
    /// a normal Cmd+Tab show passes nil, clearing any highlight from before.
    func reset(highlighting entryID: UUID? = nil) {
        draftText = ""
        focusToken = UUID()
        isShowingFavorites = false
        highlightedEntryID = entryID
    }

    func submit(dismiss: () -> Void) {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            addEntryApplyingDefaultAlarm(text: trimmed)
        }
        dismiss()
    }

    /// Logs a fresh copy of a favorited intent, then drops back to the normal
    /// list so the user immediately sees it land at the top.
    func repeatFavorite(_ entry: IntentEntry) {
        addEntryApplyingDefaultAlarm(text: entry.text)
        isShowingFavorites = false
    }

    /// Shared by submit() and repeatFavorite() so "every new to-do gets a
    /// reminder" (Preferences' Default Alarm toggle) and "every new to-do also
    /// snoozes Cmd+Tab" (Auto-snooze after entry) only need implementing once,
    /// each independent of the other's state.
    @discardableResult
    private func addEntryApplyingDefaultAlarm(text: String) -> IntentEntry {
        // Checked before adding: is this the first submission of a new
        // streak day? (Not "did the streak number change" -- simpler and
        // exactly equivalent, since submitting is the only thing that can
        // extend it.)
        let today = Calendar.current.startOfDay(for: Date())
        let isFirstOfDay = !intentStore.entries.contains { Calendar.current.isDate($0.createdAt, inSameDayAs: today) }

        let entry = intentStore.add(text: text)

        if isFirstOfDay, preferences.celebrationEnabled {
            justExtendedStreak = true
            Task {
                try? await Task.sleep(for: .seconds(celebrationDuration))
                justExtendedStreak = false
            }
        }
        if preferences.defaultAlarmEnabled {
            setReminder(for: entry.id, duration: preferences.defaultAlarmDurationSeconds)
        }
        if preferences.autoSnoozeAfterEntry {
            preferences.snoozeUntil = Date().addingTimeInterval(preferences.snoozeDurationMinutes * 60)
            debugLog("Squirrel Trap DEBUG: [addEntry] auto-snooze set snoozeUntil=\(preferences.snoozeUntil!)\n")
        }
        return entry
    }
}
