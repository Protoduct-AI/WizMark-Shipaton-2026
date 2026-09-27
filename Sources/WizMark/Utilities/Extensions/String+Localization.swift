import Foundation

// MARK: - AppLanguage

/// Supported application languages.
enum AppLanguage: String, CaseIterable, Identifiable {
    case ja
    case en

    var id: String { rawValue }

    /// Human-readable display name in the language's own script.
    var displayName: String {
        switch self {
        case .ja: "日本語"
        case .en: "English"
        }
    }

    /// The current language derived from UserDefaults, falling back to device locale,
    /// then defaulting to Japanese.
    static var current: AppLanguage {
        if let stored = Storage.string(for: .preferredLocale),
           let lang = AppLanguage(rawValue: stored) {
            return lang
        }
        let deviceCode = Locale.current.language.languageCode?.identifier ?? "ja"
        return AppLanguage(rawValue: deviceCode) ?? .ja
    }

    /// Persist this language choice and update the app's locale override.
    func apply() {
        Storage.set(rawValue, for: .preferredLocale)
        UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
    }
}

// MARK: - Localization Convenience

extension String {

    /// Shorthand for `String(localized:)` using a dot-separated key
    /// that maps into Localizable.xcstrings.
    ///
    /// ```swift
    /// let title = String.localized("auth.signIn")
    /// // equivalent to String(localized: "auth.signIn")
    /// ```
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }

    /// Returns a localized string with interpolation support.
    ///
    /// ```swift
    /// let msg = String.localized("auth.enterCodeSentTo", with: email)
    /// ```
    static func localized(
        _ key: String,
        with arguments: CVarArg...
    ) -> String {
        let format = String(localized: String.LocalizationValue(key))
        guard !arguments.isEmpty else { return format }
        return String(format: format, arguments: arguments)
    }
}
