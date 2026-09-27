import Foundation

// MARK: - WizMarkFile

/// Codable representation of a `.wizmark` collection export file.
///
/// Used for importing and exporting bookmark collections as shareable JSON files
/// with the `.wizmark` extension.
struct WizMarkFile: Codable {

    /// File format version for future compatibility.
    let version: Int

    /// The collection name.
    let collectionName: String

    /// SF Symbol name or emoji for the collection icon.
    let collectionIcon: String?

    /// Hex color string for visual distinction.
    let collectionColor: String?

    /// All bookmarks in the collection.
    let bookmarks: [WizMarkBookmark]

    // MARK: - Init

    init(
        collectionName: String,
        collectionIcon: String? = nil,
        collectionColor: String? = nil,
        bookmarks: [WizMarkBookmark]
    ) {
        self.version = 1
        self.collectionName = collectionName
        self.collectionIcon = collectionIcon
        self.collectionColor = collectionColor
        self.bookmarks = bookmarks
    }
}

// MARK: - WizMarkBookmark

extension WizMarkFile {

    /// A single bookmark entry within a `.wizmark` export file.
    struct WizMarkBookmark: Codable {

        /// The bookmarked URL.
        let url: String

        /// Page title.
        let title: String

        /// User-assigned tags.
        let tags: [String]

        /// User-written note.
        let note: String?

        /// Thumbnail image URL.
        let thumbnailUrl: String?
    }
}
