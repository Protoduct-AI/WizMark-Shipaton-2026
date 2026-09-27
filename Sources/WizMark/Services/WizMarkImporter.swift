import Foundation
import os
import SwiftData

// MARK: - WizMarkImportError

/// Errors that can occur during `.wizmark` file import.
enum WizMarkImportError: LocalizedError {

    case fileAccessDenied
    case invalidFormat(underlying: Error)
    case saveFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .fileAccessDenied:
            String(localized: "import.error.fileAccessDenied", defaultValue: ".wizmarkファイルにアクセスできませんでした")
        case .invalidFormat:
            String(localized: "import.error.invalidFormat", defaultValue: ".wizmarkファイルの形式が正しくありません")
        case .saveFailed:
            String(localized: "import.error.saveFailed", defaultValue: "インポートしたデータの保存に失敗しました")
        }
    }
}

// MARK: - WizMarkImporter

/// Imports `.wizmark` files into SwiftData, creating a collection and its bookmarks.
enum WizMarkImporter {

    private static let logger = Logger(
        subsystem: "com.protoductai.wizmark",
        category: "WizMarkImporter"
    )

    /// Import a `.wizmark` file at the given URL into the provided model context.
    ///
    /// The file URL may be a security-scoped resource (e.g. from AirDrop or Files),
    /// so access is wrapped in `startAccessingSecurityScopedResource`.
    ///
    /// - Parameters:
    ///   - url: The file URL of the `.wizmark` file.
    ///   - context: The SwiftData `ModelContext` to insert into.
    /// - Throws: `WizMarkImportError` on failure.
    static func importFile(at url: URL, into context: ModelContext) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logger.error("Failed to read .wizmark file: \(error.localizedDescription)")
            throw WizMarkImportError.fileAccessDenied
        }

        let file: WizMarkFile
        do {
            file = try JSONDecoder().decode(WizMarkFile.self, from: data)
        } catch {
            logger.error("Failed to decode .wizmark file: \(error.localizedDescription)")
            throw WizMarkImportError.invalidFormat(underlying: error)
        }

        let collection = BookmarkCollection(
            name: file.collectionName,
            icon: file.collectionIcon,
            color: file.collectionColor
        )
        context.insert(collection)

        for bm in file.bookmarks {
            let bookmark = Bookmark(
                url: bm.url,
                title: bm.title,
                description: nil,
                thumbnailUrl: bm.thumbnailUrl
            )
            bookmark.tags = bm.tags
            bookmark.note = bm.note
            bookmark.collection = collection
            context.insert(bookmark)
        }

        do {
            try context.save()
            logger.info(
                "Imported collection '\(file.collectionName)' with \(file.bookmarks.count) bookmarks"
            )
        } catch {
            logger.error("Failed to save imported data: \(error.localizedDescription)")
            throw WizMarkImportError.saveFailed(underlying: error)
        }
    }
}
