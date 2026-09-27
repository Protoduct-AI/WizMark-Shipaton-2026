import Foundation
import SwiftData
import os

@Observable
@MainActor
final class CollectionService {

    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "CollectionService")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Queries

    func fetchAll() -> [BookmarkCollection] {
        let descriptor = FetchDescriptor<BookmarkCollection>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchRootCollections() -> [BookmarkCollection] {
        let descriptor = FetchDescriptor<BookmarkCollection>(
            predicate: #Predicate<BookmarkCollection> { $0.parent == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func children(of parent: BookmarkCollection) -> [BookmarkCollection] {
        let parentId = parent.persistentModelID
        let descriptor = FetchDescriptor<BookmarkCollection>(
            predicate: #Predicate<BookmarkCollection> { $0.parent?.persistentModelID == parentId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Mutations

    @discardableResult
    func create(
        name: String,
        icon: String? = nil,
        color: String? = nil,
        parent: BookmarkCollection? = nil
    ) -> BookmarkCollection {
        let collection = BookmarkCollection(name: name, icon: icon, color: color)
        collection.parent = parent
        modelContext.insert(collection)
        save()
        logger.info("Collection created: \(name, privacy: .public)")
        return collection
    }

    func rename(_ collection: BookmarkCollection, to newName: String) {
        collection.name = newName
        save()
        logger.info("Collection renamed to \(newName, privacy: .public)")
    }

    func delete(_ collection: BookmarkCollection) {
        let name = collection.name
        modelContext.delete(collection)
        save()
        logger.info("Collection removed: \(name, privacy: .public)")
    }

    // MARK: - Private

    private func save() {
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save: \(error.localizedDescription, privacy: .public)")
        }
    }
}
