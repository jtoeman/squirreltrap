import Foundation

enum PreferencesTab: String, CaseIterable, Identifiable {
    case general
    case appearance
    case sync

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .sync: return "Sync"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .sync: return "arrow.triangle.2.circlepath"
        }
    }
}
