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
    case npsShown = "NPS Shown"
    case npsSubmitted = "NPS Submitted"
    case npsDismissed = "NPS Dismissed"
    case npsPostponed = "NPS Postponed"
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

    /// A second, entirely separate Amplitude client, always opted in, used
    /// for exactly one thing: an NPS score the person submitted while
    /// general analytics sharing is off. Answering a specific question
    /// they're looking at is a deliberate act of consent for that one
    /// answer -- distinct from the blanket "share usage data" toggle -- but
    /// that consent covers only the answer itself, nothing else. Never
    /// route anything else through this client; a dedicated instance (vs.
    /// briefly toggling `amplitude.configuration.optOut` on the shared
    /// client) means there is no shared queue/buffer to worry about
    /// accidentally flushing anything this person hasn't agreed to.
    private let npsOnlyClient: Amplitude

    private init() {
        amplitude = Amplitude(configuration: Configuration(
            apiKey: apiKey,
            optOut: true,
            autocapture: []
        ))
        npsOnlyClient = Amplitude(configuration: Configuration(
            apiKey: apiKey,
            optOut: false,
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
            // The actual installed/running version -- without this there's no
            // way to see in Amplitude how far an update has actually
            // propagated (e.g. "how many people are still on 1.8.0 a week
            // after 1.8.1 shipped"), which is normally the single most
            // useful line on a distribution-health view.
            .set(property: "app_version", value: Self.appVersionString)
        amplitude.identify(identify: identify)
    }

    /// CFBundleShortVersionString -- the real shipped version (e.g. "1.8.1"),
    /// same in Debug and Release, unlike DebugBuildTag's "1.8.1c"-style
    /// testing label which only exists in Debug and is never what a
    /// distribution dashboard should be grouping by.
    private static var appVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// Sets the NPS score/category as user properties (for segmenting other
    /// behavior by response, e.g. "do Promoters complete more tasks") --
    /// separate from the Event tracked in NPSSubmitted, which carries the
    /// score plus the optional free-text reason. Call only when analytics is
    /// actually enabled -- see recordNPSResponseRegardlessOfConsent for the
    /// declined-analytics path.
    func recordNPSScore(_ score: Int) {
        let identify = Identify()
            .set(property: "nps_score", value: score)
            .set(property: "nps_category", value: npsCategory(for: score))
        amplitude.identify(identify: identify)
    }

    /// The declined-analytics counterpart to track(.npsSubmitted, ...) +
    /// recordNPSScore(_:) -- routes through npsOnlyClient instead of the
    /// main, opted-out client, and deliberately sends nothing beyond the
    /// score/feedback/category themselves: no app_version, no other user
    /// properties, nothing that wasn't specifically what this person just
    /// answered. Call only when preferences.analyticsEnabled is false; when
    /// it's true, the normal track(.npsSubmitted, ...) + recordNPSScore(_:)
    /// pair already covers it via the main client.
    func recordNPSResponseRegardlessOfConsent(score: Int, feedback: String?) {
        npsOnlyClient.track(eventType: AnalyticsEvent.npsSubmitted.rawValue, eventProperties: [
            "score": score,
            "feedback": feedback ?? ""
        ])
        let identify = Identify()
            .set(property: "nps_score", value: score)
            .set(property: "nps_category", value: npsCategory(for: score))
        npsOnlyClient.identify(identify: identify)
    }

    private func npsCategory(for score: Int) -> String {
        switch score {
        case 0...6: return "detractor"
        case 7...8: return "passive"
        default: return "promoter"
        }
    }
}
