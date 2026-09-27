import SwiftUI

/// The list behind the bell.
struct NotificationInboxView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @Environment(Router.self) private var router

    private var inbox: NotificationInboxService? { services.inbox }

    var body: some View {
        NavigationStack {
            Group {
                if let inbox, !inbox.messages.isEmpty {
                    list(inbox.messages)
                } else {
                    ContentUnavailableView(
                        String(localized: "inbox.empty.title", defaultValue: "お知らせはありません"),
                        systemImage: "bell",
                        description: Text(String(
                            localized: "inbox.empty.message",
                            defaultValue: "運営からのお知らせや、共有への参加があったときにここに届きます。"
                        ))
                    )
                }
            }
            .navigationTitle(String(localized: "inbox.notifications.title", defaultValue: "お知らせ"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.close", defaultValue: "閉じる")) {
                        dismiss()
                    }
                }
                if let inbox, inbox.unreadCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(String(
                            localized: "inbox.markAllRead",
                            defaultValue: "すべて既読"
                        )) {
                            Task { await inbox.markAllRead() }
                        }
                    }
                }
            }
        }
    }

    private func list(_ messages: [InboxMessage]) -> some View {
        List {
            ForEach(messages) { message in
                row(message)
                    .contentShape(Rectangle())
                    .onTapGesture { open(message) }
            }
        }
        .listStyle(.plain)
    }

    private func row(_ message: InboxMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.symbol)
                .font(.body)
                .foregroundStyle(message.isRead ? Color.secondary : Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(message.title)
                    .font(.subheadline.weight(message.isRead ? .regular : .semibold))

                Text(message.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(message.date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            // Unread is carried by weight and by this dot rather than by a
            // background tint, which reads as selection in a list.
            if !message.isRead {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 4)
    }

    private func open(_ message: InboxMessage) {
        Task { await inbox?.markRead(message) }

        guard let link = message.link, let url = URL(string: link) else { return }
        // Announcements can point at a place in the app; the router already
        // knows how to get there.
        if router.handleDeepLink(url: url) {
            dismiss()
        }
    }
}
