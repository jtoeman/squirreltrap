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

    /// Gates the brief streak pulse when a submission extends the streak to
    /// a new day -- see PromptPanelViewModel.justExtendedStreak.
    @Published var celebrationEnabled: Bool {
        didSet { UserDefaults.standard.set(celebrationEnabled, forKey: Keys.celebrationEnabled) }
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
        static let reminderSyncDirection = "reminderSyncDirection"
        static let reminderSyncEveryNInvocations = "reminderSyncEveryNInvocations"
        static let reminderSyncListIdentifier = "reminderSyncListIdentifier"
        static let lastReminderSyncAt = "lastReminderSyncAt"
        static let snoozeUntil = "snoozeUntil"
        static let snoozeDurationMinutes = "snoozeDurationMinutes"
        static let autoSnoozeAfterEntry = "autoSnoozeAfterEntry"
        static let defaultAlarmEnabled = "defaultAlarmEnabled"
        static let defaultAlarmDurationSeconds = "defaultAlarmDurationSeconds"
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

        iCloudSyncEnabled = UserDefaults.standard.bool(forKey: Keys.iCloudSyncEnabled)
        hasSetUpCloudSync = UserDefaults.standard.bool(forKey: Keys.hasSetUpCloudSync)
        hasCreatedCloudSubscription = UserDefaults.standard.bool(forKey: Keys.hasCreatedCloudSubscription)
        lastCloudSyncAt = UserDefaults.standard.object(forKey: Keys.lastCloudSyncAt) as? Date
        lastUpdateCheckAt = UserDefaults.standard.object(forKey: Keys.lastUpdateCheckAt) as? Date
    }
}
