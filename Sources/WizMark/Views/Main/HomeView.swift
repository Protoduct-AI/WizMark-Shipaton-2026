import ClerkKit
import Humation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import os

// MARK: - HomeView

/// The single main screen of WizMark.
/// Shows All Bookmarks, SNS smart collections, and user collections.
/// Bookmarks arrive primarily through the share extension.
///
/// Data is read directly via SwiftData `@Query` -- no ViewModel needed.
/// CloudKit sync happens automatically through the ModelContainer.
struct HomeView: View {

    // MARK: - SwiftData Queries

    @Query(sort: [SortDescriptor(\Bookmark.displayOrder), SortDescriptor(\Bookmark.createdAt, order: .reverse)])
    private var allBookmarks: [Bookmark]

    @Query(sort: \BookmarkCollection.createdAt)
    private var allCollections: [BookmarkCollection]

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router

    @State private var joinResultMessage: String?

    // MARK: - State

    @State private var showAddCollection: Bool = false
    @State private var showProfile: Bool = false
    @State private var showInbox: Bool = false
    @State private var showSignIn: Bool = false
    @State private var navigationPath = NavigationPath()
    @State private var searchQuery: String = ""
    @State private var editingCollection: BookmarkCollection?
    @State private var deletingCollection: BookmarkCollection?
    @State private var showDeleteConfirmation: Bool = false
    @State private var exportFileURL: URL?
    @State private var showExportShare: Bool = false

    // MARK: - Computed

    /// Root collections (no parent), already sorted by createdAt via @Query.
    private var rootCollections: [BookmarkCollection] {
        allCollections.filter { $0.parent == nil }
    }

