import Foundation
import os

// MARK: - HomeViewModel

/// Thin view model for the Home tab.
///
/// With SwiftData, most data is fetched via @Query directly in views.
/// This view model only holds search state and provides filtered results
/// for bookmarks and collections passed in from the view layer.
@Observable
@MainActor
final class HomeViewModel {

    // MARK: - State

    /// User-entered search text bound to `.searchable`.
    var searchQuery: String = ""

    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "HomeViewModel")

    // MARK: - Init

    init() {}

    // MARK: - Computed

    /// Whether the search is currently active (non-empty query).
    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Filtered Results

    /// Collections matching the current search query.
    func filteredCollections(from collections: [BookmarkCollection]) -> [BookmarkCollection] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return collections }
        return collections.filter { $0.name.lowercased().contains(query) }
    }

    /// Bookmarks matching the current search query by title, URL, description, or tags.
    func filteredBookmarks(from bookmarks: [Bookmark]) -> [Bookmark] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return bookmarks.filter { bookmark in
            bookmark.title.lowercased().contains(query)
            || bookmark.url.lowercased().contains(query)
            || (bookmark.bookmarkDescription?.lowercased().contains(query) ?? false)
            || bookmark.tags.contains { $0.lowercased().contains(query) }
        }
    }
}
