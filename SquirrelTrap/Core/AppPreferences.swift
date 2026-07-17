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

    private enum Keys {
        static let showMenuBarIcon = "showMenuBarIcon"
        static let inactivityTimeout = "inactivityTimeout"
        static let translucencyEnabled = "translucencyEnabled"
        static let reminderSyncDirection = "reminderSyncDirection"
        static let reminderSyncEveryNInvocations = "reminderSyncEveryNInvocations"
        static let reminderSyncListIdentifier = "reminderSyncListIdentifier"
        static let lastReminderSyncAt = "lastReminderSyncAt"
        static let snoozeUntil = "snoozeUntil"
        static let snoozeDurationMinutes = "snoozeDurationMinutes"
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
    }
}
