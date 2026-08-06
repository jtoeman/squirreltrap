import Foundation

@MainActor
final class PromptPanelViewModel: ObservableObject {
    @Published var draftText: String = ""
    @Published var focusToken = UUID()
    @Published var isShowingFavorites = false
    // Not persisted — only meaningful for the current panel session, set when a
    // reminder fires so the relevant row can call itself out visually.
    @Published var highlightedEntryID: UUID?
    // Briefly true right when any task is completed -- drives the celebration
    // animation, then clears itself. Not persisted; a transient UI moment,
    // not state.
    @Published var isCelebrating = false

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

    /// Completing a task with an active alarm silences it -- there's nothing
    /// left to be reminded about. Celebrates every completion (not gated by
    /// streak/day logic); toggling a task back to incomplete never does.
    func toggleCompleted(id: UUID) {
        guard let entry = intentStore.entries.first(where: { $0.id == id }) else { return }
        let isCompleting = !entry.completed
        intentStore.toggleCompleted(id: id)
        guard isCompleting else { return }
        if entry.reminderDate != nil {
            cancelReminder(for: id)
        }
        if preferences.celebrationEnabled {
            isCelebrating = true
            Task {
                try? await Task.sleep(for: .seconds(celebrationDuration))
                isCelebrating = false
            }
        }
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
        let entry = intentStore.add(text: text)

        if preferences.defaultAlarmEnabled {
            setReminder(for: entry.id, duration: preferences.defaultAlarmDurationSeconds)
        }
        if preferences.autoSnoozeAfterEntry {
            preferences.snoozeUntil = Date().addingTimeInterval(preferences.snoozeDurationMinutes * 60)
            debugLog("Squirrel Trap DEBUG: [addEntry] auto-snooze set snoozeUntil=\(preferences.snoozeUntil!)\n")
        }
        return entry
    }

    #if DEBUG
    /// Re-fires the celebration on demand, without needing to actually
    /// complete a task.
    func previewCelebration() {
        isCelebrating = true
        Task {
            try? await Task.sleep(for: .seconds(celebrationDuration))
            isCelebrating = false
        }
    }
    #endif
}
