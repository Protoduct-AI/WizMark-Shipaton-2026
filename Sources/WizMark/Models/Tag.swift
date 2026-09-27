import Foundation

// MARK: - TagInfo

/// A lightweight tag representation with its usage count.
/// Tags are stored as `[String]` on `Bookmark` — this struct is computed
/// by aggregating across all bookmarks for display in tag browsers / filters.
/// Not a SwiftData model; it is derived at runtime.
struct TagInfo: Identifiable, Hashable, Sendable {

    /// Tag name (lowercase).
    let name: String

    /// Number of bookmarks using this tag.
    let count: Int

    // MARK: - Identifiable

    var id: String { name }
}
