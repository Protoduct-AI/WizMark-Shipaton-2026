import os
import SwiftUI

// MARK: - ThemePreference

/// User-selectable theme preference.
enum ThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: String(localized: "onboarding.theme.system")
        case .light: String(localized: "onboarding.theme.light")
        case .dark: String(localized: "onboarding.theme.dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - AppTheme

/// Observable theme state that persists the user's preference to UserDefaults
/// and exposes semantic colors for the "dark blue" WizMark palette.
///
/// Usage:
/// ```swift
/// // In your App or root view:
/// @State private var theme = AppTheme()
/// ...
/// .preferredColorScheme(theme.resolvedColorScheme)
/// .environment(theme)
/// ```
@Observable
@MainActor
final class AppTheme {

    // MARK: - Storage

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.protoductai.wizmark",
        category: "AppTheme"
    )

    private static let defaultsKey = StorageKey.themePreference.rawValue

    // MARK: - State

    /// The user's explicit preference. `nil` means follow the system.
    var preference: ThemePreference {
        didSet {
            guard preference != oldValue else { return }
            UserDefaults.standard.set(preference.rawValue, forKey: Self.defaultsKey)
            Self.logger.info("Theme preference changed to \(self.preference.rawValue)")
        }
    }

    /// The resolved `ColorScheme` to apply via `.preferredColorScheme()`.
    /// Returns `nil` when the user chooses "system" (letting the OS decide).
    var resolvedColorScheme: ColorScheme? {
        preference.colorScheme
    }

    /// Whether the effective appearance is dark.
    /// Useful when you need to branch logic beyond what adaptive colors handle.
    var isDark: Bool {
        switch preference {
        case .dark: true
        case .light: false
        case .system: UITraitCollection.current.userInterfaceStyle == .dark
        }
    }

    // MARK: - Semantic Color Accessors

    var background: Color { ColorTokens.background }
    var surface: Color { ColorTokens.surface }
    var surfaceVariant: Color { ColorTokens.surfaceVariant }
    var text: Color { ColorTokens.text }
    var textSecondary: Color { ColorTokens.textSecondary }
    var accent: Color { ColorTokens.accent }
    var accentSecondary: Color { ColorTokens.accentSecondary }
    var error: Color { ColorTokens.error }
    var success: Color { ColorTokens.success }
    var warning: Color { ColorTokens.warning }
    var border: Color { ColorTokens.border }
    var separator: Color { ColorTokens.separator }

    // MARK: - Init

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey)
        self.preference = stored.flatMap(ThemePreference.init(rawValue:)) ?? .system
    }

    // MARK: - Convenience

    /// Toggle between light and dark. Resets to `.dark` if currently on system.
    func toggle() {
        switch preference {
        case .light: preference = .dark
        case .dark: preference = .light
        case .system: preference = .dark
        }
    }
}
