import Combine
@preconcurrency import ConvexMobile
import Foundation
import SwiftData
import os

// MARK: - Shared Models

/// A bookmark inside a collection someone shared with this user.
struct SharedBookmark: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let url: String
    let title: String
    let bookmarkDescription: String?
    let thumbnailUrl: String?
    let note: String?
    let tags: [String]
    let siteName: String?
    let favicon: String?
    let aiSummary: String?
    let createdAt: Double
    /// Whether this user added it. Only then can they take it back.
    let addedByMe: Bool?

    /// The host of the bookmark URL, when it parses.
    var domain: String? { URL(string: url)?.host(percentEncoded: false) }

    var resolvedURL: URL? { URL(string: url) }
}

/// A collection another user shared with this one.
struct SharedCollection: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String?
    let color: String?
    let ownerName: String?
    let role: String
    let updatedAt: Double
    let bookmarks: [SharedBookmark]

    var bookmarkCount: Int { bookmarks.count }
    var isEmpty: Bool { bookmarks.isEmpty }

    /// Whether this user may add to the collection.
    var canEdit: Bool { ShareRole.parse(role) == .editor || role == "owner" }
}

/// What a member may do with a shared collection.
///
/// `owner` is not grantable: it identifies who administers the share.
enum ShareRole: String, CaseIterable, Sendable, Identifiable {
    case viewer
    case editor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .viewer:
            String(localized: "members.role.viewer", defaultValue: "閲覧のみ")
        case .editor:
            String(localized: "members.role.editor", defaultValue: "編集者")
        }
    }

    /// Falls back to view-only for anything unrecognised, including the shares
    /// published before roles were selectable.
    static func parse(_ raw: String?) -> ShareRole {
        guard let raw, let role = ShareRole(rawValue: raw) else { return .viewer }
        return role
    }
}

/// A participant of a collection this user owns and shared.
struct ShareParticipant: Codable, Sendable, Identifiable, Hashable {
    let clerkId: String
    let name: String?
    let email: String?
    let role: String
    let joinedAt: Double

    var id: String { clerkId }

    var shareRole: ShareRole { .parse(role) }

    /// Best available label for the participant.
    ///
    /// Deliberately never falls back to the email address: a member list is
    /// visible to whoever owns the share, and an address is more than they need
    /// in order to recognise someone.
    var displayName: String {
        if let name, !name.isEmpty { return name }
        return String(localized: "members.unknownParticipant", defaultValue: "招待中のユーザー")
    }
}

/// The share state of a collection this user owns.
struct MyShare: Codable, Sendable {
    let collectionId: String
    let shareCode: String
    let defaultRole: String
    let updatedAt: Double
    let participants: [ShareParticipant]

    var linkRole: ShareRole { .parse(defaultRole) }
}

/// A bookmark an editor contributed to a collection this user owns.
struct ShareContribution: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let url: String
    let title: String
    let bookmarkDescription: String?
    let thumbnailUrl: String?
    let note: String?
    let tags: [String]
    let siteName: String?
    let favicon: String?
    let aiSummary: String?
    let createdAt: Double
    let addedByName: String?

    var contributorName: String {
        if let addedByName, !addedByName.isEmpty { return addedByName }
        return String(localized: "members.unknownParticipant", defaultValue: "招待中のユーザー")
    }
}

/// The live state of a collection this user owns and published.
struct MyShareState: Codable, Sendable, Identifiable {
    let localId: String
    let collectionId: String
    let shareCode: String
    let defaultRole: String
    let updatedAt: Double
    let participants: [ShareParticipant]
    let contributions: [ShareContribution]

    var id: String { localId }
    var linkRole: ShareRole { .parse(defaultRole) }
}

/// What an invitation link points at, readable before joining.
struct SharePreview: Codable, Sendable {
    let name: String
    let icon: String?
    let color: String?
    let ownerName: String?
    let bookmarkCount: Int
}

// MARK: - ShareService

/// Collection sharing over Convex.
///
/// Collections are authored locally in SwiftData; publishing pushes a snapshot
/// to Convex and hands back an invitation code. Participants read that snapshot,
/// so sharing does not depend on CloudKit and works across accounts that never
/// touch iCloud.
@Observable
@MainActor
final class ShareService {

    // MARK: - Observable State

    /// Collections other users shared with the signed-in user.
    private(set) var sharedWithMe: [SharedCollection] = []

