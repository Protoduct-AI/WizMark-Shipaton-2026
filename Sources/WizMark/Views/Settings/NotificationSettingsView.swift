import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isRequesting: Bool = false

    @AppStorage("notif.marketing") private var marketingEnabled: Bool = false
    @AppStorage("notif.updates") private var updatesEnabled: Bool = true
    @AppStorage("notif.reminders") private var remindersEnabled: Bool = true

    var body: some View {
        Form {
            switch authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                authorizedSection
            case .denied:
                deniedSection
            default:
                notDeterminedSection
            }
        }
        .navigationTitle(String(localized: "notification.settings.title", defaultValue: "通知設定"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshStatus()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
        ) { _ in
            Task { await refreshStatus() }
        }
    }

    // MARK: - Authorized

    private var authorizedSection: some View {
        Section {
            Toggle(String(localized: "notification.settings.marketing", defaultValue: "お知らせ"), isOn: $marketingEnabled)
            Toggle(String(localized: "notification.settings.updates", defaultValue: "アップデート情報"), isOn: $updatesEnabled)
            Toggle(String(localized: "notification.settings.reminders", defaultValue: "リマインダー"), isOn: $remindersEnabled)
        } header: {
            Text(String(localized: "notification.settings.category", defaultValue: "通知カテゴリ"))
        } footer: {
            Text(String(localized: "notification.settings.category.footer", defaultValue: "受け取りたい通知の種類を選択してください。"))
        }
    }

    // MARK: - Denied

    private var deniedSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(String(localized: "notification.settings.denied.title", defaultValue: "通知がオフになっています"))
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                Text(String(localized: "notification.settings.denied.description", defaultValue: "通知を受け取るには、設定アプリからWizMarkの通知を許可してください。"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            Button(String(localized: "notification.settings.openSettings", defaultValue: "設定を開く")) {
                openSystemSettings()
            }
        }
    }

    // MARK: - Not Determined

    private var notDeterminedSection: some View {
        Section {
            Text(String(localized: "notification.settings.notDetermined.description", defaultValue: "通知を有効にすると、AI分析の完了やお知らせを受け取ることができます。"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                Task { await requestPermission() }
            } label: {
                HStack {
                    Text(String(localized: "notification.settings.enableNotifications", defaultValue: "通知を有効にする"))
                    if isRequesting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isRequesting)
        }
    }

    // MARK: - Actions

    private func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    private func requestPermission() async {
        isRequesting = true
        defer { isRequesting = false }

        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        } catch {}
        await refreshStatus()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
