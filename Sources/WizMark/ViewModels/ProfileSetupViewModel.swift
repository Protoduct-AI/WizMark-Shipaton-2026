import Foundation
import PhotosUI
import SwiftUI
import os

// MARK: - ProfileSetupViewModel

/// Drives the first-time profile setup flow after sign-up.
/// Handles avatar selection/upload and display name, then marks the profile as completed.
@Observable
@MainActor
final class ProfileSetupViewModel {

    // MARK: - Form State

    var displayName: String = ""
    var localAvatarImage: UIImage?

    // MARK: - Status

    private(set) var isUploadingAvatar: Bool = false
    private(set) var isSubmitting: Bool = false
    private(set) var isCompleted: Bool = false
    var showError: Bool = false
    private(set) var error: Error?

    // MARK: - Private

    private let userService: UserService
    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "ProfileSetup")
    private var avatarStorageId: ConvexId?

    // MARK: - Init

    init(userService: UserService) {
        self.userService = userService
    }

    // MARK: - Avatar

    /// Process a selected PhotosPickerItem, compress it, and upload to Convex.
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
            avatarStorageId = nil
            isUploadingAvatar = false
            logger.error("Avatar upload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Computed

    /// Whether the continue button should be enabled.
    var canSubmit: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isUploadingAvatar
            && !isSubmitting
    }

    // MARK: - Submission

    /// Save the profile and mark setup as complete.
    func completeSetup() async {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isUploadingAvatar else { return }

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

            Storage.set(true, for: .hasCompletedProfileSetup)
            isCompleted = true
            logger.info("Profile setup completed")
        } catch {
            self.error = error
            showError = true
            logger.error("Profile setup failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