    /// Collections this user owns and published, with live participants and
    /// whatever editors contributed.
    private(set) var myShares: [MyShareState] = []

    // MARK: - Private

    private let client: ConvexClientWithAuth<String>
    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "ShareService")
    private var subscriptionCancellable: AnyCancellable?
    private var myShareCancellable: AnyCancellable?

    init(client: ConvexClientWithAuth<String>) {
        self.client = client
    }

    // MARK: - Subscription

    /// Starts watching the collections shared with this user.
    func subscribe() {
        unsubscribe()

        let publisher: AnyPublisher<[SharedCollection], ClientError> =
            client.subscribe(to: "shares:listSharedWithMe")

        subscriptionCancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.logger.error(
                            "Shared collections subscription failed: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                },
                receiveValue: { [weak self] collections in
                    self?.sharedWithMe = collections
                }
            )

        let mine: AnyPublisher<[MyShareState], ClientError> =
            client.subscribe(to: "shares:myShares")

        myShareCancellable = mine
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.logger.error(
                            "Owned shares subscription failed: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                },
                receiveValue: { [weak self] shares in
                    self?.myShares = shares
                }
            )
    }

    func unsubscribe() {
        subscriptionCancellable?.cancel()
        subscriptionCancellable = nil
        myShareCancellable?.cancel()
        myShareCancellable = nil
    }

    // MARK: - Owned Shares

    /// The live share state of a collection this user owns, if it is published.
    func share(for collection: BookmarkCollection) -> MyShareState? {
        let localId = Self.localId(for: collection)
        return myShares.first { $0.localId == localId }
    }

    /// Pushes the collection again if it is already published.
    ///
    /// Publishing is otherwise only triggered when an invitation link is made,
    /// so everything the owner changed afterwards — including anything the share
    /// extension saved while the app was closed — stayed on their device.
    /// Callers fire this when the collection is shown; it is a no-op when the
    /// collection was never shared.
    func resyncIfShared(_ collection: BookmarkCollection) async {
        guard share(for: collection) != nil else { return }
        do {
            _ = try await publish(collection)
        } catch {
            logger.error("Resync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Publishing

    /// Publishes a collection and returns its invitation code.
    ///
    /// Re-publishing the same collection keeps the previous code, so links
    /// already sent out keep working.
    func publish(_ collection: BookmarkCollection) async throws -> String {
        // ConvexEncodable only covers scalars plus `[String: ConvexEncodable?]`
        // and `[ConvexEncodable?]`, so the payload is built in those terms.
        let bookmarks: [ConvexEncodable?] = (collection.bookmarks ?? []).map { bookmark in
            let tags: [ConvexEncodable?] = bookmark.tags.map { $0 }
            let payload: [String: ConvexEncodable?] = [
                "url": bookmark.url,
                "title": bookmark.title,
                "bookmarkDescription": bookmark.bookmarkDescription,
                "thumbnailUrl": bookmark.thumbnailUrl,
                "note": bookmark.note,
                "tags": tags,
                "siteName": bookmark.siteName,
                "favicon": bookmark.favicon,
                "aiSummary": bookmark.aiSummary,
                // `Int` encodes as Convex int64, which the float64
                // validator rejects, so widen it here.
                "displayOrder": Double(bookmark.displayOrder),
                "createdAt": bookmark.createdAt.timeIntervalSince1970 * 1000,
            ]
            return payload
        }

        let result: PublishResult = try await client.mutation(
            "shares:publish",
            with: [
                "localId": Self.localId(for: collection),
                "name": collection.name,
                "icon": collection.icon,
                "color": collection.color,
                "bookmarks": bookmarks,
            ]
        )

        logger.info("Published collection with \(bookmarks.count) bookmark(s)")
        return result.shareCode
    }

    /// Stops sharing a collection. Existing links stop resolving.
    func revoke(_ collection: BookmarkCollection) async throws {
        try await client.mutation(
            "shares:revoke",
            with: ["localId": Self.localId(for: collection)]
        )
        logger.info("Revoked share")
    }

    /// The share state of a collection this user owns, or nil when unpublished.
    func myShare(for collection: BookmarkCollection) async throws -> MyShare? {
        try await queryOnce("shares:myShare", with: ["localId": Self.localId(for: collection)])
    }

    // MARK: - Joining

    /// What an invitation code points at, before committing to join.
    func preview(shareCode: String) async throws -> SharePreview? {
        try await queryOnce("shares:preview", with: ["shareCode": shareCode])
    }

    /// Accepts an invitation. Safe to call more than once for the same code.
    func join(shareCode: String) async throws -> String {
        let result: JoinResult = try await client.mutation(
            "shares:join",
            with: ["shareCode": shareCode]
        )
        logger.info("Joined shared collection")
        return result.name
    }

    /// Leaves a collection someone shared with this user.
    func leave(collectionId: String) async throws {
        try await client.mutation("shares:leave", with: ["sharedCollectionId": collectionId])
    }

    /// Removes a participant from a collection this user owns.
    func removeMember(collectionId: String, clerkId: String) async throws {
        try await client.mutation(
            "shares:removeMember",
            with: ["sharedCollectionId": collectionId, "clerkId": clerkId]
        )
    }

    /// Adds a bookmark to a collection shared with this user.
    ///
    /// Rows added this way survive the owner republishing, which replaces only
    /// what the owner themselves pushed.
    func addBookmark(
        collectionId: String,
        url: String,
        title: String,
        description: String? = nil,
        siteName: String? = nil,
        thumbnailUrl: String? = nil,
        tags: [String] = []
    ) async throws {
        let tagValues: [ConvexEncodable?] = tags.map { $0 }
        try await client.mutation(
            "shares:addSharedBookmark",
            with: [
                "sharedCollectionId": collectionId,
                "url": url,
                "title": title,
                "bookmarkDescription": description,
                "thumbnailUrl": thumbnailUrl,
                "siteName": siteName,
                "tags": tagValues,
            ]
        )
    }

    /// Removes a bookmark the caller added, or any row when they own the share.
    func removeBookmark(id: String) async throws {
        try await client.mutation("shares:removeSharedBookmark", with: ["bookmarkId": id])
    }

    /// Sets the role future joiners receive. Existing members are untouched.
    func setLinkRole(collectionId: String, role: ShareRole) async throws {
        try await client.mutation(
            "shares:setDefaultRole",
            with: ["sharedCollectionId": collectionId, "role": role.rawValue]
        )
    }

    /// Changes one existing member's role.
    func setMemberRole(collectionId: String, clerkId: String, role: ShareRole) async throws {
        try await client.mutation(
            "shares:setMemberRole",
            with: [
                "sharedCollectionId": collectionId,
                "clerkId": clerkId,
                "role": role.rawValue,
            ]
        )
    }

    // MARK: - Invitation Link

    /// The link handed to invitees.
    ///
    /// Uses the app's universal-link domain so it stays tappable in any
    /// messaging app; the custom scheme is registered as a fallback.
    static func invitationURL(shareCode: String) -> URL? {
        URL(string: "https://wizmark.protoductai.com/join/\(shareCode)")
    }

    /// Extracts a share code from an incoming link, if it carries one.
    static func shareCode(from url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        if components.count >= 2, components[0] == "join" {
            return components[1]
        }
        if url.scheme == "wizmark", url.host == "join", let first = components.first {
            return first
        }
        return nil
    }

    // MARK: - Identity

    /// Stable identifier for a local collection.
    ///
    /// Derived from the SwiftData persistent identifier so re-publishing the
    /// same collection updates the existing share instead of creating a new one.
    private static func localId(for collection: BookmarkCollection) -> String {
        String(describing: collection.persistentModelID)
    }

    // MARK: - Query Helper

    /// One-shot query. ConvexMobile only exposes `subscribe`, so this takes the
    /// first emitted value and tears the subscription down.
    private func queryOnce<T: Decodable>(
        _ name: String,
        with args: [String: ConvexEncodable?]? = nil
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            var resumed = false

            cancellable = client.subscribe(to: name, with: args, yielding: T.self)
                .first()
                // Convex delivers on a background queue. Without hopping to the
                // main queue the callbacks run off the main actor and trip
                // Swift's executor check, which crashes the process.
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion, !resumed {
                            resumed = true
                            continuation.resume(throwing: error)
                        }
                        cancellable?.cancel()
                    },
                    receiveValue: { [continuation] value in
                        guard !resumed else { return }
                        resumed = true
                        nonisolated(unsafe) let unwrapped = value
                        continuation.resume(returning: unwrapped)
                        cancellable?.cancel()
                    }
                )
        }
    }
}

// MARK: - Mutation Results

private struct PublishResult: Decodable {
    let shareCode: String
}

private struct JoinResult: Decodable {
    let name: String
}
