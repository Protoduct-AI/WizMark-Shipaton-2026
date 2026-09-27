import AppTrackingTransparency
import GoogleMobileAds
import os
import UIKit
import UserNotifications

// MARK: - AppDelegate

/// UIKit application delegate for handling system callbacks that SwiftUI
/// does not yet cover natively: remote notification registration and
/// notification center delegation.
final class AppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {

    // MARK: - Private

    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "AppDelegate")

    // MARK: - UIApplicationDelegate

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        return true
    }

    func requestTrackingIfNeeded() {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            ATTrackingManager.requestTrackingAuthorization { status in
                self.logger.info("ATT status: \(String(describing: status.rawValue))")
            }
        }
    }


    /// Called when APNs successfully registers and returns a device token.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        logger.info("APNs device token: \(tokenString.prefix(8), privacy: .public)...")

        // Forward to NotificationService on the main actor.
        Task { @MainActor in
            // NotificationService is accessed via AppServices, but since this delegate
            // fires early, we post a notification that the app struct can listen for.
            NotificationCenter.default.post(
                name: .didRegisterForRemoteNotifications,
                object: nil,
                userInfo: ["tokenData": deviceToken]
            )
        }
    }

    /// Called when APNs registration fails.
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        logger.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")

        Task { @MainActor in
            NotificationCenter.default.post(
                name: .didFailToRegisterForRemoteNotifications,
                object: nil,
                userInfo: ["error": error]
            )
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Handle notifications received while the app is in the foreground.
    /// Display the notification as a banner + sound.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        logger.debug("Foreground notification: \(notification.request.identifier)")
        return [.banner, .sound, .badge]
    }

    /// Handle the user tapping on a notification.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        logger.info("Notification tapped: \(response.notification.request.identifier)")

        // Extract deep link URL from the notification payload if present.
        if let urlString = userInfo["url"] as? String,
           let url = URL(string: urlString)
        {
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .didReceiveNotificationDeepLink,
                    object: nil,
                    userInfo: ["url": url]
                )
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when APNs registration succeeds. UserInfo contains "tokenData" (Data).
    static let didRegisterForRemoteNotifications = Notification.Name("wizmark.didRegisterForRemoteNotifications")

    /// Posted when APNs registration fails. UserInfo contains "error" (Error).
    static let didFailToRegisterForRemoteNotifications = Notification.Name("wizmark.didFailToRegisterForRemoteNotifications")

    /// Posted when a notification deep link should be handled. UserInfo contains "url" (URL).
    static let didReceiveNotificationDeepLink = Notification.Name("wizmark.didReceiveNotificationDeepLink")
}

