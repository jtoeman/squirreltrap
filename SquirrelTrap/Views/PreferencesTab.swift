import Foundation

enum PreferencesTab: String, CaseIterable, Identifiable {
    case general
    case appearance
    case sync
    case activity

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .sync: return "Sync"
        case .activity: return "Activity"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .sync: return "arrow.triangle.2.circlepath"
        case .activity: return "chart.bar"
        }
    }
}
