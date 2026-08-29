import CloudKit
import Foundation

enum ReminderSyncDirection: String, CaseIterable {
    case off
    case pushOnly
    case pullOnly
    case bidirectional

    var label: String {
        switch self {
        case .off: return "Off"
        case .pushOnly: return "Push to Reminders"
        case .pullOnly: return "Pull from Reminders"
        case .bidirectional: return "Both ways"
        }
    }

    var pushEnabled: Bool { self == .pushOnly || self == .bidirectional }
    var pullEnabled: Bool { self == .pullOnly || self == .bidirectional }
}

@MainActor
final class AppPreferences: ObservableObject {
    @Published var showMenuBarIcon: Bool {
        didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) }
    }

    /// How long the panel sits idle before it fades out and dismisses itself.
    @Published var inactivityTimeout: Double {
        didSet { UserDefaults.standard.set(inactivityTimeout, forKey: Keys.inactivityTimeout) }
    }

    /// An explicit in-app override, separate from the system-wide Reduce
    /// Transparency setting (which the panel already honors automatically via
    /// its NSVisualEffectView material). This lets someone turn off the blur
    /// just for this app without changing a systemwide accessibility setting.
    @Published var translucencyEnabled: Bool {
        didSet { UserDefaults.standard.set(translucencyEnabled, forKey: Keys.translucencyEnabled) }
    }

    /// Gates the brief celebration pulse fired on every task completion --
    /// see PromptPanelViewModel.isCelebrating.
    @Published var celebrationEnabled: Bool {
        didSet { UserDefaults.standard.set(celebrationEnabled, forKey: Keys.celebrationEnabled) }
    }

    /// Hides the "🔥 N days" streak segment on the main panel entirely when
    /// off -- today's completed count stays visible either way, since that's
    /// a plain fact, not the streak/gamification mechanic itself.
    @Published var showStreak: Bool {
        didSet { UserDefaults.standard.set(showStreak, forKey: Keys.showStreak) }
    }

    /// Opt-in, off by default for every install (fresh or existing) -- see
    /// AnalyticsConsentPrompt, shown once per hasAskedAnalyticsConsent below.
    /// Mirrored into AnalyticsService.shared.updateConsent(enabled:) so
    /// individual call sites never need their own "if enabled" guard.
    @Published var analyticsEnabled: Bool {
        didSet { UserDefaults.standard.set(analyticsEnabled, forKey: Keys.analyticsEnabled) }
    }

    /// Guards AnalyticsConsentPrompt to exactly once, ever, regardless of
    /// which way the user answers -- unlike onboarding/coach tips, a consent
    /// decision doesn't get re-asked or rotated back into view. Deliberately
    /// NOT exempted for existing installs the way other new gates are (see
    /// isExistingInstall below): consent has to actually be asked, not
    /// silently defaulted.
    @Published var hasAskedAnalyticsConsent: Bool {
        didSet { UserDefaults.standard.set(hasAskedAnalyticsConsent, forKey: Keys.hasAskedAnalyticsConsent) }
    }

    /// True once the first-run onboarding wizard has been completed -- see
    /// OnboardingView and PanelController.showOnboardingPanel(). Gates every
    /// normal entry point (Cmd+Tab, menu bar click, Cmd+,) until it's done,
    /// so it can't be bypassed, only postponed.
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    /// Stamped once, at the moment onboarding actually finishes -- see
    /// PanelController.showOnboardingPanel()'s onFinished. Nil for anyone who
    /// completed onboarding before this existed (an existing long-time
    /// install upgrading to this version); NPSPrompt's eligibility check
    /// treats nil as "a long time ago," never as "just now," so it never
    /// blocks NPS from ever showing for those users.
    @Published var onboardingCompletedAt: Date? {
        didSet { UserDefaults.standard.set(onboardingCompletedAt, forKey: Keys.onboardingCompletedAt) }
    }

    /// Set every time the NPS prompt is actually shown, whether or not the
    /// person answered it -- gates the re-prompt cooldown (see
    /// PromptPanelViewModel.isEligibleForNPSPrompt). A dismissal counts the
    /// same as an answer for this purpose: either way, asking again sooner
    /// than the cooldown is just annoying.
    @Published var lastNPSPromptShownAt: Date? {
        didSet { UserDefaults.standard.set(lastNPSPromptShownAt, forKey: Keys.lastNPSPromptShownAt) }
    }

    /// Counts every time the main prompt panel has been shown -- CoachTip's
    /// triggerCount values are checked against this. Bumped in
    /// PanelController.showPromptPanel(), never for Preferences/onboarding
    /// shows.
    @Published var totalPanelShows: Int {
        didSet { UserDefaults.standard.set(totalPanelShows, forKey: Keys.totalPanelShows) }
    }

    /// CoachTip.rawValues that have been individually dismissed ("Don't show
    /// this tip again") -- permanently excluded from the rotation. Reset
    /// (along with coachTipRotationIndex) by Preferences → Activity's
    /// "Reset All Tips" button.
    @Published var dismissedCoachTips: Set<String> {
        didSet { UserDefaults.standard.set(Array(dismissedCoachTips), forKey: Keys.dismissedCoachTips) }
    }

    /// How many tips have been shown so far -- picks the next one via
    /// `undismissedTips[coachTipRotationIndex % undismissedTips.count]` each
    /// time the every-4th-show checkpoint is reached, so the rotation keeps
    /// cycling through whatever's left rather than only ever showing each
    /// tip once.
    @Published var coachTipRotationIndex: Int {
        didSet { UserDefaults.standard.set(coachTipRotationIndex, forKey: Keys.coachTipRotationIndex) }
    }

    /// Master switch for the whole coach-tip rotation -- on by default
    /// (tips are meant to unveil real features), but some users just find
    /// any recurring popover annoying regardless of content. Independent of
    /// dismissedCoachTips: turning this off doesn't dismiss anything, it
    /// just stops checkForCoachTip from ever firing, so turning it back on
    /// resumes exactly where the rotation left off.
    @Published var showTips: Bool {
        didSet { UserDefaults.standard.set(showTips, forKey: Keys.showTips) }
    }

    @Published var reminderSyncDirection: ReminderSyncDirection {
        didSet { UserDefaults.standard.set(reminderSyncDirection.rawValue, forKey: Keys.reminderSyncDirection) }
    }

    /// Sync runs as a side effect of normal use — every Nth time the panel
    /// shows — rather than any background polling/observer.
    @Published var reminderSyncEveryNInvocations: Int {
        didSet { UserDefaults.standard.set(reminderSyncEveryNInvocations, forKey: Keys.reminderSyncEveryNInvocations) }
    }

    @Published var reminderSyncListIdentifier: String? {
        didSet { UserDefaults.standard.set(reminderSyncListIdentifier, forKey: Keys.reminderSyncListIdentifier) }
    }

    @Published var lastReminderSyncAt: Date? {
        didSet { UserDefaults.standard.set(lastReminderSyncAt, forKey: Keys.lastReminderSyncAt) }
    }

    /// The last calendar day a "Daily Heartbeat" analytics event was sent —
    /// see AnalyticsService/AppDelegate.sendHeartbeatIfDue(). Local-only,
    /// deliberately not synced: it's a per-device fact, not app data.
    @Published var lastHeartbeatSentAt: Date? {
        didSet { UserDefaults.standard.set(lastHeartbeatSentAt, forKey: Keys.lastHeartbeatSentAt) }
    }

    /// Non-nil while Cmd+Tab is suppressed — the menu bar icon and Cmd+,
    /// still work as usual and clicking the menu bar icon cancels it early.
    @Published var snoozeUntil: Date? {
        didSet { UserDefaults.standard.set(snoozeUntil, forKey: Keys.snoozeUntil) }
    }

    /// Last picked snooze duration, so the combo box remembers it like
    /// inactivityTimeout does.
    @Published var snoozeDurationMinutes: Double {
        didSet { UserDefaults.standard.set(snoozeDurationMinutes, forKey: Keys.snoozeDurationMinutes) }
    }

    /// When on, adding a to-do also snoozes Cmd+Tab for snoozeDurationMinutes —
    /// same effect as clicking Snooze by hand, just automatic.
    @Published var autoSnoozeAfterEntry: Bool {
        didSet { UserDefaults.standard.set(autoSnoozeAfterEntry, forKey: Keys.autoSnoozeAfterEntry) }
    }

    /// When on, every new to-do gets a reminder set automatically, using
    /// defaultAlarmDurationSeconds — same durations as the per-item alarm
    /// button (IntentRowView.reminderDurations).
    @Published var defaultAlarmEnabled: Bool {
        didSet { UserDefaults.standard.set(defaultAlarmEnabled, forKey: Keys.defaultAlarmEnabled) }
    }

    @Published var defaultAlarmDurationSeconds: TimeInterval {
        didSet { UserDefaults.standard.set(defaultAlarmDurationSeconds, forKey: Keys.defaultAlarmDurationSeconds) }
    }

    /// Applied automatically to every new to-do -- see
    /// PromptPanelViewModel.addEntryApplyingDefaultAlarm. nil means no
    /// default, the pre-existing behavior.
    @Published var defaultColorTag: TodoColorTag? {
        didSet { UserDefaults.standard.set(defaultColorTag?.rawValue, forKey: Keys.defaultColorTag) }
    }

    /// The panel's overall base/accent color pair (Preferences -> Appearance).
    /// Also mirrored into WidgetSnapshot so the desktop widget always matches.
    @Published var panelTheme: PanelTheme {
        didSet { UserDefaults.standard.set(panelTheme.rawValue, forKey: Keys.panelTheme) }
    }

    /// Opt-in, off by default — single-Mac users don't need this.
    @Published var iCloudSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(iCloudSyncEnabled, forKey: Keys.iCloudSyncEnabled) }
    }

    /// Guards one-time custom-zone creation so it isn't repeated every sync.
    /// Actual pull/push only requires the zone -- see hasCreatedCloudSubscription
    /// for the separate (best-effort, non-blocking) push-subscription flag.
    @Published var hasSetUpCloudSync: Bool {
        didSet { UserDefaults.standard.set(hasSetUpCloudSync, forKey: Keys.hasSetUpCloudSync) }
    }

    /// Guards one-time push-subscription creation, tracked separately from
    /// the zone flag above: the subscription only enables near-instant push
    /// triggering, so a failure here must never block actual data sync (which
    /// only needs the zone) -- previously both were gated behind a single
    /// flag, so a subscription failure silently turned every future sync()
    /// call into a permanent no-op.
    @Published var hasCreatedCloudSubscription: Bool {
        didSet { UserDefaults.standard.set(hasCreatedCloudSubscription, forKey: Keys.hasCreatedCloudSubscription) }
    }

    @Published var lastCloudSyncAt: Date? {
        didSet { UserDefaults.standard.set(lastCloudSyncAt, forKey: Keys.lastCloudSyncAt) }
    }

    /// Throttles UpdateChecker to at most once a day — it's cheap to call on
    /// every launch and panel show, but there's no reason to actually hit
    /// GitHub's API that often.
    @Published var lastUpdateCheckAt: Date? {
        didSet { UserDefaults.standard.set(lastUpdateCheckAt, forKey: Keys.lastUpdateCheckAt) }
    }

    /// CKServerChangeToken is NSSecureCoding, not Codable, so it's
    /// archived/unarchived through Data for UserDefaults storage. Not
    /// @Published — pure sync-engine bookkeeping, nothing in the UI observes it.
    var cloudChangeToken: CKServerChangeToken? {
        get {
            guard let data = UserDefaults.standard.data(forKey: Keys.cloudChangeToken) else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
        }
        set {
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: Keys.cloudChangeToken)
                return
            }
            let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: Keys.cloudChangeToken)
        }
    }

    private enum Keys {
        static let showMenuBarIcon = "showMenuBarIcon"
        static let inactivityTimeout = "inactivityTimeout"
        static let translucencyEnabled = "translucencyEnabled"
        static let celebrationEnabled = "celebrationEnabled"
        static let showStreak = "showStreak"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let onboardingCompletedAt = "onboardingCompletedAt"
        static let lastNPSPromptShownAt = "lastNPSPromptShownAt"
        static let totalPanelShows = "totalPanelShows"
        static let dismissedCoachTips = "dismissedCoachTips"
        static let coachTipRotationIndex = "coachTipRotationIndex"
        static let showTips = "showTips"
        static let reminderSyncDirection = "reminderSyncDirection"
        static let reminderSyncEveryNInvocations = "reminderSyncEveryNInvocations"
        static let reminderSyncListIdentifier = "reminderSyncListIdentifier"
        static let lastReminderSyncAt = "lastReminderSyncAt"
        static let lastHeartbeatSentAt = "lastHeartbeatSentAt"
        static let snoozeUntil = "snoozeUntil"
        static let snoozeDurationMinutes = "snoozeDurationMinutes"
        static let autoSnoozeAfterEntry = "autoSnoozeAfterEntry"
        static let defaultAlarmEnabled = "defaultAlarmEnabled"
        static let defaultAlarmDurationSeconds = "defaultAlarmDurationSeconds"
        static let defaultColorTag = "defaultColorTag"
        static let panelTheme = "panelTheme"
        static let analyticsEnabled = "analyticsEnabled"
        static let hasAskedAnalyticsConsent = "hasAskedAnalyticsConsent"
        static let iCloudSyncEnabled = "iCloudSyncEnabled"
        static let hasSetUpCloudSync = "hasSetUpCloudSync"
        static let hasCreatedCloudSubscription = "hasCreatedCloudSubscription"
        static let lastCloudSyncAt = "lastCloudSyncAt"
        static let cloudChangeToken = "cloudChangeToken"
        static let lastUpdateCheckAt = "lastUpdateCheckAt"
    }

    init() {
        if UserDefaults.standard.object(forKey: Keys.showMenuBarIcon) == nil {
            showMenuBarIcon = true
        } else {
            showMenuBarIcon = UserDefaults.standard.bool(forKey: Keys.showMenuBarIcon)
        }

        if UserDefaults.standard.object(forKey: Keys.inactivityTimeout) == nil {
            inactivityTimeout = 7
        } else {
            inactivityTimeout = UserDefaults.standard.double(forKey: Keys.inactivityTimeout)
        }

        if UserDefaults.standard.object(forKey: Keys.translucencyEnabled) == nil {
            translucencyEnabled = true
        } else {
            translucencyEnabled = UserDefaults.standard.bool(forKey: Keys.translucencyEnabled)
        }

        if UserDefaults.standard.object(forKey: Keys.celebrationEnabled) == nil {
            celebrationEnabled = true
        } else {
            celebrationEnabled = UserDefaults.standard.bool(forKey: Keys.celebrationEnabled)
        }

        if UserDefaults.standard.object(forKey: Keys.showStreak) == nil {
            showStreak = true
        } else {
            showStreak = UserDefaults.standard.bool(forKey: Keys.showStreak)
        }

        // A genuinely fresh install has no preferences at all yet --
        // showMenuBarIcon has existed since v1.0, so its presence means this
        // Mac has run Squirrel Trap before onboarding/coach tips existed.
        // Those installs should never be forced through either retroactively.
        let isExistingInstall = UserDefaults.standard.object(forKey: Keys.showMenuBarIcon) != nil

        if UserDefaults.standard.object(forKey: Keys.hasCompletedOnboarding) == nil {
            hasCompletedOnboarding = isExistingInstall
        } else {
            hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding)
        }

        if UserDefaults.standard.object(forKey: Keys.totalPanelShows) == nil {
            totalPanelShows = isExistingInstall ? 1000 : 0
        } else {
            totalPanelShows = UserDefaults.standard.integer(forKey: Keys.totalPanelShows)
        }

        if let stored = UserDefaults.standard.array(forKey: Keys.dismissedCoachTips) as? [String] {
            dismissedCoachTips = Set(stored)
        } else if isExistingInstall {
            // The rotation cycles indefinitely (unlike a one-shot trigger
            // count), so starting totalPanelShows past the first checkpoint
            // isn't enough on its own to keep tips from eventually reaching
            // an existing install -- pre-dismissing every tip that exists as
            // of this build is. A genuinely new CoachTip case added in a
            // later version will still reach existing installs normally,
            // since by then this key already exists and this branch won't
            // run again.
            dismissedCoachTips = Set(CoachTip.allCases.map(\.rawValue))
        } else {
            dismissedCoachTips = []
        }

        coachTipRotationIndex = UserDefaults.standard.integer(forKey: Keys.coachTipRotationIndex)
        if UserDefaults.standard.object(forKey: Keys.showTips) == nil {
            showTips = true
        } else {
            showTips = UserDefaults.standard.bool(forKey: Keys.showTips)
        }

        if let rawValue = UserDefaults.standard.string(forKey: Keys.reminderSyncDirection),
           let direction = ReminderSyncDirection(rawValue: rawValue) {
            reminderSyncDirection = direction
        } else {
            reminderSyncDirection = .off
        }

        if UserDefaults.standard.object(forKey: Keys.reminderSyncEveryNInvocations) == nil {
            reminderSyncEveryNInvocations = 5
        } else {
            reminderSyncEveryNInvocations = UserDefaults.standard.integer(forKey: Keys.reminderSyncEveryNInvocations)
        }

        reminderSyncListIdentifier = UserDefaults.standard.string(forKey: Keys.reminderSyncListIdentifier)
        lastReminderSyncAt = UserDefaults.standard.object(forKey: Keys.lastReminderSyncAt) as? Date
        lastHeartbeatSentAt = UserDefaults.standard.object(forKey: Keys.lastHeartbeatSentAt) as? Date
        onboardingCompletedAt = UserDefaults.standard.object(forKey: Keys.onboardingCompletedAt) as? Date
        lastNPSPromptShownAt = UserDefaults.standard.object(forKey: Keys.lastNPSPromptShownAt) as? Date

        snoozeUntil = UserDefaults.standard.object(forKey: Keys.snoozeUntil) as? Date

        if UserDefaults.standard.object(forKey: Keys.snoozeDurationMinutes) == nil {
            snoozeDurationMinutes = 15
        } else {
            snoozeDurationMinutes = UserDefaults.standard.double(forKey: Keys.snoozeDurationMinutes)
        }

        autoSnoozeAfterEntry = UserDefaults.standard.bool(forKey: Keys.autoSnoozeAfterEntry)

        defaultAlarmEnabled = UserDefaults.standard.bool(forKey: Keys.defaultAlarmEnabled)
        if UserDefaults.standard.object(forKey: Keys.defaultAlarmDurationSeconds) == nil {
            defaultAlarmDurationSeconds = 10 * 60
        } else {
            defaultAlarmDurationSeconds = UserDefaults.standard.double(forKey: Keys.defaultAlarmDurationSeconds)
        }

        defaultColorTag = UserDefaults.standard.string(forKey: Keys.defaultColorTag).flatMap(TodoColorTag.init(rawValue:))
        panelTheme = UserDefaults.standard.string(forKey: Keys.panelTheme).flatMap(PanelTheme.init(rawValue:)) ?? .blue
        analyticsEnabled = UserDefaults.standard.bool(forKey: Keys.analyticsEnabled)
        hasAskedAnalyticsConsent = UserDefaults.standard.bool(forKey: Keys.hasAskedAnalyticsConsent)

        iCloudSyncEnabled = UserDefaults.standard.bool(forKey: Keys.iCloudSyncEnabled)
        hasSetUpCloudSync = UserDefaults.standard.bool(forKey: Keys.hasSetUpCloudSync)
        hasCreatedCloudSubscription = UserDefaults.standard.bool(forKey: Keys.hasCreatedCloudSubscription)
        lastCloudSyncAt = UserDefaults.standard.object(forKey: Keys.lastCloudSyncAt) as? Date
        lastUpdateCheckAt = UserDefaults.standard.object(forKey: Keys.lastUpdateCheckAt) as? Date
    }
}
