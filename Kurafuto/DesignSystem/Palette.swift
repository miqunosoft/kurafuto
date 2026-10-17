import SwiftUI

// The "Instrument" palette without any app state, so the widget extension can draw the same look from the
// appearance the app hands over in its widget snapshot.

/// The three looks of the "Instrument" design. Gray and dark both use the system's dark scheme.
enum ThemeMode: String, CaseIterable, Identifiable {
    case dark, gray, light

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: String(localized: "Dark")
        case .gray: String(localized: "Gray")
        case .light: String(localized: "Light")
        }
    }

    var colorScheme: ColorScheme { self == .light ? .light : .dark }
}

/// Elements that carry their own accent color, chosen by the user in Settings.
enum AccentRole: String, CaseIterable, Identifiable {
    case accent, cpu, ram, players, storage

    var id: String { rawValue }

    var label: String {
        switch self {
        case .accent: String(localized: "Accent")
        case .cpu: String(localized: "CPU")
        case .ram: String(localized: "RAM")
        case .players: String(localized: "Players")
        case .storage: String(localized: "Storage")
        }
    }

    var symbol: String {
        switch self {
        case .accent: "paintbrush.pointed.fill"
        case .cpu: "cpu"
        case .ram: "memorychip"
        case .players: "person.2.fill"
        case .storage: "internaldrive"
        }
    }

    var defaultPreset: AccentPreset {
        switch self {
        case .accent, .cpu: .cyan
        case .ram: .violet
        case .players: .green
        case .storage: .amber
        }
    }
}

/// A fixed set of accent colors instead of a free color picker, so every choice keeps
/// readable contrast on all three backgrounds. Light mode uses a darker shade of each.
/// Every shade reaches WCAG AA (4.5:1) as text on the backgrounds and on a tint of itself up to 16 %
/// (`AccessibilityTests`); keep tints behind colored text at or below that.
enum AccentPreset: String, CaseIterable, Identifiable {
    case cyan, green, violet, amber, pink, blue, orange

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cyan: String(localized: "Cyan")
        case .green: String(localized: "Green")
        case .violet: String(localized: "Violet")
        case .amber: String(localized: "Amber")
        case .pink: String(localized: "Pink")
        case .blue: String(localized: "Blue")
        case .orange: String(localized: "Orange")
        }
    }

    func color(for mode: ThemeMode) -> Color {
        let hex: UInt32 = switch (self, mode == .light) {
        case (.cyan, false): 0x3DD9EB
        case (.cyan, true): 0x006A7B
        case (.green, false): 0x5BD27A
        case (.green, true): 0x186D35
        case (.violet, false): 0xAB9EFF
        case (.violet, true): 0x5B47D6
        case (.amber, false): 0xFFB547
        case (.amber, true): 0x8C5300
        case (.pink, false): 0xFF7DB9
        case (.pink, true): 0xB0144F
        case (.blue, false): 0x72AAFF
        case (.blue, true): 0x214EE6
        case (.orange, false): 0xFF8A4C
        case (.orange, true): 0xA33F00
        }
        return Color(hex: hex)
    }
}

/// Per-mode colors. `Theme` reads them for the mode the user picked.
enum Palette {
    static func background(_ mode: ThemeMode) -> Color {
        switch mode {
        case .dark: Color(hex: 0x0A0C0F)
        case .gray: Color(hex: 0x1C2026)
        case .light: Color(hex: 0xF2F4F6)
        }
    }

    static func surface(_ mode: ThemeMode) -> Color {
        switch mode {
        case .dark: Color(hex: 0x12161B)
        case .gray: Color(hex: 0x262B32)
        case .light: Color(hex: 0xFFFFFF)
        }
    }

    static func sunken(_ mode: ThemeMode) -> Color {
        switch mode {
        case .dark: Color(hex: 0x0D1014)
        case .gray: Color(hex: 0x20252B)
        case .light: Color(hex: 0xF4F6F8)
        }
    }

    static func stroke(_ mode: ThemeMode) -> Color {
        switch mode {
        case .dark: Color(hex: 0x252B33)
        case .gray: Color(hex: 0x363D46)
        case .light: Color(hex: 0xE1E5EA)
        }
    }

    static func divider(_ mode: ThemeMode) -> Color {
        switch mode {
        case .dark: Color(hex: 0x1E242B)
        case .gray: Color(hex: 0x2F353D)
        case .light: Color(hex: 0xE8EBEF)
        }
    }

    static func track(_ mode: ThemeMode) -> Color {
        switch mode {
        case .dark: Color(hex: 0x232930)
        case .gray: Color(hex: 0x353C45)
        case .light: Color(hex: 0xE4E8EC)
        }
    }

    static func primaryText(_ mode: ThemeMode) -> Color {
        mode == .light ? Color(hex: 0x0D0F12) : Color(hex: 0xEDEFF2)
    }

    static func secondaryText(_ mode: ThemeMode) -> Color {
        switch mode {
        case .dark: Color(hex: 0x8D96A1)
        case .gray: Color(hex: 0xA3ACB7)
        case .light: Color(hex: 0x5A626D)
        }
    }

    /// Text and icons placed on an accent fill.
    static func onAccent(_ mode: ThemeMode) -> Color { mode == .light ? .white : Color(hex: 0x0A0C0F) }

    static func danger(_ mode: ThemeMode) -> Color { mode == .light ? Color(hex: 0xB52525) : Color(hex: 0xFF8278) }
    static func warning(_ mode: ThemeMode) -> Color { AccentPreset.amber.color(for: mode) }

    static func color(for status: ServerStatus, mode: ThemeMode, accent: Color) -> Color {
        switch status {
        case .online: accent
        case .offline: secondaryText(mode)
        case .starting, .updating: warning(mode)
        case .crashed: danger(mode)
        }
    }
}

extension Font {
    /// Monospaced data font (SF Mono) that still follows Dynamic Type.
    static func mono(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
