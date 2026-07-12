import Foundation

@MainActor
final class PromptPanelViewModel: ObservableObject {
    @Published var draftText: String = ""
    @Published var focusToken = UUID()
    @Published var isShowingFavorites = false
    // Not persisted — only meaningful for the current panel session, set when a
    // reminder fires so the relevant row can call itself out visually.
    @Published var highlightedEntryID: UUID?

    let intentStore: IntentStore
    private let reminderScheduler: ReminderScheduler

    init(intentStore: IntentStore, reminderScheduler: ReminderScheduler) {
        self.intentStore = intentStore
        self.reminderScheduler = reminderScheduler
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
            intentStore.add(text: trimmed)
        }
        dismiss()
    }

    /// Logs a fresh copy of a favorited intent, then drops back to the normal
    /// list so the user immediately sees it land at the top.
    func repeatFavorite(_ entry: IntentEntry) {
        intentStore.add(text: entry.text)
        isShowingFavorites = false
    }
}
