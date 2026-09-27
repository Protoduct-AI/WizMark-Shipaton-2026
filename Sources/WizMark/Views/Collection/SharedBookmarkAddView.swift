import SwiftUI

/// Adds a bookmark to a collection someone else shared.
///
/// Editors get the same starting point as the owner does: paste a link and the
/// page's own title and description fill themselves in. Typing a title by hand
/// is a chore nobody does twice, and a list of bare URLs is not worth
/// contributing to.
///
/// Deliberately not a full editor. Tags, notes and AI extraction belong to
/// whoever owns the bookmark; this screen exists to get a link into the shared
/// list and nothing more.
struct SharedBookmarkAddView: View {

    let collectionID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    @State private var url = ""
    @State private var title = ""
    @State private var pageDescription: String?
    @State private var siteName: String?
    @State private var thumbnailUrl: String?

    @State private var isFetching = false
    @State private var isSaving = false
    @State private var error: String?

    /// The last URL metadata was fetched for, so editing the title does not
    /// trigger a refetch and overwrite what was just typed.
    @State private var fetchedURL: String?

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedURL.isEmpty && URL(string: trimmedURL)?.host != nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        String(localized: "shared.add.urlPlaceholder", defaultValue: "https://"),
                        text: $url
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit { Task { await fetchMetadata() } }
                } header: {
                    Text(String(localized: "shared.add.url", defaultValue: "URL"))
                } footer: {
                    if isFetching {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(String(
                                localized: "shared.add.fetching",
                                defaultValue: "ページの情報を取得しています"
                            ))
                        }
                    }
                }

                Section {
                    TextField(
                        String(localized: "shared.add.titlePlaceholder", defaultValue: "タイトル"),
                        text: $title
                    )
                } header: {
                    Text(String(localized: "shared.add.title", defaultValue: "タイトル"))
                }
            }
            .navigationTitle(String(
                localized: "shared.add.navigationTitle",
                defaultValue: "ブックマークを追加"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel", defaultValue: "キャンセル")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.add", defaultValue: "追加")) {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                }
            }
            .alert(
                String(localized: "common.error", defaultValue: "エラー"),
                isPresented: Binding(
                    get: { error != nil },
                    set: { if !$0 { error = nil } }
                )
            ) {
                Button("OK") { error = nil }
            } message: {
                if let error { Text(error) }
            }
            // Pasting a link is the common path, so the fetch starts on its own
            // rather than waiting for a button nobody expects to press.
            .onChange(of: url) { _, _ in
                Task { await fetchMetadataIfReady() }
            }
        }
    }

    private func fetchMetadataIfReady() async {
        guard URL(string: trimmedURL)?.host != nil, trimmedURL != fetchedURL else { return }
        await fetchMetadata()
    }

    private func fetchMetadata() async {
        guard let target = URL(string: trimmedURL), target.host != nil else { return }
        fetchedURL = trimmedURL
        isFetching = true
        defer { isFetching = false }

        let ogp = await OGPFetcher.shared.fetch(url: trimmedURL)

        // Never clobber a title the user has already written.
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = ogp.title ?? target.host ?? trimmedURL
        }
        pageDescription = ogp.description
        siteName = ogp.siteName
        thumbnailUrl = ogp.imageUrl
    }

    private func save() async {
        guard let shares = services.shares else {
            error = String(
                localized: "members.error.serviceUnavailable",
                defaultValue: "共有サービスに接続できません。サインイン状態を確認してください。"
            )
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await shares.addBookmark(
                collectionId: collectionID,
                url: trimmedURL,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: pageDescription,
                siteName: siteName,
                thumbnailUrl: thumbnailUrl
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
