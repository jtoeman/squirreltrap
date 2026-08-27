import AmplitudeSwift
import Foundation

/// Every event this app ever sends -- deliberately a closed list (not a raw
/// String at each call site) so "what does Squirrel Trap send to Amplitude"
/// is answerable by reading this one enum, not by grepping every call site.
enum AnalyticsEvent: String {
    case appLaunched = "App Launched"
    case appQuit = "App Quit"
    case onboardingCompleted = "Onboarding Completed"
    case panelOpened = "Panel Opened"
    case taskAdded = "Task Added"
    case taskCompleted = "Task Completed"
    case taskDeleted = "Task Deleted"
    case snoozed = "Snoozed"
    case coachTipShown = "Coach Tip Shown"
    case coachTipDismissed = "Coach Tip Dismissed"
    case preferencesTabOpened = "Preferences Tab Opened"
    /// Sent at most once per calendar day the app is running, regardless of
    /// any user interaction -- see AppDelegate.sendHeartbeatIfDue(). Exists
    /// specifically to tell apart "installed but not touching it" from
    /// "actually uninstalled": both look identical (total silence) without
    /// this, since macOS has no uninstall hook to observe directly.
    case dailyHeartbeat = "Daily Heartbeat"
}

/// Thin wrapper around the Amplitude client, gated entirely by
/// AppPreferences.analyticsEnabled (opt-in, asked once -- see
/// AnalyticsConsentPrompt). The client is created once at launch regardless
/// (Amplitude's SDK expects a single long-lived instance) but starts opted
/// out via Configuration.optOut, which suppresses all event upload at the
/// SDK level -- so call sites never need their own "if enabled" guard, and
/// nothing is ever sent before the user has said yes. autocapture is off
/// entirely (no sessions/screen views/element taps/network tracking): only
/// the curated events in AnalyticsEvent above are ever sent, so what leaves
/// the device is exactly what this file lists, nothing implicit.
@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()

    private let amplitude: Amplitude
    // Amplitude ingestion keys are write-only (they can only submit events,
    // never read data back), so embedding one in a client app -- open-source
    // repo included -- is the normal, supported way to use them.
    private let apiKey = "bda41837fad0bfd16296fd14dd5eae4c"

    private init() {
        amplitude = Amplitude(configuration: Configuration(
            apiKey: apiKey,
            optOut: true,
            autocapture: []
        ))
    }

    /// Mirrors AppPreferences.analyticsEnabled into the SDK -- call once at
    /// launch with the current value, then again on every change.
    func updateConsent(enabled: Bool) {
        amplitude.configuration.optOut = !enabled
    }

    func track(_ event: AnalyticsEvent, properties: [String: Any] = [:]) {
        amplitude.track(eventType: event.rawValue, eventProperties: properties)
    }

    /// Also flushes immediately, unlike every other track() call -- the app
    /// process exits right after this fires, so there's no later moment left
    /// for the SDK's normal background flush timer to run.
    func trackAppQuit() {
        amplitude.track(eventType: AnalyticsEvent.appQuit.rawValue, eventProperties: nil)
        amplitude.flush()
    }

    /// Lets adoption of each toggle be sliced in Amplitude without a
    /// dedicated event for every preference change -- e.g. "do Task
    /// Completed times differ between show_streak on vs off users."
    func updateUserProperties(preferences: AppPreferences) {
        let identify = Identify()
            .set(property: "show_streak", value: preferences.showStreak)
            .set(property: "celebration_enabled", value: preferences.celebrationEnabled)
            .set(property: "default_alarm_enabled", value: preferences.defaultAlarmEnabled)
            .set(property: "panel_theme", value: preferences.panelTheme.rawValue)
            .set(property: "show_tips", value: preferences.showTips)
            // Read fresh from the system rather than AppPreferences -- this
            // toggle lives in ServiceManagement, not in AppPreferences, so
            // there's no @Published to key a Combine subscription off. Cheap
            // enough to just re-read it every time this already gets called.
            .set(property: "launch_at_login_enabled", value: LaunchAtLoginManager.isEnabled)
        amplitude.identify(identify: identify)
    }
}