    /// Whether search is active (non-empty query after trimming).
    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Collections matching the current search query (or all root collections when empty).
    private var filteredCollections: [BookmarkCollection] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return rootCollections }
        return rootCollections.filter { $0.name.lowercased().contains(query) }
    }

    /// Bookmarks matching the current search query by title, URL, description, or tags.
    /// Returns empty when the search query is blank (the main list shows sections instead).
    private var filteredBookmarks: [Bookmark] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return allBookmarks.filter { bookmark in
            bookmark.title.lowercased().contains(query)
                || bookmark.url.lowercased().contains(query)
                || (bookmark.bookmarkDescription?.lowercased().contains(query) ?? false)
                || bookmark.tags.contains { $0.lowercased().contains(query) }
                || (bookmark.note?.lowercased().contains(query) ?? false)
                || (bookmark.aiSummary?.lowercased().contains(query) ?? false)
                || (bookmark.aiTags?.contains { $0.lowercased().contains(query) } ?? false)
                || (bookmark.aiCategory?.lowercased().contains(query) ?? false)
                || (bookmark.aiPlaceName?.lowercased().contains(query) ?? false)
                || (bookmark.aiPlaceAddress?.lowercased().contains(query) ?? false)
                || (bookmark.aiPhoneNumber?.lowercased().contains(query) ?? false)
                || (bookmark.aiBusinessHours?.lowercased().contains(query) ?? false)
                || (bookmark.aiRecipe?.lowercased().contains(query) ?? false)
                || (bookmark.aiRating?.lowercased().contains(query) ?? false)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navigationPath) {
            homeContent
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // The bell sits opposite the profile: what arrives on the
                    // left, who you are on the right.
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showInbox = true
                        } label: {
                            let unread = services.inbox?.unreadCount ?? 0
                            Image(systemName: unread > 0 ? "bell.badge.fill" : "bell")
                                .font(.body)
                                .foregroundStyle(unread > 0 ? Color.accentColor : Color.secondary)
                                .accessibilityLabel(
                                    unread > 0
                                        ? String(
                                            localized: "inbox.accessibility.unread",
                                            defaultValue: "お知らせ \(unread) 件"
                                        )
                                        : String(localized: "inbox.notifications.title", defaultValue: "お知らせ")
                                )
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        AnimatedGradientTitle()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            NavigationLink {
                                SubscriptionView()
                            } label: {
                                Image(systemName: services.purchases.isSubscribed ? "crown.fill" : "crown")
                                    .font(.body)
                                    .foregroundStyle(.yellow)
                            }

                            Button {
                                showProfile = true
                            } label: {
                                UserAvatarView(pixels: 64)
                                    .frame(width: 30, height: 30)
                                    .clipShape(Circle())
                            }
                        }
                    }
                }
                .navigationDestination(for: AllBookmarksDestination.self) { _ in
                    allBookmarksList
                }
                .navigationDestination(for: CollectionNavDestination.self) { destination in
                    collectionBookmarkList(collection: destination.collection)
                }
                .navigationDestination(for: SNSFilterDestination.self) { destination in
                    snsFilteredList(destination: destination)
                }
                .navigationDestination(for: SharedCollectionDestination.self) { destination in
                    SharedCollectionDetailView(destination: destination)
                }
                .navigationDestination(for: SharedBookmarkDestination.self) { destination in
                    SharedBookmarkDetailView(destination: destination)
                }
                .navigationDestination(for: CollectionMembersDestination.self) { destination in
                    CollectionMembersView(collection: destination.collection)
                }
                .navigationDestination(for: Bookmark.self) { bookmark in
                    bookmarkDetailView(bookmark: bookmark)
                }
                // An invitation link may arrive while the app is running or be
                // what launched it. Either way the code lands in the router and
                // is redeemed here, where the share service is reachable.
                .onChange(of: router.pendingShareCode) { _, code in
                    guard code != nil else { return }
                    redeemPendingInvitation()
                }
                .task { redeemPendingInvitation() }
                .alert(
                    String(localized: "shared.join.title", defaultValue: "コレクションに参加"),
                    isPresented: Binding(
                        get: { joinResultMessage != nil },
                        set: { if !$0 { joinResultMessage = nil } }
                    )
                ) {
                    Button("OK") { joinResultMessage = nil }
                } message: {
                    if let joinResultMessage { Text(joinResultMessage) }
                }
                .sheet(isPresented: $showProfile) {
                    ProfileView()
                }
                .sheet(isPresented: $showInbox) {
                    NotificationInboxView()
                }
                .sheet(isPresented: $showAddCollection) {
                    NavigationStack {
                        CollectionFormView(mode: .create())
                    }
                }
                .sheet(isPresented: $showSignIn) {
                    NavigationStack {
                        SignInView(viewModel: AuthViewModel())
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button(String(localized: "common.cancel")) {
                                        showSignIn = false
                                    }
                                }
                            }
                    }
                }
        }
    }

    // MARK: - Home Content

    @ViewBuilder
    private var homeContent: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if isSearching {
                        searchResultsList
                    } else {
                        mainList
                    }
                }

                // FAB
                Button {
                    showAddCollection = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor, in: Circle())
                        .shadow(radius: 4, y: 2)
                }
                .padding(20)
            }

            // Banner Ad (non-Pro users only)
            if !services.purchases.shouldHideAds {
                BannerAdView(adUnitID: AdConfig.bannerUnitID)
                    .frame(height: 50)
            }
        }
        .searchable(
            text: $searchQuery,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: String(localized: "home.searchPrompt", defaultValue: "Search bookmarks and collections")
        )
    }

    // MARK: - Main List

    @ViewBuilder
    private var mainList: some View {
        List {
            // Section 1: All Bookmarks
            Section {
                NavigationLink(value: AllBookmarksDestination()) {
                    Label(
                        String(localized: "home.allBookmarks", defaultValue: "All Bookmarks"),
                        systemImage: "bookmark.fill"
                    )
                    .badge(allBookmarks.count)
                }
            }

            // Section 2: User collections (from SwiftData / CloudKit)
            if !rootCollections.isEmpty {
                Section(String(localized: "home.collectionsLabel", defaultValue: "Collections")) {
                    ForEach(filteredCollections) { collection in
                        NavigationLink(value: CollectionNavDestination(collection: collection)) {
                            HStack(spacing: 12) {
                                Image(systemName: collection.icon ?? "folder.fill")
                                    .frame(width: 28, height: 28)
                                    .foregroundStyle(
                                        collection.color != nil
                                            ? Color(hex: collection.color!)
                                            : Color.accentColor
                                    )
                                Text(collection.name)
                                Spacer()
                                if collection.bookmarkCount > 0 {
                                    Text("\(collection.bookmarkCount)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            // Section 2b: Collections shared by other iCloud users.
            // Renders nothing when no share has been accepted.
            SharedCollectionsSection()

            // Section 3: SNS (always visible)
            Section(String(localized: "home.section.sns", defaultValue: "SNS")) {
                ForEach(SNSCollection.all) { sns in
                    NavigationLink(
                        value: SNSFilterDestination(
                            name: sns.name,
                            assetName: sns.assetName,
                            domainPatterns: sns.domainPatterns
                        )
                    ) {
                        HStack(spacing: 12) {
                            Image(sns.assetName)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 28, height: 28)
                                .clipShape(.rect(cornerRadius: 6))
                            Text(sns.name)
                            Spacer()
                            let count = snsBookmarkCount(for: sns)
                            if count > 0 {
                                Text("\(count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - SNS Bookmark Count

    /// Counts bookmarks whose URL matches any domain pattern for the given SNS collection.
    private func snsBookmarkCount(for sns: SNSCollection) -> Int {
        allBookmarks.filter { sns.matches(url: $0.url) }.count
    }

    // MARK: - SNS Filtered List

    /// A destination view showing bookmarks filtered by SNS domain patterns.
    @ViewBuilder
    private func snsFilteredList(destination: SNSFilterDestination) -> some View {
        let filtered = allBookmarks.filter { bookmark in
            let lowered = bookmark.url.lowercased()
            return destination.domainPatterns.contains { lowered.contains($0) }
        }

        Group {
            if filtered.isEmpty {
                ContentUnavailableView(
                    "\(destination.name)",
                    systemImage: "bookmark",
                    description: Text(String(
                        localized: "home.snsEmpty",
                        defaultValue: "No bookmarks from \(destination.name) yet."
                    ))
                )
            } else {
                List {
                    ForEach(filtered) { bookmark in
                        NavigationLink(value: bookmark) {
                            BookmarkCardView(bookmark: bookmark)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(bookmark)
                            } label: {
                                Label(String(localized: "common.delete", defaultValue: "削除"), systemImage: "trash")
                            }
                        }
                    }
                    .onMove { source, destination in
                        reorderBookmarks(filtered, from: source, to: destination)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(destination.name)
    }

    // MARK: - Collection Bookmark List

    @ViewBuilder
    private func collectionBookmarkList(collection: BookmarkCollection) -> some View {
        let bookmarks = allBookmarks.filter { $0.collection?.persistentModelID == collection.persistentModelID }
        // The home list only shows roots, so a collection given a parent is
        // reachable nowhere else: without this section it vanishes from the app
        // the moment it is nested.
        let subCollections = allCollections
            .filter { $0.parent?.persistentModelID == collection.persistentModelID }
            .sorted { $0.createdAt < $1.createdAt }
        // Rows an editor added to the shared copy. They live in Convex, not in
        // this collection, so they are read-only here.
        let contributions = services.shares?.share(for: collection)?.contributions ?? []

        Group {
            if bookmarks.isEmpty && subCollections.isEmpty && contributions.isEmpty {
                ContentUnavailableView(
                    collection.name,
                    systemImage: collection.icon ?? "folder",
                    description: Text(String(localized: "collection.detail.emptyDescription", defaultValue: "Save bookmarks to this collection to see them here."))
                )
            } else {
                List {
                    if !subCollections.isEmpty {
                        Section(String(
                            localized: "collection.detail.subCollections",
                            defaultValue: "コレクション"
                        )) {
                            ForEach(subCollections) { child in
                                NavigationLink(value: CollectionNavDestination(collection: child)) {
                                    subCollectionRow(child)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        deletingCollection = child
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label(String(localized: "common.delete", defaultValue: "削除"), systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }

                    Section {
                        ForEach(bookmarks) { bookmark in
                            NavigationLink(value: bookmark) {
                                BookmarkCardView(bookmark: bookmark)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    modelContext.delete(bookmark)
                                } label: {
                                    Label(String(localized: "common.delete", defaultValue: "削除"), systemImage: "trash")
                                }
                            }
                        }
                        .onMove { source, destination in
                            reorderBookmarks(bookmarks, from: source, to: destination)
                        }
                    }

                    if !contributions.isEmpty {
                        Section(String(
                            localized: "collection.detail.contributions",
                            defaultValue: "メンバーが追加"
                        )) {
                            ForEach(contributions) { contribution in
                                ContributionRow(contribution: contribution)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(collection.name)
        // Publishing otherwise only happens when an invitation link is made, so
        // everything the owner changed afterwards never reached the members.
        .task { await services.shares?.resyncIfShared(collection) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Level 2: Share collection as formatted text
                    // "Share" means inviting someone into the collection. It used
                    // to hand over a text dump, which left the real sharing
                    // buried under Edit and made two unrelated features compete
                    // for the same word.
                    NavigationLink(value: CollectionMembersDestination(collection: collection)) {
                        Label(String(localized: "collection.detail.share", defaultValue: "共有"), systemImage: "person.badge.plus")
                    }

                    Divider()

                    ShareLink(
                        item: collectionShareText(collection: collection, bookmarks: bookmarks)
                    ) {
                        Label(
                            String(localized: "collection.detail.shareAsText", defaultValue: "テキストとして送る"),
                            systemImage: "text.alignleft"
                        )
                    }

                    Button {
                        exportFileURL = generateWizMarkFile(collection: collection, bookmarks: bookmarks)
                        if exportFileURL != nil {
                            showExportShare = true
                        }
                    } label: {
                        Label(String(localized: "collection.detail.export", defaultValue: "エクスポート (.wizmark)"), systemImage: "square.and.arrow.up.on.square")
                    }

                    Divider()

                    Button {
                        editingCollection = collection
                    } label: {
                        Label(String(localized: "collection.detail.edit", defaultValue: "編集"), systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        deletingCollection = collection
                        showDeleteConfirmation = true
                    } label: {
                        Label(String(localized: "collection.detail.delete", defaultValue: "削除"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $editingCollection) { col in
            NavigationStack {
                CollectionFormView(mode: .edit(col))
            }
        }
        .confirmationDialog(
            String(localized: "collection.detail.deleteTitle", defaultValue: "コレクションを削除"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "collection.detail.delete", defaultValue: "削除"), role: .destructive) {
                if let col = deletingCollection {
                    modelContext.delete(col)
                    try? modelContext.save()
                }
            }
        } message: {
            Text(String(localized: "collection.detail.deleteConfirm", defaultValue: "このコレクションを削除しますか？ブックマークは残ります。"))
        }
        .sheet(isPresented: $showExportShare) {
            if let fileURL = exportFileURL {
                ShareSheetView(activityItems: [fileURL])
            }
        }
    }

    /// One nested collection, shown inside its parent.
    @ViewBuilder
    private func subCollectionRow(_ child: BookmarkCollection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: child.icon ?? "folder.fill")
                .frame(width: 28, height: 28)
                .foregroundStyle(child.color != nil ? Color(hex: child.color!) : Color.accentColor)
            Text(child.name)
            Spacer()
            if child.bookmarkCount > 0 {
                Text("\(child.bookmarkCount)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Bookmark Detail

    @ViewBuilder
    private func bookmarkDetailView(bookmark: Bookmark) -> some View {
        BookmarkDetailScreen(bookmark: bookmark)
    }

    // MARK: - All Bookmarks Destination

    /// Builds a navigation destination that represents "All Bookmarks".
    @ViewBuilder
    private var allBookmarksList: some View {
        Group {
            if allBookmarks.isEmpty {
                ContentUnavailableView(
                    String(localized: "home.allBookmarks", defaultValue: "All Bookmarks"),
                    systemImage: "bookmark",
                    description: Text(String(localized: "home.allBookmarks.empty", defaultValue: "ブックマークがまだありません"))
                )
            } else {
                List {
                    ForEach(allBookmarks) { bookmark in
                        NavigationLink(value: bookmark) {
                            BookmarkCardView(bookmark: bookmark)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(bookmark)
                            } label: {
                                Label(String(localized: "common.delete", defaultValue: "削除"), systemImage: "trash")
                            }
                        }
                    }
                    .onMove { source, destination in
                        reorderBookmarks(Array(allBookmarks), from: source, to: destination)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(String(localized: "home.allBookmarks", defaultValue: "All Bookmarks"))
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsList: some View {
        let matchingCollections = filteredCollections
        let matchingBookmarks = filteredBookmarks

        if matchingCollections.isEmpty && matchingBookmarks.isEmpty {
            ContentUnavailableView.search(text: searchQuery)
        } else {
            List {
                if !matchingCollections.isEmpty {
                    Section {
                        ForEach(matchingCollections) { collection in
                            NavigationLink(value: CollectionNavDestination(collection: collection)) {
                                Label {
                                    Text(collection.name)
                                } icon: {
                                    if let icon = collection.icon, !icon.isEmpty {
                                        Image(systemName: icon)
                                    } else {
                                        Image(systemName: "folder.fill")
                                    }
                                }
                                .badge(collection.bookmarkCount)
                            }
                        }
                    } header: {
                        Text(String(localized: "home.collectionsLabel", defaultValue: "Collections"))
                    }
                }

                if !matchingBookmarks.isEmpty {
                    Section {
                        ForEach(matchingBookmarks) { bookmark in
                            BookmarkCardView(bookmark: bookmark)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        modelContext.delete(bookmark)
                                    } label: {
                                        Label(String(localized: "common.delete", defaultValue: "削除"), systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        Text(String(localized: "search.bookmarks", defaultValue: "Bookmarks"))
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
    // MARK: - Reorder

    private func reorderBookmarks(_ bookmarks: [Bookmark], from source: IndexSet, to destination: Int) {
        var items = bookmarks
        items.move(fromOffsets: source, toOffset: destination)
        for (index, bookmark) in items.enumerated() {
            bookmark.displayOrder = index
        }
    }

    /// Redeems an invitation code captured from a deep link.
    ///
    /// Joining needs an account, so an unauthenticated tap reports that rather
    /// than silently dropping the invitation; the code stays pending until it
    /// either succeeds or is explicitly reported as failed.
    private func redeemPendingInvitation() {
        guard let code = router.pendingShareCode else { return }
        guard let shares = services.shares else {
            joinResultMessage = String(
                localized: "shared.join.signInRequired",
                defaultValue: "招待を受けるにはサインインが必要です。"
            )
            router.pendingShareCode = nil
            return
        }

        router.pendingShareCode = nil
        Task {
            do {
                let name = try await shares.join(shareCode: code)
                joinResultMessage = String(
                    format: String(
                        localized: "shared.join.success",
                        defaultValue: "「%@」に参加しました。"
                    ),
                    name
                )
            } catch {
                // The owner opening their own link is a normal thing to do, so
                // it gets its own wording rather than looking like a broken link.
                let isOwner = error.localizedDescription.contains("already_owner")
                joinResultMessage = isOwner
                    ? String(
                        localized: "shared.join.alreadyOwner",
                        defaultValue: "これはあなたが共有しているコレクションです。"
                    )
                    : String(
                        localized: "shared.join.failed",
                        defaultValue: "招待リンクが無効か、共有が解除されています。"
                    )
            }
        }
    }

}

// MARK: - Sharing Helpers

extension HomeView {

    /// Level 2: Build a formatted text string for sharing a collection.
    func collectionShareText(collection: BookmarkCollection, bookmarks: [Bookmark]) -> String {
        var text = "\u{1F4C1} \(collection.name)\n\n"
        if bookmarks.isEmpty {
            text += String(localized: "collection.share.empty", defaultValue: "(ブックマークなし)")
        } else {
            let lines = bookmarks.map { "\u{2022} \($0.title) - \($0.url)" }
            text += lines.joined(separator: "\n")
        }
        return text
    }

    /// Level 3: Generate a .wizmark JSON export file and return its temporary URL.
    func generateWizMarkFile(collection: BookmarkCollection, bookmarks: [Bookmark]) -> URL? {
        let export = WizMarkExport(
            collectionName: collection.name,
            icon: collection.icon,
            color: collection.color,
            bookmarks: bookmarks.map { bookmark in
                WizMarkExport.BookmarkEntry(
                    url: bookmark.url,
                    title: bookmark.title,
                    tags: bookmark.tags,
                    note: bookmark.note
                )
            }
        )

        do {
            let data = try JSONEncoder().encode(export)
            let sanitizedName = collection.name
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
            let fileName = "\(sanitizedName).wizmark"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: tempURL)
            return tempURL
        } catch {
            os.Logger(subsystem: "com.protoductai.wizmark", category: "export")
                .error("Failed to generate .wizmark file: \(error.localizedDescription)")
            return nil
        }
    }
}

