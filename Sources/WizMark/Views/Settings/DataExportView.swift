import SwiftUI
import SwiftData

// MARK: - DataExportView

/// Export all bookmarks and collections as a JSON file via the system share sheet.
struct DataExportView: View {

    // MARK: - Environment

    @Environment(AppServices.self) private var services

    // MARK: - Queries

    @Query private var bookmarks: [Bookmark]
    @Query private var collections: [BookmarkCollection]

    // MARK: - State

    @State private var isExporting = false
    @State private var exportedFileURL: URL?
    @State private var showShareSheet = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showPaywall = false

    private var isPro: Bool { services.purchases.isSubscribed }

    // MARK: - Body

    var body: some View {
        Form {
            if !isPro {
                Section {
                    HStack {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(.yellow)
                        Text(String(localized: "dataExport.proRequired", defaultValue: "データエクスポートはPro機能です"))
                            .font(.subheadline)
                    }
                    Button {
                        showPaywall = true
                    } label: {
                        Text("WizMark Pro")
                            .font(.headline)
                            .foregroundStyle(.yellow)
                    }
                }
            }
            descriptionSection
            dataOverviewSection
            exportSection
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { SubscriptionView() }
        }
        .navigationTitle(String(localized: "dataExport.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let fileURL = exportedFileURL {
                ShareSheet(activityItems: [fileURL])
            }
        }
        .alert(
            String(localized: "dataExport.failed"),
            isPresented: $showError,
            actions: {
                Button(String(localized: "common.ok"), role: .cancel) {}
            },
            message: {
                Text(errorMessage)
            }
        )
    }

    // MARK: - Sections

    private var descriptionSection: some View {
        Section {
            Text(String(localized: "dataExport.description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var dataOverviewSection: some View {
        Section(String(localized: "dataExport.dataOverview")) {
            LabeledContent(
                String(localized: "dataExport.bookmarkCount"),
                value: "\(bookmarks.count)"
            )
            LabeledContent(
                String(localized: "dataExport.collectionCount"),
                value: "\(collections.count)"
            )
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                Task { await exportData() }
            } label: {
                HStack {
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "dataExport.preparing"))
                    } else {
                        Image(systemName: "square.and.arrow.up")
                        Text(String(localized: "dataExport.exportJSON"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .disabled(isExporting || !isPro)
        } footer: {
            Text(String(localized: "dataExport.footer"))
                .font(.caption)
        }
    }

    // MARK: - Export Logic

    private func exportData() async {
        isExporting = true
        defer { isExporting = false }

        do {
            let payload = ExportPayload(
                exportedAt: Date(),
                bookmarks: bookmarks.map { ExportBookmark(from: $0) },
                collections: collections.map { ExportCollection(from: $0) }
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)

            let fileName = "wizmark-export-\(formattedDate()).json"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: tempURL)

            exportedFileURL = tempURL
            showShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - Export Models

private struct ExportPayload: Encodable {
    let exportedAt: Date
    let bookmarks: [ExportBookmark]
    let collections: [ExportCollection]
}

private struct ExportBookmark: Encodable {
    let url: String
    let title: String
    let description: String?
    let thumbnailUrl: String?
    let note: String?
    let tags: [String]
    let siteName: String?
    let favicon: String?
    let collectionName: String?
    let aiSummary: String?
    let aiTags: [String]?
    let aiCategory: String?
    let createdAt: Date
    let updatedAt: Date

    init(from bookmark: Bookmark) {
        self.url = bookmark.url
        self.title = bookmark.title
        self.description = bookmark.bookmarkDescription
        self.thumbnailUrl = bookmark.thumbnailUrl
        self.note = bookmark.note
        self.tags = bookmark.tags
        self.siteName = bookmark.siteName
        self.favicon = bookmark.favicon
        self.collectionName = bookmark.collection?.name
        self.aiSummary = bookmark.aiSummary
        self.aiTags = bookmark.aiTags
        self.aiCategory = bookmark.aiCategory
        self.createdAt = bookmark.createdAt
        self.updatedAt = bookmark.updatedAt
    }
}

private struct ExportCollection: Encodable {
    let name: String
    let icon: String?
    let color: String?
    let order: Int
    let parentName: String?
    let bookmarkCount: Int
    let createdAt: Date

    init(from collection: BookmarkCollection) {
        self.name = collection.name
        self.icon = collection.icon
        self.color = collection.color
        self.order = collection.order
        self.parentName = collection.parent?.name
        self.bookmarkCount = collection.bookmarkCount
        self.createdAt = collection.createdAt
    }
}

// MARK: - ShareSheet

/// UIKit share sheet wrapper for SwiftUI.
private struct ShareSheet: UIViewControllerRepresentable {

    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
