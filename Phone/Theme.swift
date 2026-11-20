import SwiftUI
import UIKit

/// The web app's warm colors (web/src/style.css), light and dark.
enum Theme {
    static let ink = dynamic(0x3B2A23, 0xF3E6DC)
    static let muted = dynamic(0x6E554A, 0xC7B0A2)
    static let faint = dynamic(0x7A6156, 0xA8917F)
    /// The page.
    static let paper = dynamic(0xFFFBF6, 0x2A211D)
    /// Grouped lists and cards.
    static let field = dynamic(0xF8EFE6, 0x372C27)
    static let well = dynamic(0xF2E6DA, 0x40342E)
    static let link = dynamic(0xB83A4E, 0xF28C9B)
    /// Text on a `link`-filled button.
    static let onLink = dynamic(0xFFFFFF, 0x2A211D)
    static let heart = dynamic(0xE0596B, 0xEC6F80)
    static let heartSoft = dynamic(0xFDE3E6, 0x4A2B31)
    static let ok = dynamic(0x39744A, 0x8DCB9B)
    static let danger = dynamic(0xB3261E, 0xFF8A80)
    /// Behind something that can't be used: one's own link in «Добавить по ссылке».
    static let dangerSoft = dynamic(0xFCEAE8, 0x442E29)
    static let star = dynamic(0xD99A1E, 0xE8B54F)
    /// The pause row's moon.
    static let indigo = dynamic(0x6474D6, 0x939EEA)

    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Font {
    /// The system font, `size` points at the usual text size; follows the
    /// text size set in the iPhone's settings, up to a third bigger: beyond
    /// that the circles and rows, drawn for this size, would fall apart.
    static func app(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: min(UIFontMetrics.default.scaledValue(for: size), (size * 1.35).rounded()),
                weight: weight, design: design)
    }
}

/// A button that gives a little under the finger.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The wide rounded buttons of the sign-in screen and the sheets.
struct WideButton: ButtonStyle {
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.app(17, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(filled ? Theme.onLink : Theme.ink)
            .background(filled ? Theme.link : Theme.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
