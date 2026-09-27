import Combine
@preconcurrency import ConvexMobile
import Foundation
import os

/// One message in the notification inbox.
struct InboxMessage: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let kind: String
    let title: String
    let body: String
    let link: String?
    let createdAt: Double
    let isRead: Bool

    var date: Date { Date(timeIntervalSince1970: createdAt / 1000) }

    /// The symbol shown beside the message, by what it is about.
    var symbol: String {
        switch kind {
        case "member_joined": "person.badge.plus"
        case "member_left": "person.badge.minus"
        default: "megaphone"
        }
    }
}

/// The inbox behind the bell.
///
/// Push notifications get missed, dismissed and switched off, so anything worth
/// telling someone needs somewhere it stays put. Two things arrive here:
/// announcements written by us, and events on shares the user owns — someone
/// issues an invitation link and otherwise has no way of knowing whether anyone
/// used it.
///
/// Subscribed rather than fetched, so the badge and the list cannot drift apart
/// while the app is open.
@Observable
@MainActor
final class NotificationInboxService {

    private(set) var messages: [InboxMessage] = []
    private(set) var unreadCount: Int = 0

    private let client: ConvexClient
    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "Inbox")
    private var cancellables = Set<AnyCancellable>()

    init(client: ConvexClient) {
        self.client = client
    }

    func subscribe() {
        cancellables.removeAll()

        client.subscribe(to: "notifications:list")
            // Convex delivers on a background queue; this type is main-actor
            // isolated, and touching it from there is a crash rather than a
            // data race that shows up later.
            .receive(on: DispatchQueue.main)
            .replaceError(with: [InboxMessage]())
            .sink { [weak self] (messages: [InboxMessage]) in
                self?.messages = messages
            }
            .store(in: &cancellables)

        client.subscribe(to: "notifications:unreadCount")
            .receive(on: DispatchQueue.main)
            .replaceError(with: 0)
            .sink { [weak self] (count: Int) in
                self?.unreadCount = count
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        messages = []
        unreadCount = 0
    }

    func markRead(_ message: InboxMessage) async {
        guard !message.isRead else { return }
        do {
            try await client.mutation(
                "notifications:markRead",
                with: ["notificationId": message.id]
            )
        } catch {
            logger.error("Mark read failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func markAllRead() async {
        do {
            try await client.mutation("notifications:markAllRead")
        } catch {
            logger.error("Mark all read failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
