import AppKit
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
    // True only when this panel show was triggered by an actual Cmd+Tab (see
    // reset(viaSwitchGesture:)) -- gates whether submit() attributes a fresh
    // entry to the app you switched to. Deliberately read fresh at submit
    // time, not captured back at gesture-detection time: by the time you've
    // typed something and hit Enter, the OS's own app switch (which Squirrel
    // Trap's own non-activating panel never interferes with) has already
    // settled on the real destination, so NSWorkspace.frontmostApplication
    // at that moment reliably reflects where you actually ended up, not
    // wherever you started from.
    private var attributeSourceApp = false

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

    /// Same action as Preferences → General's "Clear Finished Items" --
    /// exposed here too for one-tap access right where completed items are
    /// actually visible, instead of only reachable from a different tab.
    /// Cancels any live reminder Timers for the removed entries the same way
    /// that button does, since IntentStore only owns the persisted data, not
    /// the scheduler.
    func clearCompletedEntries() {
        for id in intentStore.clearCompleted() {
            reminderScheduler.cancel(for: id)
        }
    }

    /// Completing a task with an active alarm silences it -- there's nothing
    /// left to be reminded about. Celebrates every completion (not gated by
    /// streak/day logic); toggling a task back to incomplete never does.
    func toggleCompleted(id: UUID) {
        guard let entry = intentStore.entries.first(where: { $0.id == id }) else { return }
        let isCompleting = !entry.completed
        intentStore.toggleCompleted(id: id)
        guard isCompleting else { return }
        AnalyticsService.shared.track(.taskCompleted, properties: [
            "time_since_created_seconds": Date().timeIntervalSince(entry.createdAt),
            "had_reminder": entry.reminderDate != nil,
        ])
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
        if isEligibleForNPSPrompt() {
            preferences.lastNPSPromptShownAt = Date()
            pendingNPSPrompt = true
            AnalyticsService.shared.track(.npsShown)
        }
    }

    /// True right after PromptPanelView should show the NPS prompt -- a
    /// one-shot trigger the View consumes and resets, same idea as
    /// focusToken, just boolean since only one can ever be queued at a time.
    @Published var pendingNPSPrompt = false

    /// Only ever true right after a task completion (see toggleCompleted) --
    /// not gated on panel-show count like CoachTip, since "just did
    /// something satisfying" is a deliberately better moment to ask than an
    /// arbitrary cold open. Every threshold here is about asking someone
    /// who's actually experienced the product, not a brand-new install:
    /// - opted into analytics at all (an NPS score is itself usage data;
    ///   asking despite a declined opt-out would run against what they
    ///   already told us)
    /// - at least 14 days past onboarding (nil onboardingCompletedAt, an
    ///   existing install from before this feature shipped, always counts
    ///   as "long past" -- it must never block someone who's been using
    ///   this for a year just because we don't know exactly when they
    ///   started)
    /// - at least 10 completed tasks ever, some real usage to have an
    ///   opinion about
    /// - hasn't been shown in the last 180 days, answered or not
    private func isEligibleForNPSPrompt() -> Bool {
        guard preferences.analyticsEnabled else { return false }
        let daysSinceOnboarding = preferences.onboardingCompletedAt
            .map { Date().timeIntervalSince($0) / 86400 } ?? .infinity
        guard daysSinceOnboarding >= 14 else { return false }
        guard intentStore.entries.filter({ $0.completed }).count >= 10 else { return false }
        if let lastShown = preferences.lastNPSPromptShownAt {
            guard Date().timeIntervalSince(lastShown) / 86400 >= 180 else { return false }
        }
        return true
    }

    func submitNPS(score: Int, feedback: String?) {
        AnalyticsService.shared.track(.npsSubmitted, properties: [
            "score": score,
            "feedback": feedback ?? ""
        ])
        AnalyticsService.shared.recordNPSScore(score)
    }

    func dismissNPSPrompt() {
        AnalyticsService.shared.track(.npsDismissed)
    }

    /// Called every time the panel is about to be shown: clears the draft, bumps
    /// focusToken so the text field reliably re-focuses even if the panel view's
    /// identity didn't change, and drops back out of favorites mode from any
    /// previous show. `entryID` carries a reminder-triggered highlight through;
    /// a normal Cmd+Tab show passes nil, clearing any highlight from before.
    func reset(highlighting entryID: UUID? = nil, viaSwitchGesture: Bool = false) {
        draftText = ""
        focusToken = UUID()
        isShowingFavorites = false
        highlightedEntryID = entryID
        attributeSourceApp = viaSwitchGesture
    }

    func submit(dismiss: () -> Void) {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            addEntryApplyingDefaultAlarm(text: trimmed, attributeSourceApp: attributeSourceApp)
        }
        dismiss()
    }

    /// Logs a fresh copy of a favorited intent, then drops back to the normal
    /// list so the user immediately sees it land at the top. Never attributed
    /// to a source app -- repeating a favorite isn't a Cmd+Tab-originated
    /// capture, it's just re-logging something you already had saved.
    func repeatFavorite(_ entry: IntentEntry) {
        addEntryApplyingDefaultAlarm(text: entry.text)
        isShowingFavorites = false
    }

    /// Shared by submit() and repeatFavorite() so "every new to-do gets a
    /// reminder" (Preferences' Default Alarm toggle), "every new to-do gets a
    /// color" (Default Color), and "every new to-do also snoozes Cmd+Tab"
    /// (Auto-snooze after entry) only need implementing once, each
    /// independent of the others' state.
    @discardableResult
    private func addEntryApplyingDefaultAlarm(text: String, attributeSourceApp: Bool = false) -> IntentEntry {
        var sourceAppName: String?
        var sourceAppBundleID: String?
        if attributeSourceApp, let frontmost = NSWorkspace.shared.frontmostApplication {
            sourceAppName = frontmost.localizedName
            sourceAppBundleID = frontmost.bundleIdentifier
        }
        let entry = intentStore.add(text: text, sourceAppName: sourceAppName, sourceAppBundleID: sourceAppBundleID)

        if let defaultColorTag = preferences.defaultColorTag {
            intentStore.setColor(id: entry.id, colorTag: defaultColorTag)
        }
        if preferences.defaultAlarmEnabled {
            setReminder(for: entry.id, duration: preferences.defaultAlarmDurationSeconds)
        }
        if preferences.autoSnoozeAfterEntry {
            preferences.snoozeUntil = Date().addingTimeInterval(preferences.snoozeDurationMinutes * 60)
            debugLog("Squirrel Trap DEBUG: [addEntry] auto-snooze set snoozeUntil=\(preferences.snoozeUntil!)\n")
        }
        AnalyticsService.shared.track(.taskAdded, properties: [
            "has_color_tag": preferences.defaultColorTag != nil,
            "has_reminder": preferences.defaultAlarmEnabled,
        ])
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
