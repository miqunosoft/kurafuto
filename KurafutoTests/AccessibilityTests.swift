import XCTest
import SwiftUI
@testable import Kurafuto

/// WCAG 2.2 contrast checks for every text color the "Instrument" design puts on its surfaces.
@MainActor
final class AccessibilityTests: XCTestCase {
    /// Normal-size text (WCAG 2.2 AA, 1.4.3).
    private let minimum = 4.5
    /// The strongest tint of its own color that colored text sits on (status pills, tinted buttons, badges).
    private let maxTint = 0.16

    func testTextColorsMeetAAOnEveryBackground() {
        for mode in ThemeMode.allCases {
            let grounds = [("background", Palette.background(mode)), ("surface", Palette.surface(mode)),
                           ("sunken", Palette.sunken(mode))]
            var texts = [("primary", Palette.primaryText(mode)), ("secondary", Palette.secondaryText(mode)),
                         ("danger", Palette.danger(mode)), ("warning", Palette.warning(mode))]
            texts += AccentPreset.allCases.map { ($0.rawValue, $0.color(for: mode)) }
            for (text, color) in texts {
                for (ground, fill) in grounds {
                    let ratio = contrast(color, fill)
                    XCTAssertGreaterThanOrEqual(ratio, minimum, "\(text) on \(ground), \(mode): \(ratio)")
                }
            }
        }
    }

    func testColoredTextMeetsAAOnItsOwnTint() {
        for mode in ThemeMode.allCases {
            let colors = [("danger", Palette.danger(mode)), ("warning", Palette.warning(mode))]
                + AccentPreset.allCases.map { ($0.rawValue, $0.color(for: mode)) }
            for (name, color) in colors {
                for (ground, fill) in [("background", Palette.background(mode)), ("surface", Palette.surface(mode))] {
                    let ratio = contrast(color, blend(color, maxTint, over: fill))
                    XCTAssertGreaterThanOrEqual(ratio, minimum, "\(name) on its tint over \(ground), \(mode): \(ratio)")
                }
            }
        }
    }

    func testTextOnAccentFillsMeetsAA() {
        for mode in ThemeMode.allCases {
            for preset in AccentPreset.allCases {
                let ratio = contrast(Palette.onAccent(mode), preset.color(for: mode))
                XCTAssertGreaterThanOrEqual(ratio, minimum, "on \(preset.rawValue), \(mode): \(ratio)")
            }
        }
    }

    func testConsoleColorsMeetAA() {
        let colors = [("text", Theme.consoleText), ("warning", Theme.consoleWarning), ("error", Theme.consoleError)]
            + AccentPreset.allCases.map { ($0.rawValue, $0.color(for: .dark)) }
        for (name, color) in colors {
            let ratio = contrast(color, Theme.console)
            XCTAssertGreaterThanOrEqual(ratio, minimum, "\(name) on the console: \(ratio)")
        }
    }

    func testContrastFormulaMatchesKnownValues() {
        XCTAssertEqual(contrast(.black, .white), 21, accuracy: 0.01)
        XCTAssertEqual(contrast(Color(hex: 0x767676), .white), 4.54, accuracy: 0.01)
    }

    // MARK: WCAG helpers

    private func rgb(_ color: Color) -> (r: Double, g: Double, b: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    private func luminance(_ color: Color) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let c = rgb(color)
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// `color` at `opacity` over an opaque `ground`, as the screen shows it.
    private func blend(_ color: Color, _ opacity: Double, over ground: Color) -> Color {
        let (c, g) = (rgb(color), rgb(ground))
        return Color(red: c.r * opacity + g.r * (1 - opacity),
                     green: c.g * opacity + g.g * (1 - opacity),
                     blue: c.b * opacity + g.b * (1 - opacity))
    }
}
