import ClerkKit
import SwiftData
import SwiftUI
import os

private var isProUser: Bool {
    AppGroup.defaults?.bool(forKey: "is_pro_subscriber") ?? false
}

// MARK: - CollectionFormView

/// Sheet form for creating or editing a collection.
/// Includes name input, optional color picker, optional icon picker,
/// and optional parent collection selection for hierarchy support.
///
/// Uses SwiftData + CloudKit for persistence. Save is synchronous
/// and does not require authentication.
struct CollectionFormView: View {

    // MARK: - Mode

    /// Determines whether the form creates a new collection or edits an existing one.
    enum Mode {
        case create(parent: BookmarkCollection? = nil)
        case edit(BookmarkCollection)

        var isEdit: Bool {
            if case .edit = self { return true }
            return false
        }

        var navigationTitle: String {
            switch self {
            case .create: String(localized: "collection.form.createTitle")
            case .edit: String(localized: "collection.form.editTitle")
            }
        }

        var submitLabel: String {
            switch self {
            case .create: String(localized: "collection.form.create")
            case .edit: String(localized: "common.save")
            }
        }
    }

    // MARK: - Properties

    let mode: Mode

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    // MARK: - Queries

    /// All root-level collections for the parent picker.
    @Query(
        filter: #Predicate<BookmarkCollection> { $0.parent == nil },
        sort: \BookmarkCollection.order
    )
    private var rootCollections: [BookmarkCollection]

    // MARK: - State

    @State private var name: String = ""
    @State private var selectedColor: String?
    @State private var selectedIcon: String?
    @State private var selectedParent: BookmarkCollection?
    @State private var showIconPicker: Bool = false

    @State private var defaultAiSummary = false
    @State private var defaultAiTags = false
    @State private var defaultAiCategory = false
    @State private var defaultAiPlaceName = false
    @State private var defaultAiPlaceAddress = false
    @State private var defaultAiPhoneNumber = false
    @State private var defaultAiBusinessHours = false
    @State private var defaultAiEventDateTime = false
    @State private var defaultAiRecipe = false
    @State private var defaultAiRating = false

    /// Set right after a collection is created, which drives the invite prompt.
    @State private var invitePromptCollection: BookmarkCollection?
    @State private var shareTarget: ShareTarget?
    @State private var isPreparingInvite = false
    @State private var showSignIn = false
    @State private var inviteError: String?

    // MARK: - Body

