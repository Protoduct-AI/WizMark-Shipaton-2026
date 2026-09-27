import SwiftUI

// MARK: - Contribution Row

/// One bookmark an editor added to a shared collection.
///
/// Deliberately read-only and visually distinct from the owner's own rows:
/// these live in Convex, not in the local collection, so the swipe-to-remove
/// action that applies to the rest of the list would have nothing to act on.
struct ContributionRow: View {

    let contribution: ShareContribution

    var body: some View {
        Link(destination: URL(string: contribution.url) ?? URL(string: "https://example.com")!) {
            VStack(alignment: .leading, spacing: 4) {
                Text(contribution.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(contribution.siteName ?? URL(string: contribution.url)?.host() ?? contribution.url)
                        .lineLimit(1)
                    Text("·")
                    Text(String(
                        localized: "collection.detail.addedBy",
                        defaultValue: "\(contribution.contributorName) さんが追加"
                    ))
                    .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
