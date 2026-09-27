import SwiftUI
import SwiftData

struct ShareSheetView: View {

    let sharedURL: String
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BookmarkCollection.createdAt) private var collections: [BookmarkCollection]

    @State private var title: String = ""
    @State private var thumbnailUrl: String?
    @State private var ogDescription: String?
    @State private var selectedCollection: BookmarkCollection?
    @State private var note: String = ""
    @State private var tags: String = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var fetchAiSummary = false
    @State private var fetchAiTags = false
    @State private var fetchAiCategory = false
    @State private var fetchAiPlaceName = false
    @State private var fetchAiPlaceAddress = false
    @State private var fetchAiPhoneNumber = false
    @State private var fetchAiBusinessHours = false
    @State private var fetchAiEventDateTime = false
    @State private var fetchAiRecipe = false
    @State private var fetchAiRating = false

    private var isPro: Bool {
        AppGroup.defaults?.bool(forKey: "is_pro_subscriber") ?? false
    }

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                collectionSection
                noteSection
                tagsSection
                aiSection
            }
            .navigationTitle(String(localized: "share.navigationTitle", defaultValue: "WizMark に保存"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel", defaultValue: "キャンセル")) { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(String(localized: "common.save", defaultValue: "保存")) { save() }
                            .bold()
                    }
                }
            }
        }
        .task { await fetchOGP() }
        .onChange(of: selectedCollection) { _, newCollection in
            applyCollectionDefaults(newCollection)
        }
    }

    private func applyCollectionDefaults(_ collection: BookmarkCollection?) {
        guard let collection else { return }
        fetchAiSummary = collection.defaultAiSummary
        fetchAiTags = collection.defaultAiTags
        fetchAiCategory = collection.defaultAiCategory
        fetchAiPlaceName = collection.defaultAiPlaceName
        fetchAiPlaceAddress = collection.defaultAiPlaceAddress
        fetchAiPhoneNumber = collection.defaultAiPhoneNumber
        fetchAiBusinessHours = collection.defaultAiBusinessHours
        fetchAiEventDateTime = collection.defaultAiEventDateTime
        fetchAiRecipe = collection.defaultAiRecipe
        fetchAiRating = collection.defaultAiRating
    }

    // MARK: - Sections

    private var previewSection: some View {
        Section {
            HStack(spacing: 12) {
                if let thumb = thumbnailUrl, let url = URL(string: thumb) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Color(.tertiarySystemFill)
                        }
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(.rect(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 4) {
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(String(localized: "share.fetchingData", defaultValue: "データ取得中..."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        // The fetched title is a starting point, not a verdict.
                        // Pages name themselves badly — a shop called "HOME",
                        // a recipe carrying the whole site name — and fixing it
                        // later means finding the bookmark again.
                        TextField(
                            String(localized: "share.titlePlaceholder", defaultValue: "タイトル"),
                            text: $title,
                            axis: .vertical
                        )
                        .font(.subheadline.bold())
                        .lineLimit(1...3)
                        .textFieldStyle(.plain)
                        .onChange(of: title) { _, value in
                            if value.count > Bookmark.titleCharacterLimit {
                                title = String(value.prefix(Bookmark.titleCharacterLimit))
                            }
                        }

                        if let desc = ogDescription, !desc.isEmpty {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Text(URL(string: sharedURL)?.host() ?? sharedURL)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var collectionSection: some View {
        Section(String(localized: "share.collection.header", defaultValue: "コレクション")) {
            Picker(String(localized: "share.collection.destination", defaultValue: "保存先"), selection: $selectedCollection) {
                Text(String(localized: "share.collection.uncategorized", defaultValue: "未分類"))
                    .tag(BookmarkCollection?.none)
                ForEach(collections) { col in
                    Label(col.name, systemImage: col.icon ?? "folder")
                        .tag(BookmarkCollection?.some(col))
                }
            }
            HStack {
                Toggle(String(localized: "share.ai.autoCategory", defaultValue: "AI 自動分類"), isOn: $fetchAiCategory)
                    .disabled(!isPro)
                if !isPro {
                    Text("PRO")
                        .font(.caption2.bold())
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.yellow.opacity(0.15), in: .capsule)
                }
            }
        }
    }

    private var noteSection: some View {
        Section(String(localized: "share.note.header", defaultValue: "メモ")) {
            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text(String(localized: "share.note.placeholder", defaultValue: "メモを追加（任意）"))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $note)
                    .frame(minHeight: 60, maxHeight: 120)
                    .scrollContentBackground(.hidden)
            }
        }
    }

    private var tagsSection: some View {
        Section(String(localized: "share.tags.header", defaultValue: "タグ")) {
            TextField(String(localized: "share.tags.placeholder", defaultValue: "カンマ区切り（例: tech, design）"), text: $tags)
                .autocorrectionDisabled()
        }
    }

    private func proToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(label, isOn: isOn)
            .disabled(!isPro)
    }

    private var aiSection: some View {
        Section {
            proToggle(String(localized: "share.ai.summary", defaultValue: "AI 要約を生成"), isOn: $fetchAiSummary)
            proToggle(String(localized: "share.ai.placeName", defaultValue: "店名を抽出"), isOn: $fetchAiPlaceName)
            proToggle(String(localized: "share.ai.placeAddress", defaultValue: "住所を抽出"), isOn: $fetchAiPlaceAddress)
            proToggle(String(localized: "share.ai.phoneNumber", defaultValue: "電話番号を抽出"), isOn: $fetchAiPhoneNumber)
            proToggle(String(localized: "share.ai.businessHours", defaultValue: "営業時間を抽出"), isOn: $fetchAiBusinessHours)
            proToggle(String(localized: "share.ai.eventDateTime", defaultValue: "イベント日時を抽出"), isOn: $fetchAiEventDateTime)
            proToggle(String(localized: "share.ai.recipe", defaultValue: "レシピを抽出"), isOn: $fetchAiRecipe)
            proToggle(String(localized: "share.ai.rating", defaultValue: "評価を抽出"), isOn: $fetchAiRating)
        } header: {
            HStack {
                Text(String(localized: "share.ai.header", defaultValue: "AI 抽出オプション"))
                if !isPro {
                    Text("PRO")
                        .font(.caption2.bold())
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.yellow.opacity(0.15), in: .capsule)
                }
            }
        } footer: {
            if isPro {
                Text(String(localized: "share.ai.disclaimer", defaultValue: "AIによる抽出結果は正確でない場合があります。重要な情報は必ずご自身でご確認ください。"))
            } else {
                Text(String(localized: "share.ai.proRequired", defaultValue: "AI機能を使うにはWizMark Proへの加入が必要です"))
            }
        }
    }

    // MARK: - Actions

    private func fetchOGP() async {
        let ogp = await OGPFetcher.shared.fetch(url: sharedURL)
        await MainActor.run {
            withAnimation(.none) {
                if let t = ogp.title, !t.isEmpty { title = t }
                thumbnailUrl = ogp.imageUrl
                ogDescription = ogp.description
                isLoading = false
            }
        }
    }

    private func save() {
        isSaving = true
        let bookmark = Bookmark(
            url: sharedURL,
            title: title.isEmpty ? sharedURL : title,
            description: ogDescription,
            thumbnailUrl: thumbnailUrl
        )
        bookmark.collection = selectedCollection
        bookmark.note = note.isEmpty ? nil : note
        bookmark.tags = tags.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        bookmark.requestAiSummary = fetchAiSummary
        bookmark.requestAiTags = fetchAiTags
        bookmark.requestAiCategory = fetchAiCategory
        bookmark.requestAiPlaceName = fetchAiPlaceName
        bookmark.requestAiPlaceAddress = fetchAiPlaceAddress
        bookmark.requestAiPhoneNumber = fetchAiPhoneNumber
        bookmark.requestAiBusinessHours = fetchAiBusinessHours
        bookmark.requestAiEventDateTime = fetchAiEventDateTime
        bookmark.requestAiRecipe = fetchAiRecipe
        bookmark.requestAiRating = fetchAiRating
        if fetchAiSummary || fetchAiTags || fetchAiCategory || fetchAiPlaceName || fetchAiPlaceAddress
            || fetchAiPhoneNumber || fetchAiBusinessHours || fetchAiEventDateTime || fetchAiRecipe || fetchAiRating {
            bookmark.aiStatus = "pending"
        }

        modelContext.insert(bookmark)
        try? modelContext.save()
        onDismiss()
    }
}
