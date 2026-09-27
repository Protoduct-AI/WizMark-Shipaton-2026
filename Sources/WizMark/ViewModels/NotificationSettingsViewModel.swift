import Foundation
import os

// MARK: - NotificationSettingsViewModel

/// Drives the notification preferences screen.
/// Manages toggle state for marketing, updates, and reminder notification categories,
/// syncing changes to the Convex backend via UserService.
@Observable
@MainActor
final class NotificationSettingsViewModel {

    // MARK: - Preference State

    var marketing: Bool = false
    var updates: Bool = true
    var reminders: Bool = true

    // MARK: - Private

    private let userService: UserService
    private let notificationService: NotificationService
    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "NotifSettings")
    private var hydrated: Bool = false

    // MARK: - Init

    init(userService: UserService, notificationService: NotificationService) {
        self.userService = userService
        self.notificationService = notificationService
    }

    // MARK: - Hydration

    /// Populate toggles from the current user's stored preferences.
    func hydrate() {
        guard !hydrated, let prefs = userService.currentUser?.notificationPrefs else { return }
        marketing = prefs.marketing
        updates = prefs.updates
        reminders = prefs.reminders
        hydrated = true
    }

    // MARK: - System Permission

    /// Whether push notifications are authorized at the system level.
    var isSystemAuthorized: Bool {
        notificationService.isAuthorized
    }

    /// Whether the system permission is explicitly denied (user must go to Settings).
    var isSystemDenied: Bool {
        notificationService.permissionStatus == .denied
    }

    // MARK: - Toggle Handling

    /// Persist a preference change to the backend with optimistic rollback.
    func toggleMarketing(_ value: Bool) {
        let previous = marketing
        marketing = value
        Task { await persistPrefs(rollback: { self.marketing = previous }) }
    }

    func toggleUpdates(_ value: Bool) {
        let previous = updates
        updates = value
        Task { await persistPrefs(rollback: { self.updates = previous }) }
    }

    func toggleReminders(_ value: Bool) {
        let previous = reminders
        reminders = value
        Task { await persistPrefs(rollback: { self.reminders = previous }) }
    }

    // MARK: - Private

    private func persistPrefs(rollback: @escaping () -> Void) async {
        do {
            try await userService.updateNotificationPrefs(
                marketing: marketing,
                updates: updates,
                reminders: reminders
            )
        } catch {
            rollback()
            logger.error("Failed to update notification prefs: \(error.localizedDescription, privacy: .public)")
        }
    }
}
