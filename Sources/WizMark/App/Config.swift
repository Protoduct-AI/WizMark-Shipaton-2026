import Foundation

// MARK: - Config

/// Centralized configuration values read from Info.plist at launch.
///
/// Values are populated via xcconfig or Xcode build settings and embedded
/// into Info.plist at build time. Required keys trigger a fatal error when
/// absent so misconfigurations surface immediately rather than at runtime.
enum Config {

    // MARK: - Convex

    /// The Convex deployment URL (e.g. "https://xxx-yyy.convex.cloud").
    static let convexUrl: String = required("CONVEX_URL")

    // MARK: - Clerk

    /// Clerk publishable key for authentication.
    static let clerkPublishableKey: String = required("CLERK_PUBLISHABLE_KEY")

    // MARK: - PostHog

    /// PostHog project API key for analytics.
    /// Empty string disables analytics gracefully.
    static let posthogApiKey: String = optional("POSTHOG_API_KEY") ?? ""

    /// PostHog ingestion host URL.
    static let posthogHost: String = optional("POSTHOG_HOST") ?? "https://us.i.posthog.com"

    // MARK: - Sentry

    /// Sentry DSN for error tracking.
    /// Empty string disables Sentry gracefully.
    static let sentryDsn: String = optional("SENTRY_DSN") ?? ""

    // MARK: - Deep Linking

    /// Custom URL scheme for deep links.
    static let urlScheme = "wizmark"

    /// Universal link host for associated domains.
    static let universalLinkHost = "wizmark.protoductai.com"

    // MARK: - Bundle Info

    /// The bundle identifier.
    static let bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.protoductai.wizmark"

    /// Marketing version string (e.g. "1.0.0").
    static let version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

    /// Build number string.
    static let build: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"

    // MARK: - Private Helpers

    /// Read a required value from Info.plist. Crashes at launch if missing.
    private static func required(_ key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else {
            fatalError("\(key) is not set in Info.plist. Add it to your build configuration.")
        }
        return value
    }

    /// Read an optional value from Info.plist. Returns nil if absent or empty.
    private static func optional(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
