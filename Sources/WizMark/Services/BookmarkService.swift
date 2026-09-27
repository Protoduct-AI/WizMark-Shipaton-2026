import Foundation
import SwiftData
import os

@Observable
@MainActor
final class BookmarkService {

    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "BookmarkService")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func create(
        url: String,
        title: String = "",
        description: String? = nil,
        thumbnailUrl: String? = nil,
        collection: BookmarkCollection? = nil,
        tags: [String] = []
    ) -> Bookmark {
        let bookmark = Bookmark(
            url: url,
            title: title,
            description: description,
            thumbnailUrl: thumbnailUrl
        )
        bookmark.tags = tags
        bookmark.collection = collection

        modelContext.insert(bookmark)
        try? modelContext.save()

        logger.info("Bookmark created: \(url, privacy: .public)")
        return bookmark
    }

    func delete(_ bookmark: Bookmark) {
        modelContext.delete(bookmark)
        try? modelContext.save()
        logger.info("Bookmark deleted: \(bookmark.url, privacy: .public)")
    }

    func update(_ bookmark: Bookmark) {
        bookmark.updatedAt = Date()
        try? modelContext.save()
        logger.info("Bookmark updated: \(bookmark.url, privacy: .public)")
    }
}
