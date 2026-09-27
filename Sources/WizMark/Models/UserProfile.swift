import Foundation

// MARK: - UserProfile

/// The authenticated user's profile.
/// Maps 1:1 to the `user` table in `convex/schema.ts`.
struct UserProfile: ConvexDocument {

    // MARK: - Convex System Fields

    let _id: ConvexId
    let _creationTime: Double

    // MARK: - Core Fields

    /// The user's email address (from Clerk).
    let email: String

    /// Clerk subject identifier.
    let clerkId: String

    /// User-chosen display name. Optional until profile is completed.
    let displayName: String?

    /// Unique username (lowercase, 3-20 chars, `[a-z0-9_.]`).
    /// Auto-generated on account creation, editable with a 7-day cooldown.
    let username: String?

    /// Milliseconds since epoch when the username was last changed.
    /// Used to enforce the 7-day edit cooldown.
    let usernameUpdatedAt: Double?

    /// Convex storage ID for the user's avatar image.
    let avatarStorageId: ConvexId?

    /// Whether the user has completed initial profile setup.
    let profileCompleted: Bool?

    /// User's preferred locale ("ja" or "en").
    let locale: UserLocale?

    /// Notification preferences. Nil until the user configures them.
    let notificationPrefs: NotificationPreferences?

    // MARK: - Identifiable

    var id: String { _id }

    // MARK: - Computed

    /// Whether the user has finished onboarding profile setup.
    var isProfileCompleted: Bool { profileCompleted ?? false }

    /// The date when the username was last changed, if ever.
    var usernameUpdatedDate: Date? {
        guard let usernameUpdatedAt else { return nil }
        return ConvexTimestamp.toDate(usernameUpdatedAt)
    }

    /// The earliest date when the username can be changed again.
    /// Returns nil if the username has never been changed.
    var nextUsernameEditDate: Date? {
        guard let usernameUpdatedAt else { return nil }
        let cooldownMs: Double = 7 * 24 * 60 * 60 * 1000
        return ConvexTimestamp.toDate(usernameUpdatedAt + cooldownMs)
    }

    /// Whether the username cooldown has elapsed and the user can change it.
    var canEditUsername: Bool {
        guard let nextDate = nextUsernameEditDate else { return true }
        return Date.now >= nextDate
    }
}

// MARK: - UserLocale

/// Supported app locales matching the Convex union `v.literal('ja') | v.literal('en')`.
enum UserLocale: String, Codable, Hashable, Sendable {
    case ja
    case en
}

// MARK: - NotificationPreferences

/// User notification opt-in preferences.
/// Maps to the `notificationPrefs` object in the `user` table.
struct NotificationPreferences: Codable, Hashable, Sendable {

    /// Marketing and promotional notifications.
    let marketing: Bool

    /// App update and feature announcement notifications.
    let updates: Bool

    /// Bookmark reminder notifications.
    let reminders: Bool
}
