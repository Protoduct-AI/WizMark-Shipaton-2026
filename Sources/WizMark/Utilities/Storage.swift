import Foundation

// MARK: - StorageKey

/// Centralised UserDefaults key registry.
///
/// Every persisted preference lives here so keys are discoverable,
/// typo-proof, and refactorable.
///
/// ## @AppStorage Usage
///
/// ```swift
/// struct SettingsView: View {
///     @AppStorage(StorageKey.hasCompletedOnboarding.rawValue)
///     private var hasCompletedOnboarding = false
///
///     @AppStorage(StorageKey.preferredLocale.rawValue)
///     private var preferredLocale: String = "ja"
///
///     @AppStorage(StorageKey.themePreference.rawValue)
///     private var themePreference: String = ThemePreference.system.rawValue
///
///     @AppStorage(StorageKey.biometricEnabled.rawValue)
///     private var biometricEnabled = false
/// }
/// ```
enum StorageKey: String, CaseIterable {

    /// `true` after the user completes the onboarding flow.
    case hasCompletedOnboarding = "has_completed_onboarding"

    /// `true` after the user finishes the profile setup step.
    case hasCompletedProfileSetup = "has_completed_profile_setup"

    /// ISO 639-1 language code chosen by the user (e.g. "ja", "en").
    case preferredLocale = "preferred_locale"

    /// Raw value of `ThemePreference` — "system", "light", or "dark".
    case themePreference = "theme_preference"

    /// Whether biometric (Face ID / Touch ID) unlock is enabled.
    case biometricEnabled = "biometric_enabled"

    /// Whether the notification permission prompt has been shown.
    case notificationPromptDone = "notification_prompt_done"
}

// MARK: - Type-Safe UserDefaults Helpers

enum Storage {

    private static let defaults = UserDefaults.standard

    // MARK: String

    static func string(for key: StorageKey) -> String? {
        defaults.string(forKey: key.rawValue)
    }

    static func set(_ value: String, for key: StorageKey) {
        defaults.set(value, forKey: key.rawValue)
    }

    // MARK: Bool

    static func bool(for key: StorageKey) -> Bool {
        defaults.bool(forKey: key.rawValue)
    }

    static func set(_ value: Bool, for key: StorageKey) {
        defaults.set(value, forKey: key.rawValue)
    }

    // MARK: Int

    static func int(for key: StorageKey) -> Int {
        defaults.integer(forKey: key.rawValue)
    }

    static func set(_ value: Int, for key: StorageKey) {
        defaults.set(value, forKey: key.rawValue)
    }

    // MARK: Remove

    static func remove(_ key: StorageKey) {
        defaults.removeObject(forKey: key.rawValue)
    }

    // MARK: Codable

    static func codable<T: Decodable>(for key: StorageKey, as type: T.Type) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func set<T: Encodable>(_ value: T, for key: StorageKey) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key.rawValue)
    }

    // MARK: Reset

    /// Remove all known keys (useful for sign-out / account deletion).
    static func resetAll() {
        for key in StorageKey.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
    }
}
