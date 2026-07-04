import Foundation

@MainActor
final class AppPreferences: ObservableObject {
    @Published var showMenuBarIcon: Bool {
        didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) }
    }

    private enum Keys {
        static let showMenuBarIcon = "showMenuBarIcon"
    }

    init() {
        if UserDefaults.standard.object(forKey: Keys.showMenuBarIcon) == nil {
            showMenuBarIcon = true
        } else {
            showMenuBarIcon = UserDefaults.standard.bool(forKey: Keys.showMenuBarIcon)
        }
    }
}
