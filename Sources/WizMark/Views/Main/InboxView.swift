import SwiftUI
import SwiftData

/// Shows unsorted bookmarks (those without a collection).
/// Kept as a standalone view so it can be embedded anywhere.
struct InboxView: View {

    @Query(
        filter: #Predicate<Bookmark> { $0.collection == nil },
        sort: \Bookmark.createdAt,
        order: .reverse
    )
    private var unsortedBookmarks: [Bookmark]

    @Environment(\.modelContext) private var modelContext
    @State private var deleteError: Error?

    var body: some View {
        Group {
            if unsortedBookmarks.isEmpty {
                ContentUnavailableView(
                    String(localized: "inbox.emptyTitle", defaultValue: "All organized!"),
                    systemImage: "tray",
                    description: Text(String(localized: "inbox.emptyDescription", defaultValue: "Bookmarks without a collection appear here."))
                )
            } else {
                List {
                    ForEach(unsortedBookmarks) { bookmark in
                        BookmarkCardView(bookmark: bookmark)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteBookmark(bookmark)
                                } label: {
                                    Label(String(localized: "common.delete", defaultValue: "Delete"), systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .errorAlert(error: $deleteError)
    }

    private func deleteBookmark(_ bookmark: Bookmark) {
        do {
            modelContext.delete(bookmark)
            try modelContext.save()
        } catch {
            deleteError = error
        }
    }
}
