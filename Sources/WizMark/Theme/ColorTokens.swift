import SwiftUI

// MARK: - ColorTokens

/// Semantic color tokens for the WizMark design system.
/// Dark mode uses the "dark blue (navy)" palette from the Expo themes/dark-blue.css.
/// Light mode uses a warm, refined light palette with intentional depth.
enum ColorTokens {

    // MARK: - Backgrounds

    /// Primary background.
    /// Light: warm off-white with a subtle cream tint. Dark: deep navy.
    static let background = Color(
        light: Color(hex: "FAF9F7"),
        dark: Color(hex: "151D35")
    )

    /// Elevated surface (cards, sheets).
    /// Light: pure white. Dark: warm lifted navy.
    static let surface = Color(
        light: Color(hex: "FFFFFF"),
        dark: Color(hex: "1E2A48")
    )

    /// Secondary surface (grouped table rows, subtle cards).
    static let surfaceVariant = Color(
        light: Color(hex: "F3F2EE"),
        dark: Color(hex: "283654")
    )

    /// Tertiary surface / segment control background.
    static let surfaceTertiary = Color(
        light: Color(hex: "EAE8E3"),
        dark: Color(hex: "314060")
    )

    // MARK: - Text

    /// Primary text / foreground.
    static let text = Color(
        light: Color(hex: "1C1B1F"),
        dark: Color(hex: "F4F5FA")
    )

    /// Secondary text (labels, captions).
    static let textSecondary = Color(
        light: Color(hex: "65656E"),
        dark: Color(hex: "A0A8C0")
    )

    /// Muted / placeholder text.
    static let textMuted = Color(
        light: Color(hex: "9D9DA5"),
        dark: Color(hex: "7E879E")
    )

    // MARK: - Accent

    /// Primary accent — vibrant, accessible blue.
    /// Light mode WCAG AA on white: 4.58:1 contrast ratio.
    static let accent = Color(
        light: Color(hex: "2F5FE0"),
        dark: Color(hex: "6B9AFF")
    )

    /// Secondary accent for complementary highlights.
    static let accentSecondary = Color(
        light: Color(hex: "7A58E8"),
        dark: Color(hex: "A088F8")
    )

    /// Gradient start (for accent gradient buttons / decorative elements).
    static let accentGradientStart = Color(
        light: Color(hex: "3668F0"),
        dark: Color(hex: "5B8AFF")
    )

    /// Gradient end (for accent gradient buttons / decorative elements).
    static let accentGradientEnd = Color(
        light: Color(hex: "7A58E8"),
        dark: Color(hex: "A088F8")
    )

    // MARK: - Status

    /// Success green.
    static let success = Color(
        light: Color(hex: "2DA860"),
        dark: Color(hex: "4DD88A")
    )

    /// Warning amber.
    static let warning = Color(
        light: Color(hex: "D4930A"),
        dark: Color(hex: "F0C040")
    )

    /// Error / danger red.
    static let error = Color(
        light: Color(hex: "DC3545"),
        dark: Color(hex: "F06070")
    )

    // MARK: - Borders & Dividers

    /// Default border.
    static let border = Color(
        light: Color(hex: "E3E1DC"),
        dark: Color(hex: "304060")
    )

    /// Separator / divider.
    static let separator = Color(
        light: Color(hex: "EBE9E4"),
        dark: Color(hex: "384C6C")
    )

    // MARK: - Overlay

    /// Overlay background (modal backdrop, etc.).
    static let overlay = Color(
        light: Color(hex: "000000").opacity(0.3),
        dark: Color(hex: "0D1220").opacity(0.6)
    )

    // MARK: - Field

    /// Form field background.
    static let fieldBackground = Color(
        light: Color(hex: "F5F4F0"),
        dark: Color(hex: "212D4A")
    )

    // MARK: - Effects

    /// Shimmer / skeleton loading highlight color.
    static let shimmer = Color(
        light: Color(hex: "FFFFFF").opacity(0.6),
        dark: Color(hex: "FFFFFF").opacity(0.08)
    )

    /// Standardized card shadow color.
    static let cardShadow = Color(
        light: Color(hex: "1C1B1F").opacity(0.08),
        dark: Color(hex: "000000").opacity(0.35)
    )
}

// MARK: - Adaptive Color Initializer

extension Color {

    /// Creates an adaptive color that switches between light and dark variants
    /// based on the current color scheme.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}
