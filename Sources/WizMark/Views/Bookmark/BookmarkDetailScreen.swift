import SwiftUI
import SwiftData

// MARK: - Bookmark Detail Screen

/// The bookmark detail screen reached from the lists in ``HomeView``.
///
/// Lives here rather than inside HomeView so that file stays about the home
/// screen itself; it is internal rather than private because HomeView now
/// references it across files.
struct BookmarkDetailScreen: View {

    let bookmark: Bookmark
    @State private var showFullImage = false
    @State private var showMapChooser = false
    @State private var mapTarget: ExtractedPlace?
    @State private var showEditSheet = false
    @State private var editingNote: String = ""
    @State private var editingTitle: String = ""
    @State private var isEditingMemo = false
    // FocusState for memo moved into RichNoteEditor component.

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // OGP Image
                if bookmark.showImage, let thumbUrl = bookmark.thumbnailUrl, let url = URL(string: thumbUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: 200)
                                .clipped()
                                .contentShape(Rectangle())
                                .onTapGesture { showFullImage = true }
                        default:
                            EmptyView()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(bookmark.title)
                        .font(.title3.bold())

                    if bookmark.showSiteName, let site = bookmark.siteName, !site.isEmpty {
                        Text(site)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Sits where the extracted fields will appear, so the wait
                    // happens in the same place as the result.
                    AIStatusBadge(bookmark: bookmark)

                    if bookmark.showAuthor, let author = bookmark.ogAuthor, !author.isEmpty {
                        Label(author, systemImage: "person")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if bookmark.showDescription, let desc = bookmark.bookmarkDescription, !desc.isEmpty {
                        ExpandableText(text: desc, lineLimit: 3)
                    }

                    if bookmark.showAiSummary, let summary = bookmark.aiSummary, !summary.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(String(localized: "bookmark.detail.aiSummaryLabel", defaultValue: "AI 要約"), systemImage: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if bookmark.showAiCategory, let category = bookmark.aiCategory, !category.isEmpty {
                        Label(category, systemImage: "folder")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }

                    Link(destination: URL(string: bookmark.url) ?? URL(string: "https://example.com")!) {
                        Label(bookmark.domain ?? bookmark.url, systemImage: "safari")
                            .font(.callout)
                    }

                    if bookmark.showCanonicalUrl, let canonical = bookmark.canonicalUrl, !canonical.isEmpty, canonical != bookmark.url {
                        Label(canonical, systemImage: "link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if bookmark.showOgType, let ogType = bookmark.ogType, !ogType.isEmpty {
                        Label(ogType, systemImage: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if bookmark.showLocale, let locale = bookmark.ogLocale, !locale.isEmpty {
                        Label(locale, systemImage: "globe")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if bookmark.showTags, !bookmark.tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(bookmark.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.tertiarySystemFill))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    // A round-up page yields several places, so they are listed
                    // rather than collapsed into one. Tapping opens maps;
                    // long-pressing still selects the text to copy.
                    if bookmark.showPlaceName || bookmark.showPlaceAddress {
                        let places = bookmark.extractedPlaces
                        if places.count > 1 {
                            Text(String(
                                localized: "bookmark.detail.placeCount",
                                defaultValue: "紹介されている場所 \(places.count) 件"
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        ForEach(Array(places.enumerated()), id: \.offset) { _, place in
                            placeEntry(place, showDivider: places.count > 1)
                        }
                    }

                    // One map for the whole page: a round-up of ten cafés is
                    // more useful as ten pins on one map than as ten maps.
                    if bookmark.showPlaceMap, !bookmark.extractedPlaces.isEmpty {
                        PlaceMapView(places: bookmark.extractedPlaces)
                    }

                    if bookmark.showDate {
                        Text(bookmark.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal)

                // Memo (rich note editor)
                Divider().padding(.horizontal)
                RichNoteEditor(
                    text: Binding(get: { bookmark.note }, set: { bookmark.note = $0 }),
                    richData: Binding(get: { bookmark.noteRichData }, set: { bookmark.noteRichData = $0 })
                )
                .padding(.horizontal)
            }
        }
        .confirmationDialog(
            String(localized: "map.chooser.title", defaultValue: "地図アプリで開く"),
            isPresented: $showMapChooser,
            titleVisibility: .visible
        ) {
            ForEach(MapLauncher.availableApps) { app in
                Button(app.label) {
                    MapLauncher.open(
                        in: app,
                        placeName: mapTarget?.name,
                        address: mapTarget?.address
                    )
                }
            }
        }
        // Applies to every Text on the screen rather than being sprinkled per
        // field: anything the extractor pulled out — an address, a phone
        // number, opening hours, a recipe — is something someone will want to
        // paste elsewhere, and the fields left out are the ones that read as
        // broken.
        .textSelection(.enabled)
        .navigationTitle(bookmark.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    ShareLink(
                        item: URL(string: bookmark.url) ?? URL(string: "https://example.com")!,
                        subject: Text(bookmark.title),
                        message: Text(bookmark.title)
                    )
                    Button {
                        editingNote = bookmark.note ?? ""
                        editingTitle = bookmark.title
                        showEditSheet = true
                    } label: {
                        Image(systemName: "pencil.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            NavigationStack {
                Form {
                    // Pages name themselves badly, and the fetched title is
                    // what the list shows from then on. Editing it was only
                    // possible through a screen nothing navigated to.
                    Section {
                        TextField(
                            String(localized: "bookmark.edit.titlePlaceholder", defaultValue: "タイトル"),
                            text: $editingTitle,
                            axis: .vertical
                        )
                        .lineLimit(1...4)
                        .onChange(of: editingTitle) { _, value in
                            if value.count > Bookmark.titleCharacterLimit {
                                editingTitle = String(value.prefix(Bookmark.titleCharacterLimit))
                            }
                        }
                    } header: {
                        Text(String(localized: "bookmark.edit.titleSection", defaultValue: "タイトル"))
                    }

                    let hasImage = bookmark.thumbnailUrl != nil
                    let hasDesc = bookmark.bookmarkDescription?.isEmpty == false
                    let hasTags = !bookmark.tags.isEmpty
                    let hasSite = bookmark.siteName?.isEmpty == false
                    let hasAuthor = bookmark.ogAuthor?.isEmpty == false
                    let hasFavicon = bookmark.favicon?.isEmpty == false
                    let hasOgType = bookmark.ogType?.isEmpty == false
                    let hasCanonical = bookmark.canonicalUrl?.isEmpty == false
                    let hasLocale = bookmark.ogLocale?.isEmpty == false
                    let hasAiSummary = bookmark.aiSummary?.isEmpty == false
                    let hasAiCategory = bookmark.aiCategory?.isEmpty == false
                    let hasPlace = bookmark.aiPlaceName?.isEmpty == false
                    let hasAddress = bookmark.aiPlaceAddress?.isEmpty == false
                    let hasMap = bookmark.aiPlaceMapUrl?.isEmpty == false

                    if hasImage || hasDesc || hasTags {
                        Section(String(localized: "bookmark.displaySettings.basic", defaultValue: "基本")) {
                            if hasImage { Toggle(String(localized: "bookmark.displaySettings.image", defaultValue: "画像"), isOn: .init(get: { bookmark.showImage }, set: { bookmark.showImage = $0 })) }
                            if hasDesc { Toggle(String(localized: "bookmark.displaySettings.description", defaultValue: "説明文"), isOn: .init(get: { bookmark.showDescription }, set: { bookmark.showDescription = $0 })) }
                            if hasTags { Toggle(String(localized: "bookmark.displaySettings.tags", defaultValue: "タグ"), isOn: .init(get: { bookmark.showTags }, set: { bookmark.showTags = $0 })) }
                            Toggle(String(localized: "bookmark.displaySettings.date", defaultValue: "日時"), isOn: .init(get: { bookmark.showDate }, set: { bookmark.showDate = $0 }))
                        }
                    }

                    if hasSite || hasAuthor || hasFavicon || hasOgType || hasCanonical || hasLocale {
                        Section(String(localized: "bookmark.displaySettings.ogpMetadata", defaultValue: "OGP メタデータ")) {
                            if hasSite { Toggle(String(localized: "bookmark.displaySettings.siteName", defaultValue: "サイト名"), isOn: .init(get: { bookmark.showSiteName }, set: { bookmark.showSiteName = $0 })) }
                            if hasAuthor { Toggle(String(localized: "bookmark.displaySettings.author", defaultValue: "著者"), isOn: .init(get: { bookmark.showAuthor }, set: { bookmark.showAuthor = $0 })) }
                            if hasFavicon { Toggle(String(localized: "bookmark.displaySettings.favicon", defaultValue: "ファビコン"), isOn: .init(get: { bookmark.showFavicon }, set: { bookmark.showFavicon = $0 })) }
                            if hasOgType { Toggle(String(localized: "bookmark.displaySettings.contentType", defaultValue: "コンテンツ種別"), isOn: .init(get: { bookmark.showOgType }, set: { bookmark.showOgType = $0 })) }
                            if hasCanonical { Toggle(String(localized: "bookmark.displaySettings.canonicalUrl", defaultValue: "正規URL"), isOn: .init(get: { bookmark.showCanonicalUrl }, set: { bookmark.showCanonicalUrl = $0 })) }
                            if hasLocale { Toggle(String(localized: "bookmark.displaySettings.locale", defaultValue: "言語"), isOn: .init(get: { bookmark.showLocale }, set: { bookmark.showLocale = $0 })) }
                        }
                    }

                    if hasAiSummary || hasAiCategory {
                        Section(String(localized: "bookmark.displaySettings.aiAnalysis", defaultValue: "AI 分析")) {
                            if hasAiSummary { Toggle(String(localized: "bookmark.displaySettings.aiSummary", defaultValue: "AI 要約"), isOn: .init(get: { bookmark.showAiSummary }, set: { bookmark.showAiSummary = $0 })) }
                            if hasAiCategory { Toggle(String(localized: "bookmark.displaySettings.aiCategory", defaultValue: "AI カテゴリ"), isOn: .init(get: { bookmark.showAiCategory }, set: { bookmark.showAiCategory = $0 })) }
                        }
                    }

                    if hasPlace || hasAddress || hasMap {
                        Section(String(localized: "bookmark.displaySettings.placeInfo", defaultValue: "場所情報")) {
                            if hasPlace { Toggle(String(localized: "bookmark.displaySettings.placeName", defaultValue: "場所名"), isOn: .init(get: { bookmark.showPlaceName }, set: { bookmark.showPlaceName = $0 })) }
                            if hasAddress { Toggle(String(localized: "bookmark.displaySettings.address", defaultValue: "住所"), isOn: .init(get: { bookmark.showPlaceAddress }, set: { bookmark.showPlaceAddress = $0 })) }
                            if hasMap { Toggle(String(localized: "bookmark.displaySettings.mapLink", defaultValue: "マップリンク"), isOn: .init(get: { bookmark.showPlaceMap }, set: { bookmark.showPlaceMap = $0 })) }
                        }
                    }

                    Section {
                        Link(destination: URL(string: bookmark.url) ?? URL(string: "https://example.com")!) {
                            Label(String(localized: "bookmark.displaySettings.openInSafari", defaultValue: "Safariで開く"), systemImage: "safari")
                        }
                    }
                }
                .navigationTitle(String(localized: "bookmark.displaySettings.title", defaultValue: "表示設定"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "common.done", defaultValue: "完了")) {
                            let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            // An empty title would leave the row showing a bare
                            // URL, so the previous one stands.
                            if !trimmed.isEmpty, trimmed != bookmark.title {
                                bookmark.title = trimmed
                                bookmark.updatedAt = Date()
                            }
                            showEditSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: $showFullImage) {
            if let thumbUrl = bookmark.thumbnailUrl, let url = URL(string: thumbUrl) {
                ZStack {
                    Color.black.ignoresSafeArea()
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        default:
                            ProgressView().tint(.white)
                        }
                    }
                }
                .onTapGesture { showFullImage = false }
                .overlay(alignment: .topTrailing) {
                    Button { showFullImage = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding()
                    }
                }
            }
        }
    }

    /// One place: name, address and whatever else the page stated.
    @ViewBuilder
    private func placeEntry(_ place: ExtractedPlace, showDivider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if showDivider {
                Divider().padding(.vertical, 2)
            }

            if let name = place.name, !name.isEmpty {
                placeRow(
                    text: name,
                    symbol: "mappin.and.ellipse",
                    font: .subheadline,
                    tint: .primary,
                    place: place
                )
            }

            if let address = place.address, !address.isEmpty {
                placeRow(
                    text: address,
                    symbol: "map",
                    font: .caption,
                    tint: .secondary,
                    place: place
                )
            }

            if let hours = place.hours, !hours.isEmpty {
                Label(hours, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let phone = place.phone, !phone.isEmpty {
                Label(phone, systemImage: "phone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let rating = place.rating, !rating.isEmpty {
                Label(rating, systemImage: "star")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A place line that opens maps on tap and stays selectable on long press.
    ///
    /// A plain `Button` would swallow the long press that starts a selection, so
    /// the tap is attached to the text itself.
    @ViewBuilder
    private func placeRow(
        text: String,
        symbol: String,
        font: Font,
        tint: Color,
        place: ExtractedPlace
    ) -> some View {
        let canOpen = MapLauncher.canOpen(placeName: place.name, address: place.address)

        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(font)
                .foregroundStyle(canOpen ? Color.accentColor : tint)

            Text(text)
                .font(font)
                .foregroundStyle(tint)

            if canOpen {
                Image(systemName: "arrow.up.forward.app")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard canOpen else { return }
            mapTarget = place
            showMapChooser = true
        }
    }

    // MARK: - Memo Helpers
    // Formatting helpers moved to RichNoteEditor component.
}
