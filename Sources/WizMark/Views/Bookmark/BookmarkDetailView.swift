import SwiftUI
import SwiftData
import UIKit
import os

// MARK: - BookmarkDetailView

/// Displays full bookmark details including OGP preview, AI enrichment,
/// tags, place info, notes, and metadata.
///
/// Toolbar provides Edit, Share, and Delete actions.
/// The view observes the SwiftData @Model directly for automatic updates
/// (e.g. when AI enrichment completes and syncs via CloudKit).
struct BookmarkDetailView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showEditSheet: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var error: Error?

    /// The bookmark to display. SwiftData @Model objects are observable,
    /// so the view updates automatically when properties change.
    let bookmark: Bookmark

    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "BookmarkDetailView")

    // MARK: - Body

    var body: some View {
        detailContent(bookmark)
            .background(Color.wizmarkBackground)
            .navigationTitle(String(localized: "bookmark.detail.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    toolbarActions
                }
            }
            .alert(
                String(localized: "bookmark.detail.deleteTitle"),
                isPresented: $showDeleteConfirmation
            ) {
                Button(String(localized: "common.cancel"), role: .cancel) {}
                Button(String(localized: "bookmark.detail.delete"), role: .destructive) {
                    performDelete()
                }
            } message: {
                Text("bookmark.detail.deleteConfirm", bundle: .main)
            }
            .sheet(isPresented: $showEditSheet) {
                BookmarkFormView(bookmark: bookmark)
            }
            .errorAlert(error: $error)
    }

    // MARK: - Detail Content

    private func detailContent(_ bookmark: Bookmark) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Hero thumbnail
                heroImage(bookmark)

                VStack(alignment: .leading, spacing: 12) {
                    // Title
                    Text(bookmark.title)
                        .font(.title2.bold())
                        .foregroundStyle(Color.wizmarkText)

                    // URL row
                    urlRow(bookmark)

                    // Description
                    if let description = bookmark.bookmarkDescription, !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(Color.wizmarkText.opacity(0.8))
                            .lineSpacing(4)
                    }

                    Divider()
                        .background(Color.wizmarkSeparator)

                    // AI Status
                    if bookmark.isEnriching {
                        aiEnrichingIndicator
                    } else if bookmark.isEnrichmentFailed {
                        aiErrorIndicator(bookmark.aiError)
                    }

                    // AI Summary
                    if let summary = bookmark.aiSummary {
                        aiSummarySection(summary)
                    }

                    // Tags
                    if !bookmark.tags.isEmpty {
                        tagsSection(bookmark.tags)
                    }

                    // AI Tags (additional tags from enrichment)

                    // Category
                    if let category = bookmark.aiCategory {
                        categoryBadge(category)
                    }

                    // Place info
                    if bookmark.aiPlaceName != nil || bookmark.aiPlaceAddress != nil {
                        placeSection(bookmark)
                    }

                    // AI Extracted Details
                    if bookmark.aiPhoneNumber != nil || bookmark.aiBusinessHours != nil
                        || bookmark.aiEventDateTime != nil || bookmark.aiRecipe != nil
                        || bookmark.aiRating != nil {
                        aiDetailsSection(bookmark)
                    }

                    // Notes (always visible — shows placeholder when empty)
                    RichNoteEditor(
                        text: Binding(
                            get: { bookmark.note },
                            set: { bookmark.note = $0; bookmark.updatedAt = Date() }
                        ),
                        richData: Binding(
                            get: { bookmark.noteRichData },
                            set: { bookmark.noteRichData = $0 }
                        ),
                        onSave: { try? modelContext.save() }
                    )

                    // Metadata
                    metadataSection(bookmark)
                }
                .padding(.horizontal, 16)

                // Open in Safari button
                openInSafariButton
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Hero Image

    @ViewBuilder
    private func heroImage(_ bookmark: Bookmark) -> some View {
        if let thumbnailUrl = bookmark.thumbnailUrl, let url = URL(string: thumbnailUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipped()
                case .failure:
                    faviconHero(bookmark)
                case .empty:
                    Color.wizmarkSurfaceVariant
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay {
                            ProgressView()
                                .tint(Color.wizmarkAccent)
                        }
                @unknown default:
                    faviconHero(bookmark)
                }
            }
        } else {
            faviconHero(bookmark)
        }
    }

    private func faviconHero(_ bookmark: Bookmark) -> some View {
        HStack {
            Spacer()
            if let faviconUrl = bookmark.favicon, let url = URL(string: faviconUrl) {
                AsyncImage(url: url) { image in
                    image.resizable()
                } placeholder: {
                    Image(systemName: "globe")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.wizmarkTextMuted)
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.wizmarkTextMuted)
            }
            Spacer()
        }
        .frame(height: 100)
        .background(Color.wizmarkSurfaceVariant)
    }

    // MARK: - URL Row

    private func urlRow(_ bookmark: Bookmark) -> some View {
        Button {
            openInSafari()
        } label: {
            HStack(spacing: 6) {
                if let faviconUrl = bookmark.favicon, let url = URL(string: faviconUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable()
                    } placeholder: {
                        Image(systemName: "globe")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.wizmarkTextMuted)
                    }
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.wizmarkTextMuted)
                }

                Text(bookmark.url)
                    .font(.subheadline)
                    .foregroundStyle(Color.wizmarkTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.wizmarkAccent)
            }
        }
    }

    // MARK: - AI Summary

    private func aiSummarySection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.wizmarkAccentSecondary)

                Text("AI")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.wizmarkAccentSecondary)
                    .clipShape(Capsule())

                Text("bookmark.detail.aiSummary", bundle: .main)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.wizmarkTextSecondary)
            }

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(Color.wizmarkText.opacity(0.85))
                .lineSpacing(4)
        }
        .padding(12)
        .background(Color.wizmarkSurfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.wizmarkAccentSecondary.opacity(0.2), lineWidth: 0.5)
        )
    }

    private func aiErrorIndicator(_ message: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.wizmarkError)

            Text(message ?? String(localized: "bookmark.detail.aiExtractionFailed", defaultValue: "AI抽出に失敗しました"))
                .font(.subheadline)
                .foregroundStyle(Color.wizmarkTextSecondary)

            Spacer()

            Button {
                bookmark.aiStatus = "pending"
                try? modelContext.save()
                Task {
                    await AIExtractionService.shared.process(bookmark: bookmark, context: modelContext)
                }
            } label: {
                Text(String(localized: "bookmark.detail.retry", defaultValue: "再試行"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.wizmarkAccent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.wizmarkError.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.wizmarkError.opacity(0.2), lineWidth: 0.5)
        )
    }

    private var aiEnrichingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.wizmarkAccentSecondary)

            Text("bookmark.detail.enriching", bundle: .main)
                .font(.subheadline)
                .foregroundStyle(Color.wizmarkTextSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.wizmarkSurfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Tags

    private func tagsSection(_ tags: [String]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.wizmarkText.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.wizmarkSurfaceTertiary)
                    .clipShape(Capsule())
            }
        }
    }

    private func aiTagsSection(_ aiTags: [String], existingTags: [String]) -> some View {
        let existingSet = Set(existingTags.map { $0.lowercased() })
        let uniqueAiTags = aiTags.filter { !existingSet.contains($0.lowercased()) }

        return Group {
            if !uniqueAiTags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.wizmarkAccentSecondary)
                        Text("bookmark.detail.suggestedTags", bundle: .main)
                            .font(.caption)
                            .foregroundStyle(Color.wizmarkTextMuted)
                    }

                    FlowLayout(spacing: 8) {
                        ForEach(uniqueAiTags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.wizmarkAccentSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.wizmarkAccentSecondary.opacity(0.1))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.wizmarkAccentSecondary.opacity(0.3), lineWidth: 0.5)
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Category Badge

    private func categoryBadge(_ category: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "tag.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.wizmarkAccent)

            Text(category)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.wizmarkAccent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.wizmarkAccent.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Place Section

    private func placeSection(_ bookmark: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.wizmarkError)

                Text("bookmark.detail.placeInfo", bundle: .main)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.wizmarkTextSecondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let name = bookmark.aiPlaceName, !name.isEmpty {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.wizmarkText)
                }

                if let address = bookmark.aiPlaceAddress, !address.isEmpty {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(Color.wizmarkTextSecondary)
                }

                if let mapUrl = bookmark.aiPlaceMapUrl, let url = URL(string: mapUrl) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "map.fill")
                                .font(.system(size: 12))
                            Text("bookmark.detail.openMap", bundle: .main)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(Color.wizmarkAccent)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(12)
        .background(Color.wizmarkSurfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.wizmarkBorder.opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: - AI Details Section

    private func aiDetailsSection(_ bookmark: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.wizmarkAccentSecondary)

                Text(String(localized: "bookmark.detail.aiExtractedInfo", defaultValue: "AI 抽出情報"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.wizmarkTextSecondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                if let phone = bookmark.aiPhoneNumber, !phone.isEmpty {
                    aiDetailRow(icon: "phone.fill", label: phone, isLink: true, url: "tel:\(phone)")
                }
                if let hours = bookmark.aiBusinessHours, !hours.isEmpty {
                    aiDetailRow(icon: "clock.fill", label: hours)
                }
                if let event = bookmark.aiEventDateTime, !event.isEmpty {
                    aiDetailRow(icon: "calendar", label: event)
                }
                if let rating = bookmark.aiRating, !rating.isEmpty {
                    aiDetailRow(icon: "star.fill", label: rating)
                }
                if let recipe = bookmark.aiRecipe, !recipe.isEmpty {
                    aiDetailRow(icon: "fork.knife", label: recipe)
                }
            }
        }
        .padding(12)
        .background(Color.wizmarkSurfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.wizmarkBorder.opacity(0.5), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func aiDetailRow(icon: String, label: String, isLink: Bool = false, url: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.wizmarkAccentSecondary)
                .frame(width: 16)
                .padding(.top, 2)

            if isLink, let urlString = url, let linkUrl = URL(string: urlString) {
                Link(label, destination: linkUrl)
                    .font(.subheadline)
                    .foregroundStyle(Color.wizmarkAccent)
            } else {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Color.wizmarkText)
            }
        }
    }

    // MARK: - Notes Section
    // Replaced by the shared RichNoteEditor component.

    // MARK: - Metadata Section

    private func metadataSection(_ bookmark: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            metadataRow(
                icon: "calendar",
                label: String(localized: "bookmark.detail.created"),
                value: bookmark.createdAt.formatted(date: .abbreviated, time: .shortened)
            )

            if let collectionName = bookmark.collection?.name {
                metadataRow(
                    icon: "folder",
                    label: String(localized: "bookmark.detail.collection"),
                    value: collectionName
                )
            }

            if let ogType = bookmark.ogType {
                metadataRow(
                    icon: "doc.text",
                    label: String(localized: "bookmark.detail.type"),
                    value: ogType
                )
            }
        }
        .padding(.top, 4)
    }

    private func metadataRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.wizmarkTextMuted)
                .frame(width: 16)

            Text(label)
                .font(.caption)
                .foregroundStyle(Color.wizmarkTextMuted)

            Spacer()

            Text(value)
                .font(.caption)
                .foregroundStyle(Color.wizmarkTextSecondary)
        }
    }

    // MARK: - Open in Safari Button

    private var openInSafariButton: some View {
        Button {
            openInSafari()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "safari")
                    .font(.system(size: 16, weight: .medium))
                Text("bookmark.detail.open", bundle: .main)
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(.white)
            .background(Color.wizmarkAccent)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Toolbar

    private var toolbarActions: some View {
        HStack(spacing: 12) {
            Button {
                showEditSheet = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.wizmarkAccent)
            }

            if let url = URL(string: bookmark.url) {
                ShareLink(
                    item: url,
                    subject: Text(bookmark.title),
                    message: Text(shareContent())
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.wizmarkAccent)
                }
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.wizmarkError)
            }
        }
    }

    // MARK: - Actions

    private func openInSafari() {
        guard let url = URL(string: bookmark.url) else { return }
        UIApplication.shared.open(url)
    }

    private func shareContent() -> String {
        if bookmark.title.isEmpty || bookmark.title == bookmark.url {
            return bookmark.url
        }
        return "\(bookmark.title)\n\(bookmark.url)"
    }

    private func performDelete() {
        do {
            modelContext.delete(bookmark)
            try modelContext.save()
            dismiss()
        } catch {
            self.error = error
            logger.error("Delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - FlowLayout (shared with BookmarkFormView)

/// A horizontal flow layout that wraps children to the next line.
/// Duplicated here to keep the file self-contained; extract to a shared
/// Components directory if used in three or more places.
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
