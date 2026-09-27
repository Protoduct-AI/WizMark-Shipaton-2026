import SwiftUI

// MARK: - Hex Initializer

extension Color {

    /// Initialize a `Color` from a hex string.
    ///
    /// Accepts 3-, 4-, 6-, and 8-character hex values, with or without a leading `#`.
    ///
    /// ```swift
    /// Color(hex: "#3B6EF6")
    /// Color(hex: "3B6EF6")
    /// Color(hex: "F00")        // short form
    /// Color(hex: "3B6EF680")   // with alpha
    /// ```
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)

        let r: Double
        let g: Double
        let b: Double
        let a: Double

        switch cleaned.count {
        case 3: // RGB (4-bit per channel)
            r = Double((rgb >> 8) & 0xF) / 15
            g = Double((rgb >> 4) & 0xF) / 15
            b = Double(rgb & 0xF) / 15
            a = 1
        case 4: // RGBA (4-bit per channel)
            r = Double((rgb >> 12) & 0xF) / 15
            g = Double((rgb >> 8) & 0xF) / 15
            b = Double((rgb >> 4) & 0xF) / 15
            a = Double(rgb & 0xF) / 15
        case 6: // RRGGBB
            r = Double((rgb >> 16) & 0xFF) / 255
            g = Double((rgb >> 8) & 0xFF) / 255
            b = Double(rgb & 0xFF) / 255
            a = 1
        case 8: // RRGGBBAA
            r = Double((rgb >> 24) & 0xFF) / 255
            g = Double((rgb >> 16) & 0xFF) / 255
            b = Double((rgb >> 8) & 0xFF) / 255
            a = Double(rgb & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0; a = 1
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Semantic Accessors

extension Color {

    // MARK: Backgrounds

    /// Primary background.
    static var wizmarkBackground: Color { ColorTokens.background }

    /// Elevated surface (cards, sheets).
    static var wizmarkSurface: Color { ColorTokens.surface }

    /// Secondary surface (grouped rows, subtle cards).
    static var wizmarkSurfaceVariant: Color { ColorTokens.surfaceVariant }

    /// Tertiary surface (segment controls, etc.).
    static var wizmarkSurfaceTertiary: Color { ColorTokens.surfaceTertiary }

    // MARK: Text

    /// Primary text.
    static var wizmarkText: Color { ColorTokens.text }

    /// Secondary / caption text.
    static var wizmarkTextSecondary: Color { ColorTokens.textSecondary }

    /// Muted / placeholder text.
    static var wizmarkTextMuted: Color { ColorTokens.textMuted }

    // MARK: Accent

    /// Primary accent blue.
    static var wizmarkAccent: Color { ColorTokens.accent }

    /// Secondary accent purple.
    static var wizmarkAccentSecondary: Color { ColorTokens.accentSecondary }

    // MARK: Status

    /// Success green.
    static var wizmarkSuccess: Color { ColorTokens.success }

    /// Warning amber.
    static var wizmarkWarning: Color { ColorTokens.warning }

    /// Error / danger red.
    static var wizmarkError: Color { ColorTokens.error }

    // MARK: Chrome

    /// Border color.
    static var wizmarkBorder: Color { ColorTokens.border }

    /// Separator / divider color.
    static var wizmarkSeparator: Color { ColorTokens.separator }

    /// Form field background.
    static var wizmarkFieldBackground: Color { ColorTokens.fieldBackground }

    /// Overlay backdrop.
    static var wizmarkOverlay: Color { ColorTokens.overlay }

    // MARK: Effects

    /// Shimmer / skeleton loading highlight.
    static var wizmarkShimmer: Color { ColorTokens.shimmer }

    /// Standardized card shadow.
    static var wizmarkCardShadow: Color { ColorTokens.cardShadow }

    /// Accent gradient start.
    static var wizmarkAccentGradientStart: Color { ColorTokens.accentGradientStart }

    /// Accent gradient end.
    static var wizmarkAccentGradientEnd: Color { ColorTokens.accentGradientEnd }
}
