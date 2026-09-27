import Foundation

// MARK: - Legacy Convex Types
// ⚠️ LEGACY: These types are only used when Convex sync is enabled (signed-in users).
// Core bookmark/collection data now uses SwiftData + CloudKit (see Bookmark.swift, Collection.swift).
// Kept for Feedback and UserProfile which remain Convex-backed for signed-in features.

// MARK: - Convex ID Types

/// Convex document IDs are opaque strings (e.g. "j571abc...").
/// Using a typealias preserves semantic meaning while keeping Codable simplicity.
typealias ConvexId = String

/// Strongly-typed wrapper for table-specific Convex IDs.
/// Prevents accidentally passing a bookmark ID where a collection ID is expected.
enum ConvexDocumentId {
    typealias User = ConvexId
    typealias Storage = ConvexId
    typealias Feedback = ConvexId
}

// MARK: - Convex Timestamp Conversion

/// Convex stores timestamps as milliseconds since Unix epoch (JavaScript `Date.now()`).
/// These helpers convert between Convex timestamps and Swift `Date`.
enum ConvexTimestamp {

    /// Convert a Convex millisecond timestamp to a Swift Date.
    static func toDate(_ milliseconds: Double) -> Date {
        Date(timeIntervalSince1970: milliseconds / 1000.0)
    }

    /// Convert a Swift Date to a Convex millisecond timestamp.
    static func fromDate(_ date: Date) -> Double {
        date.timeIntervalSince1970 * 1000.0
    }
}

// MARK: - Tag (Convex-backed)

/// A tag returned by the `tags:list` Convex query.
/// Maps to the Convex tag aggregation which returns name + usage count.
struct Tag: Codable, Identifiable, Hashable, Sendable {
    let name: String
    let count: Int

    var id: String { name }
}

// MARK: - ConvexDocument Protocol

/// Protocol for Convex-backed document types (Feedback, UserProfile).
/// Every Convex document has a system-generated `_id` and `_creationTime`.
protocol ConvexDocument: Codable, Identifiable, Sendable {
    /// The Convex document ID (system-generated, globally unique string).
    var _id: ConvexId { get }

    /// Milliseconds since Unix epoch when the document was inserted.
    var _creationTime: Double { get }
}

extension ConvexDocument {
    /// The creation timestamp as a Swift Date.
    var creationDate: Date {
        ConvexTimestamp.toDate(_creationTime)
    }
}
