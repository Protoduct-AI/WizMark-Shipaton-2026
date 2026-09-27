import Foundation

// MARK: - Feedback

/// A user-submitted feedback entry.
/// Maps 1:1 to the `feedback` table in `convex/schema.ts`.
struct Feedback: ConvexDocument, Hashable {

    // MARK: - Convex System Fields

    let _id: ConvexId
    let _creationTime: Double

    // MARK: - Core Fields

    /// Clerk subject identifier. Optional (anonymous feedback is allowed).
    let clerkId: String?

    /// Email address of the submitter. Optional.
    let email: String?

    /// Feedback category.
    let category: FeedbackCategory

    /// The feedback message body. 1-4000 characters.
    let message: String

    /// The app version string at time of submission (e.g. "1.2.0").
    let appVersion: String?

    /// The platform identifier at time of submission (e.g. "ios", "android").
    let platform: String?

    // MARK: - Identifiable

    var id: String { _id }
}

// MARK: - FeedbackCategory

/// Feedback type categories matching the Convex union.
enum FeedbackCategory: String, Codable, Hashable, Sendable {
    case bug
    case feature
    case other
}

// MARK: - FeedbackSubmission

/// Input payload for submitting new feedback via the `feedback.submitFeedback` mutation.
/// This is a write-only struct (not a Convex document) used to construct mutation arguments.
struct FeedbackSubmission: Codable, Sendable {

    /// Feedback category.
    let category: FeedbackCategory

    /// The feedback message body.
    let message: String

    /// Current app version.
    let appVersion: String?

    /// Current platform.
    let platform: String?

    /// Validate the submission before sending.
    /// Returns nil if valid, or an error description if invalid.
    var validationError: String? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return String(localized: "feedback.error.empty", defaultValue: "Message is required")
        }
        if trimmed.count > 4000 {
            return String(localized: "feedback.error.tooLong", defaultValue: "Message too long")
        }
        return nil
    }
}
