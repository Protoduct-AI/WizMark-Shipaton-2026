import Foundation
import PostHog
import os

// MARK: - AnalyticsService

/// Wraps the PostHog iOS SDK for event tracking, user identification, and screen views.
/// Respects App Tracking Transparency; does not capture events until configured.
@Observable
@MainActor
final class AnalyticsService {

    // MARK: - State

    /// Whether PostHog has been configured and is ready to capture events.
    private(set) var isConfigured: Bool = false

    // MARK: - Private

    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "Analytics")

    // MARK: - Configuration

    /// Initialize the PostHog SDK with the given API key and host.
    /// Call once at app launch after ATT consent (if required).
    /// - Parameters:
    ///   - apiKey: PostHog project API key.
    ///   - host: PostHog host URL (defaults to US cloud).
    func configure(apiKey: String, host: String = "https://us.i.posthog.com") {
        guard !apiKey.isEmpty else {
            logger.warning("PostHog API key is empty; analytics disabled")
            return
        }

        let config = PostHogConfig(apiKey: apiKey, host: host)
        config.captureScreenViews = true
        config.captureApplicationLifecycleEvents = true
        config.sessionReplay = false

        PostHogSDK.shared.setup(config)
        isConfigured = true
        logger.info("PostHog configured")
    }

    // MARK: - Event Tracking

    /// Capture a named event with optional properties.
    /// - Parameters:
    ///   - event: The event name (e.g. "bookmark_created").
    ///   - properties: Key-value pairs attached to the event.
    func capture(event: String, properties: [String: Any]? = nil) {
        guard isConfigured else { return }
        PostHogSDK.shared.capture(event, properties: properties)
    }

    /// Identify the current user for event attribution.
    /// Call after Clerk sign-in succeeds.
    /// - Parameters:
    ///   - userId: The Clerk subject identifier.
    ///   - properties: Optional user traits (email, name, etc.).
    func identify(userId: String, properties: [String: Any]? = nil) {
        guard isConfigured else { return }
        PostHogSDK.shared.identify(userId, userProperties: properties)
        logger.debug("Identified user: \(userId, privacy: .private(mask: .hash))")
    }

    /// Track a screen view. Use for manually tracked screens outside auto-capture.
    /// - Parameter name: The screen name (e.g. "BookmarkDetail").
    func screen(name: String) {
        guard isConfigured else { return }
        PostHogSDK.shared.screen(name)
    }

    /// Reset the current user identity (call on sign-out).
    func reset() {
        guard isConfigured else { return }
        PostHogSDK.shared.reset()
        logger.debug("Analytics identity reset")
    }

    /// Opt the user out of analytics tracking.
    func optOut() {
        guard isConfigured else { return }
        PostHogSDK.shared.optOut()
        logger.info("User opted out of analytics")
    }

    /// Opt the user back into analytics tracking.
    func optIn() {
        guard isConfigured else { return }
        PostHogSDK.shared.optIn()
        logger.info("User opted into analytics")
    }
}
