import Foundation
import os

// MARK: - FeedbackViewModel

/// Drives the feedback submission screen: category selection, message input, and submission.
@Observable
@MainActor
final class FeedbackViewModel {

    // MARK: - Form State

    var category: FeedbackCategory = .other
    var message: String = ""

    // MARK: - Submission State

    private(set) var isSubmitting: Bool = false
    var showSuccessAlert: Bool = false
    var showErrorAlert: Bool = false
    private(set) var error: Error?

    // MARK: - Private

    private let feedbackService: FeedbackService
    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "FeedbackVM")

    // MARK: - Init

    init(feedbackService: FeedbackService) {
        self.feedbackService = feedbackService
    }

    // MARK: - Computed

    /// Whether the submit button should be enabled.
    var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    /// App version string from the main bundle.
    private var appVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    // MARK: - Actions

    /// Submit the feedback to the backend.
    func submit() async {
        guard canSubmit else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await feedbackService.submit(
                category: category,
                message: message,
                appVersion: appVersion
            )
            showSuccessAlert = true
            logger.info("Feedback submitted: \(self.category.rawValue, privacy: .public)")
        } catch {
            self.error = error
            showErrorAlert = true
            logger.error("Feedback submission failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Reset the form after successful submission.
    func reset() {
        category = .other
        message = ""
    }
}
