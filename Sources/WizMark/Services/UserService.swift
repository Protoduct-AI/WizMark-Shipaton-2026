import Foundation
import Combine
@preconcurrency import ConvexMobile
import os

// MARK: - UserService

/// Manages the authenticated user's profile via Convex real-time subscription and mutations.
/// Provides profile update, avatar upload, username management, and notification preferences.
@Observable
@MainActor
final class UserService {

    // MARK: - Published State

    /// The current user's profile. Nil if not yet loaded or not authenticated.
    private(set) var currentUser: UserProfile?

    /// Whether the initial user load is in progress.
    private(set) var isLoading: Bool = false

    /// Last error from subscription or mutation.
    private(set) var error: Error?

    // MARK: - Private

    private let client: ConvexClientWithAuth<String>
    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "UserService")
    private var subscriptionCancellable: AnyCancellable?

    // MARK: - Init

    init(client: ConvexClientWithAuth<String>) {
        self.client = client
    }

    // MARK: - Subscription

    /// Start a real-time subscription to the current user's profile.
    func subscribe() {
        unsubscribe()
        isLoading = true
        error = nil

        let publisher: AnyPublisher<UserProfile?, ClientError> = client.subscribe(to: "users:getCurrentUser")
        subscriptionCancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self else { return }
                    if case .failure(let subscriptionError) = completion {
                        self.error = subscriptionError
                        self.isLoading = false
                        self.logger.error("User subscription failed: \(subscriptionError.localizedDescription, privacy: .public)")
                    }
                },
                receiveValue: { [weak self] (decoded: UserProfile?) in
                    guard let self else { return }
                    self.currentUser = decoded
                    self.isLoading = false
                    self.error = nil
                }
            )

        logger.debug("User subscription started")
    }

    /// Stop the real-time subscription.
    func unsubscribe() {
        subscriptionCancellable?.cancel()
        subscriptionCancellable = nil
    }

    // MARK: - Profile Management

    /// Update the user's display name and optional avatar.
    /// - Parameters:
    ///   - displayName: New display name.
    ///   - avatarStorageId: Convex storage ID for the uploaded avatar image, if changed.
    ///   - locale: Preferred locale.
    func updateProfile(
        displayName: String,
        avatarStorageId: ConvexId? = nil,
        locale: UserLocale? = nil
    ) async throws {
        var args: [String: ConvexEncodable?] = [
            "displayName": displayName,
        ]

        if let avatarStorageId {
            args["avatarStorageId"] = avatarStorageId
        }

        if let locale {
            args["locale"] = locale.rawValue
        }

        try await client.mutation("users:updateProfile", with: args)
        logger.info("Profile updated")
    }

    /// Update the user's notification preferences.
    /// - Parameters:
    ///   - marketing: Opt-in for marketing notifications.
    ///   - updates: Opt-in for app update notifications.
    ///   - reminders: Opt-in for bookmark reminder notifications.
    func updateNotificationPrefs(
        marketing: Bool,
        updates: Bool,
        reminders: Bool
    ) async throws {
        try await client.mutation("users:updateNotificationPrefs", with: [
            "marketing": marketing,
            "updates": updates,
            "reminders": reminders,
        ])
        logger.info("Notification preferences updated")
    }

    // MARK: - Avatar Upload

    /// Upload avatar image data to Convex storage.
    /// - Parameter imageData: JPEG or PNG image data.
    /// - Returns: The Convex storage ID for the uploaded image.
    func uploadAvatar(imageData: Data) async throws -> String {
        let uploadUrl: String = try await client.mutation("users:generateAvatarUploadUrl", with: [:])

        guard let url = URL(string: uploadUrl) else {
            throw UserServiceError.avatarUploadFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw UserServiceError.avatarUploadFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let storageId = json["storageId"] as? String else {
            throw UserServiceError.avatarUploadFailed
        }

        logger.info("Avatar uploaded: \(storageId.prefix(20))")
        return storageId
    }

    // MARK: - Username Management

    /// Check whether a username is available.
    /// - Parameter username: The desired username.
    /// - Returns: Availability result with reason if unavailable.
    func checkUsernameAvailable(username: String) async throws -> UsernameAvailability {
        try await queryOnce("users:checkUsernameAvailable", with: ["username": username])
    }

    /// Update the current user's username.
    /// Subject to format validation and 7-day cooldown.
    /// - Parameter username: The new username.
    func updateUsername(_ username: String) async throws {
        try await client.mutation("users:updateUsername", with: [
            "username": username,
        ])
        logger.info("Username updated")
    }

    // MARK: - Account

    /// Backfill the username if the user account was created before username support.
    func backfillUsername() async throws {
        try await client.mutation("users:backfillUsername", with: [:])
        logger.debug("Username backfilled")
    }

    /// Permanently delete the current user's account and all associated data.
    func deleteAccount() async throws {
        try await client.mutation("users:deleteUser", with: [:])
        logger.info("User account deleted")
    }

    /// Export all user data for GDPR/privacy compliance.
    func exportUserData() async throws -> UserDataExport {
        try await queryOnce("users:exportUserData", with: [:])
    }

    /// Get the public URL for an avatar by its storage ID.
    /// - Parameter storageId: The Convex storage ID.
    /// - Returns: The public URL string, or nil if not found.
    func getAvatarUrl(storageId: ConvexId) async throws -> String? {
        try await queryOnce("users:getAvatarUrl", with: ["storageId": storageId])
    }

    // MARK: - Query Helper

    /// Execute a one-shot query by subscribing and taking the first emitted value.
    /// ConvexMobile only provides `subscribe` for queries (no one-shot query method).
    private func queryOnce<T: Decodable>(_ name: String, with args: [String: ConvexEncodable?]? = nil) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = client.subscribe(to: name, with: args, yielding: T.self)
                .first()
                // Convex delivers on a background queue. Without hopping to the
                // main queue the callbacks run off the main actor and trip
                // Swift's executor check, which crashes the process.
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            continuation.resume(throwing: error)
                        }
                        cancellable?.cancel()
                    },
                    receiveValue: { [continuation] value in
                        nonisolated(unsafe) let v = value
                        continuation.resume(returning: v)
                        cancellable?.cancel()
                    }
                )
        }
    }
}

// MARK: - UserServiceError

enum UserServiceError: LocalizedError {
    case avatarUploadFailed

    var errorDescription: String? {
        switch self {
        case .avatarUploadFailed:
            return String(localized: "user.error.avatarUpload", defaultValue: "Failed to upload avatar")
        }
    }
}

// MARK: - UsernameAvailability

/// Result of a username availability check.
struct UsernameAvailability: Codable, Sendable {
    let available: Bool
    let reason: String?
}

// MARK: - UserDataExport

/// The shape returned by `users:exportUserData`.
struct UserDataExport: Codable, Sendable {
    let exportedAt: String
    let schema: String
    let user: UserDataExportUser?
    let feedback: [UserDataExportFeedback]
}

struct UserDataExportUser: Codable, Sendable {
    let email: String
    let displayName: String?
    let username: String?
    let locale: String?
    let profileCompleted: Bool
    let avatarUrl: String?
    let notificationPrefs: NotificationPreferences?
    let createdAt: String
}

struct UserDataExportFeedback: Codable, Sendable {
    let category: String
    let message: String
    let appVersion: String?
    let platform: String?
    let submittedAt: String
}
