import Foundation

// MARK: - AppGroup

/// The App Group container shared by the app and the share extension.
///
/// Kept separate from ``Config`` on purpose: `Config` traps when a required
/// Info.plist key is missing, and the extension's Info.plist does not carry the
/// app's keys. This file can therefore be compiled into both targets safely.
enum AppGroup {

    /// The App Group identifier declared in both targets' entitlements.
    static let identifier = "group.com.protoductai.wizmark"

    /// Defaults backed by the shared container, shared by app and extension.
    static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}
