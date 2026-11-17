import SwiftUI
import UIKit

/// One palette, resolved per appearance.
///
/// The ground is neutral black and bright cyan is the brand: the accent marks what is selected,
/// what is live, what was just copied. Everything else is ink on layered greys — near-white by
/// day, near-black at night — so a screens-worth of secrets still reads quietly. Cyan is spent
/// sparingly; a screen normally carries exactly one of it.
enum Theme {

    // MARK: - Accent

    /// Brand accent. Light appearance needs a deeper value to stay legible on paper; dark gets
    /// the bright cyan the mark is built from.
    static let accent = adaptive(light: UIColor(red: 0.043, green: 0.478, blue: 0.447, alpha: 1),  // #0B7A72
                                 dark: UIColor(red: 0.208, green: 0.882, blue: 0.815, alpha: 1))   // #35E1D0
    /// The literal brand cyan — glows, blooms and fills that never sit on paper.
    static let accentBright = Color(red: 0.208, green: 0.882, blue: 0.815)                          // #35E1D0
    static let accentDeep = Color(red: 0.027, green: 0.404, blue: 0.376)                            // #076760
    static let accentSoft = Color(red: 0.208, green: 0.882, blue: 0.815, opacity: 0.14)

    /// Ink that sits ON the bright gradient — white disappears on cyan, petrol does not.
    static let onAccent = Color(red: 0.016, green: 0.075, blue: 0.071)                              // #041312

    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.361, green: 0.937, blue: 0.878), Color(red: 0.051, green: 0.596, blue: 0.557)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: - Surfaces
    //
    // The ground is neutral black, not a tinted one: a page of secrets should read as ink on a
    // dark sheet, and a teal ground made everything look washed. Cyan is spent only where it
    // means something — see the accent above.

    static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static let background = adaptive(light: UIColor(red: 0.965, green: 0.965, blue: 0.969, alpha: 1),
                                     dark: UIColor(red: 0.024, green: 0.024, blue: 0.027, alpha: 1))
    static let backgroundGlow = adaptive(light: UIColor(red: 0.937, green: 0.937, blue: 0.945, alpha: 1),
                                         dark: UIColor(red: 0.086, green: 0.086, blue: 0.094, alpha: 1))
    /// Cards and list rows.
    static let surface = adaptive(light: .white,
                                  dark: UIColor(red: 0.078, green: 0.078, blue: 0.086, alpha: 1))
    /// A step above a card: value panels, insets, selected chips.
    static let surfaceRaised = adaptive(light: UIColor(red: 0.937, green: 0.937, blue: 0.945, alpha: 1),
                                        dark: UIColor(red: 0.110, green: 0.110, blue: 0.122, alpha: 1))
    static let surfaceDeep = adaptive(light: UIColor(red: 0.902, green: 0.902, blue: 0.914, alpha: 1),
                                      dark: UIColor(red: 0.043, green: 0.043, blue: 0.051, alpha: 1))

    // MARK: - Lines

    static let hairline = adaptive(light: UIColor(white: 0, alpha: 0.09),
                                   dark: UIColor(white: 1, alpha: 0.10))
    static let hairlineStrong = adaptive(light: UIColor(white: 0, alpha: 0.16),
                                         dark: UIColor(white: 1, alpha: 0.18))

    // MARK: - Ink
    // Light needs more ink than dark needs white: a grey that reads on black vanishes on paper.

    static let textPrimary = adaptive(light: UIColor(white: 0.07, alpha: 1),
                                      dark: UIColor(white: 1, alpha: 0.97))
    static let textSecondary = adaptive(light: UIColor(white: 0.07, alpha: 0.74),
                                        dark: UIColor(white: 1, alpha: 0.72))
    static let textTertiary = adaptive(light: UIColor(white: 0.07, alpha: 0.56),
                                       dark: UIColor(white: 1, alpha: 0.54))

    // MARK: - Semantics

    static let success = Color(red: 0.13, green: 0.70, blue: 0.42)
    static let warning = Color(red: 0.94, green: 0.62, blue: 0.06)
    static let danger = Color(red: 0.92, green: 0.29, blue: 0.29)

    // MARK: - Type
    //
    // One scale, used everywhere. Sizes step by ~1.2× from the title down to the caption, and
    // every icon box is sized against the text it sits beside — a 26 pt box next to a 15 pt title
    // reads smaller than a 42 pt badge next to a 16 pt one, which is exactly what made the
    // settings cards look wrong next to the vault cards.

    static let title = Font.system(size: 28, weight: .bold)
    static let heading = Font.system(size: 17.5, weight: .semibold)
    static let cardTitle = Font.system(size: 15.5, weight: .semibold)
    static let body = Font.system(size: 14.5, weight: .regular)
    static let bodyMedium = Font.system(size: 14.5, weight: .medium)
    static let callout = Font.system(size: 13, weight: .regular)
    static let label = Font.system(size: 12, weight: .semibold)
    static let caption = Font.system(size: 11, weight: .regular)
    static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)

    /// Icon boxes: the glyph is ~47% of the box, the box ~2× the text size beside it.
    enum IconSize {
        static let row: CGFloat = 30
        static let badge: CGFloat = 42
        static let hero: CGFloat = 54
    }

    // MARK: - Geometry

    enum Radius {
        /// Rows and tiles.
        static let card: CGFloat = 16
        /// Sheets, hero panels.
        static let panel: CGFloat = 24
        /// Controls whose shape identifies them.
        static let control: CGFloat = 12
        static let chip: CGFloat = 999
    }

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let s: CGFloat = 10
        static let m: CGFloat = 14
        static let l: CGFloat = 18
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 34
    }

    /// Screen-edge inset shared by headers, cards and footers.
    static let inset: CGFloat = 18

    // MARK: - Motion

    enum Motion {
        static let press = Animation.easeOut(duration: 0.16)
        static let snap = Animation.spring(response: 0.28, dampingFraction: 0.82)
        static let appear = Animation.spring(response: 0.42, dampingFraction: 0.86)
    }
}

// MARK: - Hex

extension Color {
    /// `Color(hex: "#35E1D0")` — also accepts a bare `35E1D0`.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
