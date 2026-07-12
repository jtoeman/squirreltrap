import Foundation

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

    private enum Keys {
        static let showMenuBarIcon = "showMenuBarIcon"
        static let inactivityTimeout = "inactivityTimeout"
        static let translucencyEnabled = "translucencyEnabled"
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
    }
}
