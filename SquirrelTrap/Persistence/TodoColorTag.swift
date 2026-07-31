import SwiftUI

/// One of 16 preset color tags a to-do can be assigned, Trello-style (a
/// handful of hues, each in a light and dark shade) rather than free-form RGB.
enum TodoColorTag: String, CaseIterable, Codable {
    case green, lime, yellow, orange, red, pink, purple, blue
    case darkGreen, darkLime, darkYellow, darkOrange, darkRed, darkPink, darkPurple, darkBlue

    var color: Color {
        switch self {
        case .green:      return Color(red: 0x4B / 255, green: 0xCE / 255, blue: 0x97 / 255)
        case .lime:       return Color(red: 0x94 / 255, green: 0xC7 / 255, blue: 0x48 / 255)
        case .yellow:     return Color(red: 0xF5 / 255, green: 0xCD / 255, blue: 0x47 / 255)
        case .orange:     return Color(red: 0xFA / 255, green: 0xA5 / 255, blue: 0x3D / 255)
        case .red:        return Color(red: 0xF8 / 255, green: 0x71 / 255, blue: 0x68 / 255)
        case .pink:       return Color(red: 0xE7 / 255, green: 0x74 / 255, blue: 0xBB / 255)
        case .purple:     return Color(red: 0x9F / 255, green: 0x8F / 255, blue: 0xEF / 255)
        case .blue:       return Color(red: 0x57 / 255, green: 0x9D / 255, blue: 0xFF / 255)
        case .darkGreen:  return Color(red: 0x1F / 255, green: 0x84 / 255, blue: 0x5A / 255)
        case .darkLime:   return Color(red: 0x5B / 255, green: 0x7F / 255, blue: 0x24 / 255)
        case .darkYellow: return Color(red: 0x94 / 255, green: 0x6F / 255, blue: 0x00 / 255)
        case .darkOrange: return Color(red: 0xB9 / 255, green: 0x5A / 255, blue: 0x00 / 255)
        case .darkRed:    return Color(red: 0xC9 / 255, green: 0x37 / 255, blue: 0x2C / 255)
        case .darkPink:   return Color(red: 0xA9 / 255, green: 0x3A / 255, blue: 0x82 / 255)
        case .darkPurple: return Color(red: 0x6E / 255, green: 0x5D / 255, blue: 0xC6 / 255)
        case .darkBlue:   return Color(red: 0x0C / 255, green: 0x66 / 255, blue: 0xE4 / 255)
        }
    }
}
