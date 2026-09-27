import SwiftUI

// MARK: - SharedCollectionsSection

/// The "shared with me" section of ``HomeView``.
///
/// Renders nothing when nobody has shared a collection with this user, so the
/// home screen of someone who never received an invitation is unchanged. Rows
/// are read-only: participants currently hold view access only.
struct SharedCollectionsSection: View {

    @Environment(AppServices.self) private var services

    var body: some View {
        if let shares = services.shares, !shares.sharedWithMe.isEmpty {
            Section(String(localized: "home.section.shared", defaultValue: "共有されたコレクション")) {
                ForEach(shares.sharedWithMe) { collection in
                    NavigationLink(value: SharedCollectionDestination(collection.id)) {
                        SharedCollectionRow(collection: collection)
                    }
                }
            }
        }
    }
}

// MARK: - SharedCollectionRow

/// A single shared collection row: icon, name, owner, and bookmark count.
struct SharedCollectionRow: View {

    let collection: SharedCollection

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: collection.icon ?? "folder.fill")
                    .frame(width: 28, height: 28)
                    .foregroundStyle(
                        collection.color != nil
                            ? Color(hex: collection.color!)
                            : Color.accentColor
                    )

                Image(systemName: "person.2.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(2)
                    .background(Color(.systemBackground), in: Circle())
                    .offset(x: 4, y: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)
                if let ownerName = collection.ownerName {
                    Text(
                        String(
                            format: String(
                                localized: "shared.ownerLabel",
                                defaultValue: "%@ さんから"
                            ),
                            ownerName
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if collection.bookmarkCount > 0 {
                Text("\(collection.bookmarkCount)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