    var body: some View {
        Form {
            nameSection
            colorSection
            iconSection
            parentSection
            aiDefaultsSection
            if mode.isEdit {
                membersSection
            }
        }
        .navigationTitle(mode.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "common.cancel")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(mode.submitLabel) {
                    save()
                }
                .fontWeight(.semibold)
                .disabled(!isValid)
            }
        }
        .onAppear { populateFromMode() }
        .overlay {
            if isPreparingInvite {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView(String(
                        localized: "collection.invite.preparing",
                        defaultValue: "招待リンクを準備中..."
                    ))
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .alert(
            String(localized: "collection.invite.prompt.title", defaultValue: "友人を招待しますか？"),
            isPresented: Binding(
                get: { invitePromptCollection != nil },
                set: { if !$0 { invitePromptCollection = nil } }
            )
        ) {
            Button(String(localized: "collection.invite.prompt.invite", defaultValue: "招待する")) {
                prepareInvite()
            }
            Button(String(localized: "collection.invite.prompt.later", defaultValue: "あとで"), role: .cancel) {
                invitePromptCollection = nil
                dismiss()
            }
        } message: {
            Text(String(
                localized: "collection.invite.prompt.message",
                defaultValue: "このコレクションを共有すると、友人と一緒にブックマークを集められます。"
            ))
        }
        .alert(
            String(localized: "common.error", defaultValue: "エラー"),
            isPresented: Binding(
                get: { inviteError != nil },
                set: { if !$0 { inviteError = nil } }
            )
        ) {
            Button("OK") {
                inviteError = nil
                dismiss()
            }
        } message: {
            if let inviteError { Text(inviteError) }
        }
        .sheet(item: $shareTarget, onDismiss: { dismiss() }) { target in
            ActivityShareSheet(items: [target.url])
        }
        .sheet(isPresented: $showSignIn, onDismiss: { dismiss() }) {
            SignInSheetView()
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Name Section

    private var nameSection: some View {
        Section {
            TextField(
                String(localized: "collection.form.namePlaceholder"),
                text: $name
            )
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
        } header: {
            Text("collection.form.nameLabel")
        }
    }

    // MARK: - Color Section

    private var colorSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                ForEach(PresetColor.all) { preset in
                    colorCell(preset: preset)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("collection.form.colorLabel")
        }
    }

    private func colorCell(preset: PresetColor) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedColor = selectedColor == preset.hex ? nil : preset.hex
            }
        } label: {
            Circle()
                .fill(Color(hex: preset.hex))
                .frame(width: 36, height: 36)
                .overlay {
                    if selectedColor == preset.hex {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay(
                    Circle()
                        .strokeBorder(
                            selectedColor == preset.hex ? Color.wizmarkAccent : Color.wizmarkBorder,
                            lineWidth: selectedColor == preset.hex ? 2.5 : 0.5
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.name)
    }

    // MARK: - Icon Section

    private var iconSection: some View {
        Section {
            Button {
                showIconPicker = true
            } label: {
                HStack {
                    Text(String(localized: "collection.form.iconLabel"))
                        .foregroundStyle(.primary)
                    Spacer()
                    if let selectedIcon {
                        Image(systemName: selectedIcon)
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Text(String(localized: "collection.form.iconNone", defaultValue: "None"))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .sheet(isPresented: $showIconPicker) {
            SFSymbolPicker(selection: $selectedIcon)
        }
    }

    // MARK: - Parent Section

    private var parentSection: some View {
        Section {
            Picker(
                String(localized: "collection.form.parentLabel"),
                selection: $selectedParent
            ) {
                Text("collection.form.noParent")
                    .tag(BookmarkCollection?.none)

                ForEach(availableParents) { collection in
                    Label(collection.name, systemImage: collection.icon ?? "folder")
                        .tag(BookmarkCollection?.some(collection))
                }
            }
        } header: {
            Text("collection.form.hierarchyLabel")
        } footer: {
            Text("collection.form.hierarchyFooter")
        }
    }

    /// Collections available as parents. Excludes the collection being edited
    /// (and itself) to prevent circular references.
    private var availableParents: [BookmarkCollection] {
        if case .edit(let collection) = mode {
            return rootCollections.filter { $0.persistentModelID != collection.persistentModelID }
        }
        return rootCollections
    }

    // MARK: - AI Defaults Section

    private var aiDefaultsCount: Int {
        [defaultAiSummary, defaultAiCategory, defaultAiPlaceName,
         defaultAiPlaceAddress, defaultAiPhoneNumber, defaultAiBusinessHours,
         defaultAiEventDateTime, defaultAiRecipe, defaultAiRating].filter { $0 }.count
    }

    private var aiDefaultsSection: some View {
        Section {
            NavigationLink {
                aiDefaultsDetailView
            } label: {
                HStack {
                    Label(String(localized: "collection.form.aiExtraction", defaultValue: "AI 抽出オプション"), systemImage: "sparkles")
                    Spacer()
                    if aiDefaultsCount > 0 {
                        Text(String(localized: "collection.form.aiDefaults.count", defaultValue: "\(aiDefaultsCount)個 ON"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            Text(String(localized: "collection.form.aiDefaults.footer", defaultValue: "共有時にこのコレクションを選択すると、設定したオプションが自動でオンになります。"))
        }
    }

    private func proToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(label, isOn: isOn)
            .disabled(!isProUser)
    }

    private var aiDefaultsDetailView: some View {
        Form {
            Section {
                proToggle(String(localized: "collection.form.ai.summary", defaultValue: "AI 要約を生成"), isOn: $defaultAiSummary)
                proToggle(String(localized: "collection.form.ai.category", defaultValue: "コレクション自動分類"), isOn: $defaultAiCategory)
            } header: {
                HStack {
                    Text(String(localized: "collection.form.ai.analysis", defaultValue: "AI 分析"))
                    if !isProUser {
                        Text("PRO")
                            .font(.caption2.bold())
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.yellow.opacity(0.15), in: .capsule)
                    }
                }
            }

            Section {
                proToggle(String(localized: "collection.form.ai.placeName", defaultValue: "店名を抽出"), isOn: $defaultAiPlaceName)
                proToggle(String(localized: "collection.form.ai.placeAddress", defaultValue: "住所を抽出"), isOn: $defaultAiPlaceAddress)
                proToggle(String(localized: "collection.form.ai.phoneNumber", defaultValue: "電話番号を抽出"), isOn: $defaultAiPhoneNumber)
                proToggle(String(localized: "collection.form.ai.businessHours", defaultValue: "営業時間を抽出"), isOn: $defaultAiBusinessHours)
            } header: {
                Text(String(localized: "collection.form.ai.placeInfo", defaultValue: "場所情報"))
            }

            Section {
                proToggle(String(localized: "collection.form.ai.eventDateTime", defaultValue: "イベント日時を抽出"), isOn: $defaultAiEventDateTime)
                proToggle(String(localized: "collection.form.ai.recipe", defaultValue: "レシピを抽出"), isOn: $defaultAiRecipe)
                proToggle(String(localized: "collection.form.ai.rating", defaultValue: "評価を抽出"), isOn: $defaultAiRating)
            } header: {
                Text(String(localized: "collection.form.ai.other", defaultValue: "その他"))
            }
        }
        .navigationTitle(String(localized: "collection.form.aiExtraction", defaultValue: "AI 抽出オプション"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Members Section

    private var membersSection: some View {
        Section {
            if case .edit(let collection) = mode {
                NavigationLink {
                    CollectionMembersView(collection: collection)
                } label: {
                    Label(String(localized: "members.manage", defaultValue: "メンバー管理"), systemImage: "person.2")
                }
            }
        } header: {
            Text(String(localized: "members.sharing", defaultValue: "共有"))
        }
    }

    // MARK: - Populate

    private func populateFromMode() {
        switch mode {
        case .create(let parent):
            selectedParent = parent
        case .edit(let collection):
            name = collection.name
            selectedColor = collection.color
            selectedIcon = collection.icon
            selectedParent = collection.parent
            defaultAiSummary = collection.defaultAiSummary
            defaultAiTags = collection.defaultAiTags
            defaultAiCategory = collection.defaultAiCategory
            defaultAiPlaceName = collection.defaultAiPlaceName
            defaultAiPlaceAddress = collection.defaultAiPlaceAddress
            defaultAiPhoneNumber = collection.defaultAiPhoneNumber
            defaultAiBusinessHours = collection.defaultAiBusinessHours
            defaultAiEventDateTime = collection.defaultAiEventDateTime
            defaultAiRecipe = collection.defaultAiRecipe
            defaultAiRating = collection.defaultAiRating
        }
    }

    // MARK: - Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        switch mode {
        case .create:
            let collection = BookmarkCollection(
                name: trimmedName,
                icon: selectedIcon,
                color: selectedColor
            )
            collection.parent = selectedParent
            applyAiDefaults(to: collection)
            modelContext.insert(collection)
            try? modelContext.save()

            // Stay on screen so the invite prompt has somewhere to appear.
            // Dismissal happens once the prompt is answered.
            invitePromptCollection = collection

        case .edit(let existing):
            existing.name = trimmedName
            existing.icon = selectedIcon
            existing.color = selectedColor
            existing.parent = selectedParent
            applyAiDefaults(to: existing)
            try? modelContext.save()
            dismiss()
        }
    }

    // MARK: - Invite

    /// Publishes the freshly created collection and hands its invitation link to
    /// the system share sheet. Routes to sign-in when there is no account yet.
    private func prepareInvite() {
        guard let collection = invitePromptCollection else { return }
        invitePromptCollection = nil

        guard Clerk.shared.user != nil else {
            showSignIn = true
            return
        }
        guard let shares = services.shares else {
            inviteError = String(
                localized: "members.error.serviceUnavailable",
                defaultValue: "共有サービスに接続できません。サインイン状態を確認してください。"
            )
            return
        }

        isPreparingInvite = true
        Task {
            do {
                let code = try await shares.publish(collection)
                if let url = ShareService.invitationURL(shareCode: code) {
                    shareTarget = ShareTarget(url: url)
                } else {
                    inviteError = String(
                        localized: "collection.invite.error.noURL",
                        defaultValue: "招待リンクを取得できませんでした。"
                    )
                }
            } catch {
                inviteError = error.localizedDescription
            }
            isPreparingInvite = false
        }
    }

    private func applyAiDefaults(to collection: BookmarkCollection) {
        collection.defaultAiSummary = defaultAiSummary
        collection.defaultAiTags = defaultAiTags
        collection.defaultAiCategory = defaultAiCategory
        collection.defaultAiPlaceName = defaultAiPlaceName
        collection.defaultAiPlaceAddress = defaultAiPlaceAddress
        collection.defaultAiPhoneNumber = defaultAiPhoneNumber
        collection.defaultAiBusinessHours = defaultAiBusinessHours
        collection.defaultAiEventDateTime = defaultAiEventDateTime
        collection.defaultAiRecipe = defaultAiRecipe
        collection.defaultAiRating = defaultAiRating
    }
}

// MARK: - Preset Colors

/// A curated set of collection colors covering the full hue range.
private struct PresetColor: Identifiable {
    let hex: String
    let name: String

    var id: String { hex }

    static let all: [PresetColor] = [
        PresetColor(hex: "#EF4444", name: String(localized: "color.red")),
        PresetColor(hex: "#F97316", name: String(localized: "color.orange")),
        PresetColor(hex: "#EAB308", name: String(localized: "color.yellow")),
        PresetColor(hex: "#22C55E", name: String(localized: "color.green")),
        PresetColor(hex: "#14B8A6", name: String(localized: "color.teal")),
        PresetColor(hex: "#06B6D4", name: String(localized: "color.cyan")),
        PresetColor(hex: "#3B82F6", name: String(localized: "color.blue")),
        PresetColor(hex: "#6366F1", name: String(localized: "color.indigo")),
        PresetColor(hex: "#8B5CF6", name: String(localized: "color.violet")),
        PresetColor(hex: "#A855F7", name: String(localized: "color.purple")),
        PresetColor(hex: "#EC4899", name: String(localized: "color.pink")),
        PresetColor(hex: "#78716C", name: String(localized: "color.stone")),
    ]
}

// MARK: - Preset Icons

/// A curated set of SF Symbol icons suitable for collection categorization.
private struct PresetIcon: Identifiable {
    let symbolName: String
    let label: String

    var id: String { symbolName }

    static let all: [PresetIcon] = [
        PresetIcon(symbolName: "folder.fill", label: String(localized: "icon.folder")),
        PresetIcon(symbolName: "star.fill", label: String(localized: "icon.star")),
        PresetIcon(symbolName: "heart.fill", label: String(localized: "icon.heart")),
        PresetIcon(symbolName: "bookmark.fill", label: String(localized: "icon.bookmark")),
        PresetIcon(symbolName: "tag.fill", label: String(localized: "icon.tag")),
        PresetIcon(symbolName: "doc.text.fill", label: String(localized: "icon.document")),
        PresetIcon(symbolName: "book.fill", label: String(localized: "icon.book")),
        PresetIcon(symbolName: "link", label: String(localized: "icon.link")),
        PresetIcon(symbolName: "globe", label: String(localized: "icon.globe")),
        PresetIcon(symbolName: "briefcase.fill", label: String(localized: "icon.briefcase")),
        PresetIcon(symbolName: "cart.fill", label: String(localized: "icon.cart")),
        PresetIcon(symbolName: "fork.knife", label: String(localized: "icon.food")),
        PresetIcon(symbolName: "mappin.and.ellipse", label: String(localized: "icon.location")),
        PresetIcon(symbolName: "house.fill", label: String(localized: "icon.home")),
        PresetIcon(symbolName: "film.fill", label: String(localized: "icon.film")),
        PresetIcon(symbolName: "headphones", label: String(localized: "icon.headphones")),
        PresetIcon(symbolName: "gamecontroller.fill", label: String(localized: "icon.game")),
        PresetIcon(symbolName: "wrench.and.screwdriver.fill", label: String(localized: "icon.tools")),
        PresetIcon(symbolName: "lightbulb.fill", label: String(localized: "icon.idea")),
        PresetIcon(symbolName: "graduationcap.fill", label: String(localized: "icon.education")),
        PresetIcon(symbolName: "camera.fill", label: String(localized: "icon.camera")),
        PresetIcon(symbolName: "paintbrush.fill", label: String(localized: "icon.art")),
        PresetIcon(symbolName: "cpu", label: String(localized: "icon.tech")),
        PresetIcon(symbolName: "leaf.fill", label: String(localized: "icon.nature")),
    ]
}
