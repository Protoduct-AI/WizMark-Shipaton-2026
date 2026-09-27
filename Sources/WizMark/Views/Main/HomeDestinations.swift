import SwiftData

// MARK: - Navigation Destinations

/// Wraps a BookmarkCollection for use as a NavigationStack destination.
/// Conforms to Hashable via the persistent model ID.
struct AllBookmarksDestination: Hashable {}

struct CollectionNavDestination: Hashable {
    let collection: BookmarkCollection

    static func == (lhs: CollectionNavDestination, rhs: CollectionNavDestination) -> Bool {
        lhs.collection.persistentModelID == rhs.collection.persistentModelID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(collection.persistentModelID)
    }
}

/// Navigation destination for the member management screen of a collection.
struct CollectionMembersDestination: Hashable {
    let collection: BookmarkCollection

    static func == (lhs: CollectionMembersDestination, rhs: CollectionMembersDestination) -> Bool {
        lhs.collection.persistentModelID == rhs.collection.persistentModelID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(collection.persistentModelID)
    }
}
