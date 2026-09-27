import SwiftUI

struct BookmarkCardView: View {

    let bookmark: Bookmark

    private var domain: String {
        guard let url = URL(string: bookmark.url),
              let host = url.host() else { return bookmark.url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.title.isEmpty ? bookmark.url : bookmark.title)
                    .font(.body)
                    .lineLimit(2)
                Text(domain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !bookmark.tags.isEmpty {
                    Text(bookmark.tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                AIStatusBadge(bookmark: bookmark, style: .full)
            }
        }
        .task {
            await fetchOGPIfNeeded()
        }
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

    private func fetchOGPIfNeeded() async {
        guard bookmark.thumbnailUrl == nil || bookmark.title.isEmpty || bookmark.bookmarkDescription == nil else { return }
        let ogp = await OGPFetcher.shared.fetch(url: bookmark.url)
        await MainActor.run {
            if let title = ogp.title, !title.isEmpty, bookmark.title.isEmpty {
                bookmark.title = title
            }
            if let img = ogp.imageUrl, bookmark.thumbnailUrl == nil {
                bookmark.thumbnailUrl = img
            }
            if let desc = ogp.description, bookmark.bookmarkDescription == nil {
                bookmark.bookmarkDescription = desc
            }
            if let site = ogp.siteName, bookmark.siteName == nil {
                bookmark.siteName = site
            }
        }
    }
}
