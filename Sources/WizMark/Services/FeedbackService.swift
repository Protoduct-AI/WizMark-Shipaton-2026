import Foundation
@preconcurrency import ConvexMobile
import os

// MARK: - FeedbackService

/// Submits user feedback to the Convex backend via the `feedback:submitFeedback` mutation.
@Observable
@MainActor
final class FeedbackService {

    // MARK: - State

    /// Whether a submission is in progress.
    private(set) var isSubmitting: Bool = false

    // MARK: - Private

    private let client: ConvexClientWithAuth<String>
    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "Feedback")

    // MARK: - Init

    init(client: ConvexClientWithAuth<String>) {
        self.client = client
    }

    // MARK: - Public API

    /// Submit feedback to the backend.
    /// - Parameter submission: The validated feedback payload.
    /// - Throws: Network or validation errors.
    func submit(_ submission: FeedbackSubmission) async throws {
        if let validationError = submission.validationError {
            throw FeedbackError.validation(validationError)
        }

        isSubmitting = true
        defer { isSubmitting = false }

        var args: [String: ConvexEncodable?] = [
            "category": submission.category.rawValue,
            "message": submission.message.trimmingCharacters(in: .whitespacesAndNewlines),
        ]

        if let appVersion = submission.appVersion {
            args["appVersion"] = appVersion
        }

        if let platform = submission.platform {
            args["platform"] = platform
        }

        let _: FeedbackResult = try await client.mutation("feedback:submitFeedback", with: args)
        logger.info("Feedback submitted: \(submission.category.rawValue, privacy: .public)")
    }

    /// Convenience: submit feedback with individual parameters.
    func submit(
        category: FeedbackCategory,
        message: String,
        appVersion: String? = nil
    ) async throws {
        let submission = FeedbackSubmission(
            category: category,
            message: message,
            appVersion: appVersion,
            platform: "ios"
        )
        try await submit(submission)
    }
}

// MARK: - FeedbackResult

/// Decodable wrapper for the `{ success: true }` response from `feedback:submitFeedback`.
private struct FeedbackResult: Decodable {
    let success: Bool
}

// MARK: - FeedbackError

enum FeedbackError: LocalizedError {
    case validation(String)

    var errorDescription: String? {
        switch self {
        case .validation(let message):
            return message
        }
    }
}
