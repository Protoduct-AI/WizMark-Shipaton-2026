import Foundation
import PhotosUI
import SwiftUI
import os

// MARK: - ProfileEditViewModel

/// Drives the profile edit screen: avatar upload, display name, username management.
/// Subscribes to the current user via UserService and persists changes through Convex mutations.
@Observable
@MainActor
final class ProfileEditViewModel {

    // MARK: - Form State

    var displayName: String = ""
    var username: String = ""
    var localAvatarImage: UIImage?

    // MARK: - Derived State

    private(set) var isUploadingAvatar: Bool = false
    private(set) var isSubmitting: Bool = false
    private(set) var usernameAvailability: UsernameAvailability?
    private(set) var avatarStorageId: ConvexId?
    private(set) var remoteAvatarUrl: String?
    private(set) var error: Error?

    var showSuccessToast: Bool = false
    var showError: Bool = false

    // MARK: - Private

    private let userService: UserService
    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "ProfileEdit")
    private var hydrated: Bool = false
    private var originalUsername: String = ""
    private var usernameCheckTask: Task<Void, Never>?

    // MARK: - Init

    init(userService: UserService) {
        self.userService = userService
    }

    // MARK: - Hydration

    /// Populate form fields from the current user profile. Called once when the view appears.
    func hydrate() async {
        guard !hydrated, let user = userService.currentUser else { return }

        displayName = user.displayName ?? ""
        username = user.username ?? ""
        originalUsername = (user.username ?? "").lowercased()
        avatarStorageId = user.avatarStorageId

        if let storageId = user.avatarStorageId {
            do {
                remoteAvatarUrl = try await userService.getAvatarUrl(storageId: storageId)
            } catch {
                logger.error("Failed to load avatar URL: \(error.localizedDescription, privacy: .public)")
            }
        }

        hydrated = true
    }

    // MARK: - Avatar

    /// Process a selected PhotosPickerItem, compress it to JPEG, and upload to Convex.
    func handleAvatarSelection(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                return
            }

            localAvatarImage = uiImage
            isUploadingAvatar = true

            guard let jpegData = uiImage.jpegData(compressionQuality: 0.7) else {
                isUploadingAvatar = false
                return
            }

            let storageId = try await userService.uploadAvatar(imageData: jpegData)
            avatarStorageId = storageId
            isUploadingAvatar = false
        } catch {
            self.error = error
            showError = true
            localAvatarImage = nil
            isUploadingAvatar = false
            logger.error("Avatar upload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Username Validation

    /// The sanitized, lowercase username with only allowed characters.
    var sanitizedUsername: String {
        username.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
    }

    /// Whether the current username differs from the stored one.
    var usernameChanged: Bool {
        sanitizedUsername != originalUsername
    }

    /// Whether the username format is valid (empty OR 3-20 chars of [a-z0-9_.]).
    var usernameValidFormat: Bool {
        let trimmed = sanitizedUsername
        if trimmed.isEmpty { return true }
        let pattern = /^[a-z0-9_.]{3,20}$/
        return trimmed.wholeMatch(of: pattern) != nil
    }

    /// Whether the username is locked due to the 7-day cooldown.
    var usernameLocked: Bool {
        guard let user = userService.currentUser else { return false }
        return !user.canEditUsername
    }

    /// The date when the username can next be edited.
    var nextUsernameEditDate: Date? {
        userService.currentUser?.nextUsernameEditDate
    }

    /// Filter the username input to only allowed characters.
    func sanitizeUsernameInput(_ value: String) {
        username = value.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
        checkUsernameAvailability()
    }

    /// Debounced username availability check.
    private func checkUsernameAvailability() {
        usernameCheckTask?.cancel()
        usernameAvailability = nil

        let trimmed = sanitizedUsername
        guard usernameChanged, trimmed.count >= 3, usernameValidFormat else { return }

        usernameCheckTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            do {
                let result = try await userService.checkUsernameAvailable(username: trimmed)
                guard !Task.isCancelled else { return }
                usernameAvailability = result
            } catch {
                logger.debug("Username check failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Submission

    /// Whether the save button should be enabled.
    var canSubmit: Bool {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isUploadingAvatar, !isSubmitting, usernameValidFormat else {
            return false
        }
        if usernameChanged {
            return usernameAvailability?.available == true
        }
        return true
    }

    /// Save the profile changes to Convex.
    /// - Returns: `true` if save succeeded and the caller should dismiss.
    func save() async -> Bool {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isUploadingAvatar else { return false }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let locale: UserLocale? = {
                let current = AppLanguage.current
                return UserLocale(rawValue: current.rawValue)
            }()

            try await userService.updateProfile(
                displayName: trimmed,
                avatarStorageId: avatarStorageId,
                locale: locale
            )

            if usernameChanged, usernameValidFormat, !sanitizedUsername.isEmpty {
                try await userService.updateUsername(sanitizedUsername)
            }

            showSuccessToast = true
            return true
        } catch {
            self.error = error
            showError = true
            logger.error("Profile save failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
