import SwiftUI

// MARK: - SharedCollectionDestination

/// Navigation destination for a collection shared by another user.
///
/// Carries only the identity. The screen re-resolves its subject from
/// ``ShareService`` on every render, so an update from the owner reaches a
/// screen that is already open instead of leaving a stale copy on display.
struct SharedCollectionDestination: Hashable {
    let collectionID: String

    init(_ collectionID: String) {
        self.collectionID = collectionID
    }
}

// MARK: - SharedCollectionDetailView

/// Read-only detail screen for a shared collection.
///
/// Participants hold read access, so no editing, deleting or reordering is
/// offered. Tapping a bookmark opens its detail screen.
struct SharedCollectionDetailView: View {

    let destination: SharedCollectionDestination

    @Environment(AppServices.self) private var services

    @State private var error: String?

    private var collection: SharedCollection? {
        services.shares?.sharedWithMe.first { $0.id == destination.collectionID }
    }

    var body: some View {
        Group {
            if let collection {
                content(for: collection)
            } else {
                // The share disappeared: the owner stopped sharing, or the
                // participant was removed. Say so rather than showing a blank.
                ContentUnavailableView(
                    String(
                        localized: "shared.collection.unavailable.title",
                        defaultValue: "コレクションを表示できません"
                    ),
                    systemImage: "person.2.slash",
                    description: Text(String(
                        localized: "shared.collection.unavailable.message",
                        defaultValue: "共有が解除されたか、アクセス権がなくなった可能性があります。"
                    ))
                )
            }
        }
        .navigationTitle(collection?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            String(localized: "common.error", defaultValue: "エラー"),
            isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )
        ) {
            Button("OK") { error = nil }
        } message: {
            if let error { Text(error) }
        }
    }

    private func remove(_ bookmark: SharedBookmark) {
        guard let shares = services.shares else { return }
        Task {
            do {
                try await shares.removeBookmark(id: bookmark.id)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func content(for collection: SharedCollection) -> some View {
        if collection.isEmpty {
            ContentUnavailableView(
                collection.name,
                systemImage: collection.icon ?? "folder",
                description: Text(String(
                    localized: "shared.collection.empty",
                    defaultValue: "このコレクションにはまだブックマークがありません。"
                ))
            )
        } else {
            List {
                Section(String(localized: "search.bookmarks", defaultValue: "Bookmarks")) {
                    ForEach(collection.bookmarks) { bookmark in
                        NavigationLink(
                            value: SharedBookmarkDestination(
                                collectionID: collection.id,
                                bookmarkID: bookmark.id
                            )
                        ) {
                            SharedBookmarkRow(bookmark: bookmark)
                        }
                        // Only what this user contributed. The owner's rows
                        // mirror their own collection and come back on the next
                        // publish, so offering to delete them would be a lie.
                        .swipeActions(edge: .trailing) {
                            if bookmark.addedByMe == true {
                                Button(role: .destructive) {
                                    remove(bookmark)
                                } label: {
                                    Label(
                                        String(localized: "common.delete", defaultValue: "削除"),
                                        systemImage: "trash"
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

// MARK: - SharedBookmarkRow

/// Lightweight row for a shared bookmark.
///
/// `BookmarkCardView` requires a SwiftData `Bookmark`, which shared records are
/// deliberately not, so this renders straight from the Convex payload.
private struct SharedBookmarkRow: View {

    let bookmark: SharedBookmark

    private var subtitle: String {
        if let siteName = bookmark.siteName { return siteName }
        if let domain = bookmark.domain {
            return domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
        }
        return bookmark.url
    }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.title.isEmpty ? bookmark.url : bookmark.title)
                    .font(.body)
                    .lineLimit(2)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !bookmark.tags.isEmpty {
                    Text(bookmark.tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumbUrl = bookmark.thumbnailUrl, let url = URL(string: thumbUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholderIcon
                default:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 8))
        } else {
            placeholderIcon
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 8))
        }
    }

    private var placeholderIcon: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
        }
    }
}
