import Foundation
import UserNotifications
import UIKit
import os

// MARK: - NotificationService

/// Manages push notification permission, registration, and device token handling.
/// Wraps UNUserNotificationCenter for a clean async/await interface.
@Observable
@MainActor
final class NotificationService: NSObject {

    // MARK: - Published State

    /// Current notification authorization status.
    private(set) var permissionStatus: UNAuthorizationStatus = .notDetermined

    /// The APNs device token as a hex string, if registration succeeded.
    private(set) var deviceToken: String?

    /// Whether the permission prompt has been shown at least once.
    private(set) var promptCompleted: Bool = false

    // MARK: - Private

    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "Notifications")
    private let center = UNUserNotificationCenter.current()

    // MARK: - Init

    override init() {
        super.init()
        Task { [weak self] in
            await self?.refreshPermissionStatus()
        }
    }

    // MARK: - Public API

    /// Refresh the current authorization status from the system.
    func refreshPermissionStatus() async {
        let settings = await center.notificationSettings()
        permissionStatus = settings.authorizationStatus
    }

    /// Request notification permission from the user.
    /// - Returns: `true` if the user granted permission.
    @discardableResult
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshPermissionStatus()
            promptCompleted = true

            if granted {
                registerForRemoteNotifications()
                logger.info("Notification permission granted")
            } else {
                logger.info("Notification permission denied")
            }

            return granted
        } catch {
            logger.error("Failed to request notification permission: \(error.localizedDescription, privacy: .public)")
            promptCompleted = true
            return false
        }
    }

    /// Register with APNs for remote notifications.
    /// Call after permission is granted or on app launch if already authorized.
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
        logger.debug("Registered for remote notifications")
    }

    /// Called by the AppDelegate when APNs returns a device token.
    /// - Parameter tokenData: The raw token data from `didRegisterForRemoteNotificationsWithDeviceToken`.
    func handleDeviceToken(_ tokenData: Data) {
        let tokenString = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        deviceToken = tokenString
        logger.info("APNs device token received: \(tokenString.prefix(8), privacy: .public)...")
    }

    /// Called by the AppDelegate when APNs registration fails.
    /// - Parameter error: The registration error.
    func handleRegistrationError(_ error: Error) {
        logger.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
        deviceToken = nil
    }

    /// Clear the badge count.
    func clearBadge() async {
        do {
            try await center.setBadgeCount(0)
        } catch {
            logger.debug("Failed to clear badge: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Whether the user can be prompted for notification permission.
    /// Returns false if the user already denied or if status is not determined after prompt.
    var canRequestPermission: Bool {
        permissionStatus == .notDetermined
    }

    /// Whether notifications are currently authorized.
    var isAuthorized: Bool {
        permissionStatus == .authorized || permissionStatus == .provisional
    }
}
