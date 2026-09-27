import SwiftUI
import SwiftData
import os

// MARK: - BookmarkFormView

/// Full-screen sheet or pushed view for creating or editing a bookmark.
///
/// Layout mirrors the Expo `new.tsx` form:
/// 1. OGP preview card (thumbnail + inline title edit + URL + article info)
/// 2. Notes section
/// 3. Tag input with autocomplete suggestions and removable chips
/// 4. Collection picker (horizontal scroll of chips)
/// 5. Sticky save button at the bottom
struct BookmarkFormView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \BookmarkCollection.createdAt)
    private var allCollections: [BookmarkCollection]

    @Query(sort: \Bookmark.createdAt)
    private var allBookmarks: [Bookmark]

    @State private var url: String = ""
    @State private var title: String = ""
    @State private var bookmarkDescription: String = ""
    @State private var notes: String = ""
    @State private var tags: [String] = []
    @State private var tagInput: String = ""
    @State private var thumbnailUrl: String?
    @State private var faviconUrl: String?
    @State private var siteName: String?
    @State private var isEditingUrl: Bool = false
    @State private var selectedCollection: BookmarkCollection?
    @State private var isSaving: Bool = false
    @State private var error: Error?
    @State private var hasUserEditedTitle: Bool = false

    /// The bookmark being edited, or nil for creation mode.
    private let editingBookmark: Bookmark?

    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "BookmarkFormView")

    // MARK: - Init

    /// Create a new bookmark, optionally pre-filling URL and collection.
    init(
        initialUrl: String = "",
        initialCollection: BookmarkCollection? = nil
    ) {
        self.editingBookmark = nil
        _url = State(initialValue: initialUrl)
        _selectedCollection = State(initialValue: initialCollection)
    }

    /// Edit an existing bookmark.
    init(bookmark: Bookmark) {
        self.editingBookmark = bookmark
        _url = State(initialValue: bookmark.url)
        _title = State(initialValue: bookmark.title)
        _bookmarkDescription = State(initialValue: bookmark.bookmarkDescription ?? "")
        _notes = State(initialValue: bookmark.note ?? "")
        _thumbnailUrl = State(initialValue: bookmark.thumbnailUrl)
        _faviconUrl = State(initialValue: bookmark.favicon)
        _siteName = State(initialValue: bookmark.siteName)
        _selectedCollection = State(initialValue: bookmark.collection)
        _tags = State(initialValue: bookmark.tags)
        _hasUserEditedTitle = State(initialValue: true)
    }

    // MARK: - Computed

    private var isEditing: Bool { editingBookmark != nil }

    private var isValidUrl: Bool {
        guard let components = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil,
              let host = components.host, !host.isEmpty else {
            return false
        }
        return true
    }

    private var canSave: Bool {
        isValidUrl && !isSaving
    }

    private var hostname: String {
        guard let parsedUrl = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parsedUrl.host() else {
            return ""
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Compute tag suggestions from all bookmarks' tags, excluding already-selected tags.
    private var tagSuggestions: [TagInfo] {
        let query = tagInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }

        // Aggregate tag usage counts across all bookmarks.
        var tagCounts: [String: Int] = [:]
        for bookmark in allBookmarks {
            for tag in bookmark.tags {
                let lower = tag.lowercased()
                tagCounts[lower, default: 0] += 1
            }
        }

        let selectedSet = Set(tags.map { $0.lowercased() })
        return tagCounts
            .filter { !selectedSet.contains($0.key) && $0.key.contains(query) }
            .map { TagInfo(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 20) {
                        ogPreviewCard
                        notesSection
                        tagsSection
                        collectionSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 100)
                }
                .scrollDismissesKeyboard(.interactively)
                .dismissKeyboard()

                stickyBottomBar
            }
            .background(Color.wizmarkBackground)
            .navigationTitle(isEditing
                ? String(localized: "bookmark.edit.title")
                : String(localized: "bookmark.new.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                    .foregroundStyle(Color.wizmarkText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveButtonLabel) {
                        performSave()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .loadingOverlay(isLoading: isSaving)
            .errorAlert(error: $error)
        }
    }

    // MARK: - Save Button Label

    private var saveButtonLabel: String {
        if isSaving {
            return String(localized: "bookmark.new.saving")
        }
        return isEditing
            ? String(localized: "bookmark.edit.save")
            : String(localized: "bookmark.new.save")
    }

    // MARK: - OGP Preview Card

    private var ogPreviewCard: some View {
        VStack(spacing: 0) {
            thumbnailArea
            cardContent
        }
        .background(Color.wizmarkSurfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.wizmarkBorder.opacity(0.5), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var thumbnailArea: some View {
        if let thumbnailUrl, let url = URL(string: thumbnailUrl) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(16 / 9, contentMode: .fill)
                            .clipped()
                    case .failure:
                        thumbnailPlaceholder
                    case .empty:
                        thumbnailPlaceholder
                            .overlay {
                                ProgressView()
                                    .tint(Color.wizmarkAccent)
                            }
                    @unknown default:
                        thumbnailPlaceholder
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)

                Button {
                    self.thumbnailUrl = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .padding(8)
            }
        } else {
            thumbnailPlaceholder
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.wizmarkTextMuted)
                        Text("bookmark.new.noThumbnail", bundle: .main)
                            .font(.caption)
                            .foregroundStyle(Color.wizmarkTextMuted.opacity(0.7))
                    }
                }
        }
    }

    private var thumbnailPlaceholder: some View {
        Color.wizmarkSurfaceVariant
            .aspectRatio(16 / 9, contentMode: .fit)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Inline title editing
            TextField(
                String(localized: "bookmark.new.titlePlaceholder"),
                text: $title,
                axis: .vertical
            )
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.wizmarkText)
            .onChange(of: title) { _, _ in
                hasUserEditedTitle = true
            }

            // Site info row
            HStack(spacing: 6) {
                if let faviconUrl, let url = URL(string: faviconUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable()
                    } placeholder: {
                        Image(systemName: "globe")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.wizmarkTextMuted)
                    }
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.wizmarkTextMuted)
                }

                Text(siteInfoLabel)
                    .font(.caption)
                    .foregroundStyle(Color.wizmarkTextSecondary)
                    .lineLimit(1)

                Spacer()

                Button {
                    isEditingUrl.toggle()
                } label: {
                    Text(isEditingUrl
                        ? String(localized: "common.cancel")
                        : String(localized: "bookmark.new.editUrl"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.wizmarkAccent)
                }
            }

            // Expandable URL editing section
            if isEditingUrl {
                urlEditSection
            }
        }
        .padding(12)
    }

    private var siteInfoLabel: String {
        if let name = siteName, !name.isEmpty {
            return "\(name) \u{00B7} \(hostname)"
        }
        return hostname.isEmpty
            ? String(localized: "bookmark.new.urlLabel")
            : hostname
    }

    private var urlEditSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .background(Color.wizmarkSeparator)

            VStack(alignment: .leading, spacing: 2) {
                Text("URL")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.wizmarkTextMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)

                TextField(
                    "https://example.com",
                    text: $url
                )
                .font(.system(size: 13))
                .foregroundStyle(Color.wizmarkText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("bookmark.new.thumbnailUrlLabel", bundle: .main)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.wizmarkTextMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)

                TextField(
                    "https://example.com/og.png",
                    text: Binding(
                        get: { thumbnailUrl ?? "" },
                        set: { thumbnailUrl = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                    )
                )
                .font(.system(size: 13))
                .foregroundStyle(Color.wizmarkText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("bookmark.new.noteLabel", bundle: .main)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.wizmarkTextSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            TextField(
                String(localized: "bookmark.new.notePlaceholder"),
                text: $notes,
                axis: .vertical
            )
            .font(.system(size: 15))
            .foregroundStyle(Color.wizmarkText)
            .lineLimit(3...8)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.wizmarkSurfaceVariant)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.wizmarkBorder.opacity(0.4), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("bookmark.new.tagsLabel", bundle: .main)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.wizmarkTextSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            // Existing tags as removable chips
            if !tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        TagChipView(name: tag) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                removeTag(tag)
                            }
                        }
                    }
                }
            }

            // Tag input with autocomplete
            VStack(spacing: 0) {
                TextField(
                    String(localized: "bookmark.new.tagsPlaceholder"),
                    text: $tagInput
                )
                .font(.system(size: 15))
                .foregroundStyle(Color.wizmarkText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.wizmarkSurfaceVariant)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.wizmarkBorder.opacity(0.4), lineWidth: 0.5)
                )
                .onSubmit {
                    addTag(tagInput)
                }

                // Autocomplete suggestions
                if !tagSuggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(tagSuggestions.prefix(5))) { tag in
                            Button {
                                addTag(tag.name)
                            } label: {
                                HStack {
                                    Text("#\(tag.name)")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.wizmarkText)
                                    Spacer()
                                    Text("\(tag.count)")
                                        .font(.caption)
                                        .foregroundStyle(Color.wizmarkTextMuted)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }

                            if tag.id != tagSuggestions.prefix(5).last?.id {
                                Divider()
                                    .background(Color.wizmarkSeparator)
                            }
                        }
                    }
                    .background(Color.wizmarkSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.wizmarkBorder.opacity(0.5), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Collection Section

    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("bookmark.new.collectionLabel", bundle: .main)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.wizmarkTextSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // "No collection" / Inbox chip
                    CollectionChipView(
                        name: String(localized: "bookmark.new.noCollection"),
                        icon: "tray",
                        isSelected: selectedCollection == nil
                    ) {
                        selectedCollection = nil
                    }

                    // Collection chips
                    ForEach(allCollections) { collection in
                        CollectionChipView(
                            name: collection.name,
                            icon: collection.icon ?? "folder",
                            isSelected: selectedCollection?.persistentModelID == collection.persistentModelID,
                            color: collection.color
                        ) {
                            selectedCollection = collection
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    // MARK: - Sticky Bottom Bar

    private var stickyBottomBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.wizmarkSeparator.opacity(0.3))

            Button {
                performSave()
            } label: {
                Group {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(isEditing
                            ? String(localized: "bookmark.edit.save")
                            : String(localized: "bookmark.new.save"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.wizmarkAccent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .opacity(canSave ? 1 : 0.4)
            }
            .disabled(!canSave)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Tag Management

    private func addTag(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let lowered = trimmed.lowercased()
        guard !tags.contains(where: { $0.lowercased() == lowered }) else { return }
        tags.append(trimmed)
        tagInput = ""
    }

    private func removeTag(_ name: String) {
        tags.removeAll { $0.lowercased() == name.lowercased() }
    }

    // MARK: - Save

    private func performSave() {
        guard canSave else { return }

        let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? trimmedUrl
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDescription = bookmarkDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        isSaving = true
        defer { isSaving = false }

        do {
            if let existing = editingBookmark {
                // Update existing bookmark
                existing.url = trimmedUrl
                existing.title = resolvedTitle
                existing.bookmarkDescription = resolvedDescription.isEmpty ? nil : resolvedDescription
                existing.thumbnailUrl = thumbnailUrl
                existing.note = resolvedNotes.isEmpty ? nil : resolvedNotes
                existing.collection = selectedCollection
                existing.tags = tags
                existing.updatedAt = Date()
                try modelContext.save()
                logger.info("Bookmark updated: \(trimmedUrl, privacy: .public)")
            } else {
                // Create new bookmark
                let bookmark = Bookmark(
                    url: trimmedUrl,
                    title: resolvedTitle,
                    description: resolvedDescription.isEmpty ? nil : resolvedDescription,
                    thumbnailUrl: thumbnailUrl
                )
                bookmark.note = resolvedNotes.isEmpty ? nil : resolvedNotes
                bookmark.collection = selectedCollection
                bookmark.tags = tags
                bookmark.favicon = faviconUrl
                bookmark.siteName = siteName
                modelContext.insert(bookmark)
                try modelContext.save()
                logger.info("Bookmark created: \(trimmedUrl, privacy: .public)")
            }
            dismiss()
        } catch {
            self.error = error
            logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - TagChipView

/// A removable tag chip showing "#tagName" with an X button.
private struct TagChipView: View {

    let name: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("#\(name)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.wizmarkText)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.wizmarkTextMuted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.wizmarkSurfaceTertiary)
        .clipShape(Capsule())
    }
}

// MARK: - CollectionChipView

/// A selectable collection chip with icon and name.
private struct CollectionChipView: View {

    let name: String
    let icon: String
    let isSelected: Bool
    var color: String?
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? .white : Color.wizmarkText)
            .background(isSelected ? Color.wizmarkAccent : Color.wizmarkSurfaceVariant)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.wizmarkAccent : Color.wizmarkBorder.opacity(0.3),
                        lineWidth: 1
                    )
            )
        }
    }
}

// MARK: - FlowLayout

/// A horizontal flow layout that wraps children to the next line when they exceed
/// the available width. Used for tag chips.
private struct FlowLayout: Layout {

    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layoutSubviews(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalHeight = currentY + lineHeight
        }

        return LayoutResult(
            size: CGSize(width: maxWidth, height: totalHeight),
            positions: positions
        )
    }

    private struct LayoutResult {
        let size: CGSize
        let positions: [CGPoint]
    }
}
