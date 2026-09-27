import ClerkKit
import Humation
import SwiftData
import SwiftUI

// MARK: - CollectionMembersView

/// Manages the invitation link and participant list for a collection.
///
/// Sharing runs through Convex: publishing uploads a snapshot of the collection
/// and returns an invitation code. Publishing requires an account, so an
/// unauthenticated tap routes to sign-in rather than failing.
struct CollectionMembersView: View {

    let collection: BookmarkCollection

    @Environment(AppServices.self) private var services

    @State private var shareCode: String?
    @State private var linkRole: ShareRole = .viewer
    @State private var isGeneratingLink = false
    @State private var shareTarget: ShareTarget?
    @State private var showSignIn = false
    @State private var error: String?

    private var shareURL: URL? {
        shareCode.flatMap(ShareService.invitationURL(shareCode:))
    }

    /// Read straight from the subscription rather than fetched once: joining,
    /// leaving and role changes all used to need the screen reopened before
    /// they showed up.
    private var participants: [ShareParticipant] {
        services.shares?.share(for: collection)?.participants ?? []
    }

    var body: some View {
        List {
            shareLinkSection
            membersSection
        }
        .navigationTitle(String(localized: "members.title", defaultValue: "メンバー管理"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "common.error", defaultValue: "エラー"), isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK") { error = nil }
        } message: {
            if let error { Text(error) }
        }
        .sheet(isPresented: $showSignIn) {
            SignInSheetView()
        }
        .sheet(item: $shareTarget) { target in
            ActivityShareSheet(items: [target.url])
        }
        .task { await loadExistingShare() }
    }

    // MARK: - Share Link Section

