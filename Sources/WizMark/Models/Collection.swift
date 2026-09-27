import Foundation
import SwiftData

// MARK: - BookmarkCollection

/// A hierarchical folder for organizing bookmarks.
/// Named "BookmarkCollection" to avoid conflict with Swift's `Collection` protocol.
/// Persisted via SwiftData with automatic iCloud sync through CloudKit.
@Model
final class BookmarkCollection {

    // MARK: - Core Fields

    /// Display name of the collection.
    var name: String = ""

    /// SF Symbol name or emoji for the collection icon.
    var icon: String?

    /// Hex color string for visual distinction (e.g. "#FF5733").
    var color: String?

    /// Sort order among siblings. Lower values appear first.
    var order: Int = 0

    /// When the collection was created.
    var createdAt: Date = Date()

    // MARK: - AI Extraction Defaults

    var defaultAiSummary: Bool = false
    var defaultAiTags: Bool = false
    var defaultAiCategory: Bool = false
    var defaultAiPlaceName: Bool = false
    var defaultAiPlaceAddress: Bool = false
    var defaultAiPhoneNumber: Bool = false
    var defaultAiBusinessHours: Bool = false
    var defaultAiEventDateTime: Bool = false
    var defaultAiRecipe: Bool = false
    var defaultAiRating: Bool = false

    // MARK: - Relationships

    /// Bookmarks that belong to this collection.
    @Relationship(deleteRule: .nullify, inverse: \Bookmark.collection)
    var bookmarks: [Bookmark]? = []

    /// Parent collection for nested folders. Nil means root-level.
    var parent: BookmarkCollection?

    /// Child collections (sub-folders).
    @Relationship(deleteRule: .nullify, inverse: \BookmarkCollection.parent)
    var children: [BookmarkCollection]? = []

    // MARK: - Init

    init(name: String, icon: String? = nil, color: String? = nil) {
        self.name = name
        self.icon = icon
        self.color = color
    }

    // MARK: - Computed

    /// Number of bookmarks in this collection.
    var bookmarkCount: Int { bookmarks?.count ?? 0 }

    /// Whether this is a root-level collection (no parent).
    var isRoot: Bool { parent == nil }
}
