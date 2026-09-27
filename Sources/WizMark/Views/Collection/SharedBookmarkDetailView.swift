import SwiftUI

// MARK: - SharedBookmarkDestination

/// Navigation destination for one bookmark inside a shared collection.
///
/// Carries both ids rather than the record itself so the screen re-resolves its
/// subject on every render. The owner republishing while this is open then
/// updates the screen instead of leaving a stale copy behind, and a bookmark
/// that disappears is reported rather than frozen.
struct SharedBookmarkDestination: Hashable {
    let collectionID: String
    let bookmarkID: String
}

// MARK: - SharedBookmarkDetailView

/// Read-only detail screen for a bookmark someone else shared.
///
/// The owner's own detail screen renders a SwiftData `Bookmark`; shared records
/// are deliberately not that, so this renders straight from the Convex payload.
/// Only what the owner published is available, which is why there is no editing,
/// no display-settings and no per-field toggles here — those belong to whoever
/// owns the bookmark.
struct SharedBookmarkDetailView: View {

    let destination: SharedBookmarkDestination

    @Environment(\.openURL) private var openURL
    @Environment(AppServices.self) private var services

    private var collection: SharedCollection? {
        services.shares?.sharedWithMe.first { $0.id == destination.collectionID }
    }

    private var bookmark: SharedBookmark? {
        collection?.bookmarks.first { $0.id == destination.bookmarkID }
    }

    var body: some View {
        Group {
            if let bookmark {
                content(for: bookmark)
            } else {
                ContentUnavailableView(
                    String(
                        localized: "shared.bookmark.unavailable.title",
                        defaultValue: "ブックマークを表示できません"
                    ),
                    systemImage: "bookmark.slash",
                    description: Text(String(
                        localized: "shared.bookmark.unavailable.message",
                        defaultValue: "共有元で削除されたか、共有が解除された可能性があります。"
                    ))
                )
            }
        }
        // Shared content is just as worth copying as your own.
        .textSelection(.enabled)
        .navigationTitle(bookmark?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = bookmark?.resolvedURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    // MARK: - Content

    private func content(for bookmark: SharedBookmark) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                thumbnail(for: bookmark)

                VStack(alignment: .leading, spacing: 8) {
                    Text(bookmark.title.isEmpty ? bookmark.url : bookmark.title)
                        .font(.title3.bold())

                    if let siteName = bookmark.siteName, !siteName.isEmpty {
                        Text(siteName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let description = bookmark.bookmarkDescription, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let summary = bookmark.aiSummary, !summary.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(
                                String(
                                    localized: "bookmark.detail.aiSummaryLabel",
                                    defaultValue: "AI 要約"
                                ),
                                systemImage: "sparkles"
                            )
                            .font(.caption)
                            .foregroundStyle(.yellow)

                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    linkRow(for: bookmark)

                    Text(Date(timeIntervalSince1970: bookmark.createdAt / 1000), style: .date)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if !bookmark.tags.isEmpty {
                    tagRow(for: bookmark)
                }

                // The owner's note travels with the share, so it is worth
                // showing — labelled as theirs, since it is not editable here.
                if let note = bookmark.note, !note.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            String(
                                localized: "shared.bookmark.ownerNote",
                                defaultValue: "共有元のメモ"
                            ),
                            systemImage: "text.alignleft"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Text(note)
                            .font(.body)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    @ViewBuilder
    private func linkRow(for bookmark: SharedBookmark) -> some View {
        if let url = bookmark.resolvedURL {
            Link(destination: url) {
                Label(bookmark.domain ?? bookmark.url, systemImage: "safari")
                    .font(.subheadline)
                    .lineLimit(1)
            }
        } else {
            // A URL that will not parse cannot be opened, and silently rendering
            // nothing would read as a broken screen.
            Label(bookmark.url, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func tagRow(for bookmark: SharedBookmark) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(bookmark.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemFill), in: Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private func thumbnail(for bookmark: SharedBookmark) -> some View {
        if let thumbUrl = bookmark.thumbnailUrl, let url = URL(string: thumbUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: 200)
                        .clipped()
                        .clipShape(.rect(cornerRadius: 12))
                default:
                    EmptyView()
                }
            }
        }
    }
}