    private var shareLinkSection: some View {
        Section {
            if let shareURL {
                Text(shareURL.absoluteString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Plain rows rather than a prominent button: inside a List a
                // full-width button ignores the row insets and sits flush with
                // the cell edges. A row also lets the List own the tap, which a
                // ShareLink otherwise loses.
                Button {
                    shareTarget = ShareTarget(url: shareURL)
                } label: {
                    Label(
                        String(localized: "common.share", defaultValue: "共有"),
                        systemImage: "square.and.arrow.up"
                    )
                }

                // Applies to whoever redeems the link from here on. Members
                // who already joined keep the role they were given.
                Picker(
                    String(localized: "members.share.linkRole", defaultValue: "リンクの権限"),
                    selection: $linkRole
                ) {
                    ForEach(ShareRole.allCases) { role in
                        Text(role.label).tag(role)
                    }
                }
                .onChange(of: linkRole) { previous, role in
                    guard previous != role else { return }
                    updateLinkRole(to: role, revertingTo: previous)
                }

                Button(role: .destructive) {
                    revokeShare()
                } label: {
                    Label(
                        String(localized: "members.share.revoke", defaultValue: "共有を停止"),
                        systemImage: "person.2.slash"
                    )
                }
            } else {
                Button {
                    generateShareLink()
                } label: {
                    HStack {
                        Label(
                            String(localized: "members.share.generateLink", defaultValue: "招待リンクを発行"),
                            systemImage: "link.badge.plus"
                        )
                        Spacer()
                        if isGeneratingLink {
                            ProgressView()
                        }
                    }
                }
                .disabled(isGeneratingLink)
            }
        } header: {
            Text(String(localized: "members.share.inviteLink", defaultValue: "招待リンク"))
        } footer: {
            Text(String(
                localized: "members.share.inviteLink.footer.role",
                defaultValue: "リンクを知っている人がこのコレクションを開けます。発行時点の内容が共有され、再発行すると最新の内容に更新されます。権限を変えても、すでに参加している人の権限はそのままです。"
            ))
        }
    }

    // MARK: - Members Section

    private var membersSection: some View {
        Section {
            ownerRow

            ForEach(participants) { participant in
                memberRow(participant)
            }
        } header: {
            Text(String(
                localized: "members.section.header",
                defaultValue: "メンバー (\(participants.count + 1))"
            ))
        }
    }

    private var ownerRow: some View {
        HStack(spacing: 12) {
            ownerAvatar
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            VStack(alignment: .leading) {
                Text(ownerName)
                    .font(.body)
                Text(String(localized: "members.role.owner", defaultValue: "オーナー"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(localized: "members.role.admin", defaultValue: "管理者"))
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Capsule())
        }
        .frame(minHeight: Self.memberRowHeight)
    }

    private func memberRow(_ member: ShareParticipant) -> some View {
        HStack(spacing: 12) {
            memberAvatar(seed: member.clerkId)
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            Text(member.displayName)
                .font(.body)
            Spacer()
            Menu {
                ForEach(ShareRole.allCases) { role in
                    Button {
                        updateMemberRole(member, to: role)
                    } label: {
                        if member.shareRole == role {
                            Label(role.label, systemImage: "checkmark")
                        } else {
                            Text(role.label)
                        }
                    }
                }

                Divider()

                Button(role: .destructive) {
                    removeMember(member)
                } label: {
                    Label(
                        String(localized: "members.removeMember", defaultValue: "メンバーを削除"),
                        systemImage: "person.badge.minus"
                    )
                }
            } label: {
                Text(member.shareRole.label)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
            }
        }
        .frame(minHeight: Self.memberRowHeight)
    }

    /// Keeps the owner row (name plus a subtitle) and member rows (name only)
    /// the same height, so the list does not look ragged.
    private static let memberRowHeight: CGFloat = 44

    // MARK: - Avatars

    private var ownerAvatar: some View {
        UserAvatarView(pixels: 72)
    }

    private var ownerName: String {
        let user = Clerk.shared.user
        let name = "\(user?.firstName ?? "") \(user?.lastName ?? "")".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? String(localized: "members.owner.self", defaultValue: "自分") : name
    }

    private func memberAvatar(seed: String) -> some View {
        Group {
            if let img = Humation.image(seed: seed, pixels: 72) {
                Image(uiImage: img).resizable()
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Actions


    /// Publishes the collection and shows the resulting invitation link.
    private func generateShareLink() {
        guard Clerk.shared.user != nil else {
            showSignIn = true
            return
        }
        guard let shares = services.shares else {
            error = String(
                localized: "members.error.serviceUnavailable",
                defaultValue: "共有サービスに接続できません。サインイン状態を確認してください。"
            )
            return
        }

        isGeneratingLink = true
        Task {
            do {
                shareCode = try await shares.publish(collection)
                await refreshShareState()
            } catch {
                self.error = error.localizedDescription
            }
            isGeneratingLink = false
        }
    }

    /// Loads an already-issued link so it survives reopening the screen.
    private func loadExistingShare() async {
        guard Clerk.shared.user != nil, let shares = services.shares else { return }
        do {
            if let existing = try await shares.myShare(for: collection) {
                shareCode = existing.shareCode
                linkRole = existing.linkRole
            }
        } catch {
            // Not being published yet is the normal case, so this stays quiet.
        }
    }

    /// Participants come from the subscription now; this only re-reads the
    /// link state, which a mutation can change.
    private func refreshShareState() async {
        guard let shares = services.shares else { return }
        let existing = try? await shares.myShare(for: collection)
        if let existing { linkRole = existing.linkRole }
    }

    /// Persists the role future joiners get.
    ///
    /// The picker has already moved by the time this runs, so a failure puts it
    /// back rather than leaving the UI claiming a permission the server never
    /// accepted.
    private func updateLinkRole(to role: ShareRole, revertingTo previous: ShareRole) {
        guard let shares = services.shares else { return }
        Task {
            do {
                guard let existing = try await shares.myShare(for: collection) else {
                    throw ShareUIError.notPublished
                }
                try await shares.setLinkRole(collectionId: existing.collectionId, role: role)
            } catch {
                linkRole = previous
                self.error = error.localizedDescription
            }
        }
    }

    private func updateMemberRole(_ member: ShareParticipant, to role: ShareRole) {
        guard member.shareRole != role, let shares = services.shares else { return }
        Task {
            do {
                guard let existing = try await shares.myShare(for: collection) else {
                    throw ShareUIError.notPublished
                }
                try await shares.setMemberRole(
                    collectionId: existing.collectionId,
                    clerkId: member.clerkId,
                    role: role
                )
                await refreshShareState()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func revokeShare() {
        guard let shares = services.shares else { return }
        Task {
            do {
                try await shares.revoke(collection)
                shareCode = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func removeMember(_ member: ShareParticipant) {
        guard let shares = services.shares else { return }
        Task {
            do {
                guard let existing = try await shares.myShare(for: collection) else {
                    throw ShareUIError.notPublished
                }
                try await shares.removeMember(
                    collectionId: existing.collectionId,
                    clerkId: member.clerkId
                )
                await refreshShareState()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - ShareUIError

private enum ShareUIError: LocalizedError {
    case notPublished

    var errorDescription: String? {
        String(
            localized: "members.error.notPublished",
            defaultValue: "このコレクションはまだ共有されていません。"
        )
    }
}
