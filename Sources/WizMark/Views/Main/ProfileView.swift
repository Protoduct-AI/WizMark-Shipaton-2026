import CloudKit
import Humation
import StoreKit
import SwiftUI
import SwiftData
import ClerkKit
import ClerkKitUI
import os

// MARK: - ProfileView

/// Comprehensive settings screen accessible as a sheet from the home screen.
/// All sections except Account are visible regardless of sign-in status.
struct ProfileView: View {

    // MARK: - Environment

    @Environment(AppServices.self) private var services
    @Environment(AppTheme.self) private var appTheme
    @Environment(\.requestReview) private var requestReview

    // MARK: - State

    @State private var showSignOutConfirmation = false
    @State private var showDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var showSignIn = false
    @State private var isSigningOut = false
    @State private var signOutError: Error?
    @State private var iCloudStatus: ICloudSyncStatus = .checking

    @State private var showNicknamePrompt = false
    @State private var nicknameInput = ""
    @AppStorage("user_nickname") private var nickname: String?

    private var isSignedIn: Bool {
        Clerk.shared.session != nil
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            @Bindable var theme = appTheme
            Form {
                accountSection
                subscriptionSection
                appearanceSection(theme: $theme)
                notificationsSection
                dataSection
                supportSection
                aboutSection
                legalSection

                #if DEBUG
                devSection
                #endif
            }
            .formStyle(.grouped)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                String(localized: "settings.signOutConfirmTitle", defaultValue: "サインアウト"),
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    String(localized: "settings.signOut", defaultValue: "サインアウト"),
                    role: .destructive
                ) {
                    performSignOut()
                }
                Button(String(localized: "common.cancel", defaultValue: "キャンセル"), role: .cancel) {}
            } message: {
                Text(String(localized: "settings.signOutConfirmMessage", defaultValue: "サインアウトしてもよろしいですか？"))
            }

            .confirmationDialog(
                String(localized: "deleteAccount.title", defaultValue: "アカウントを削除"),
                isPresented: $showDeleteAccountConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "deleteAccount.confirm", defaultValue: "アカウントを削除"), role: .destructive) {
                    performDeleteAccount()
                }
                Button(String(localized: "common.cancel", defaultValue: "キャンセル"), role: .cancel) {}
            } message: {
                Text(String(localized: "deleteAccount.message", defaultValue: "アカウントとすべての関連データが完全に削除されます。この操作は取り消せません。"))
            }
            .sheet(isPresented: $showSignIn) {
                SignInSheetView()
            }
            .errorAlert(error: $signOutError)
            .preferredColorScheme(appTheme.resolvedColorScheme)
            .alert(String(localized: "profile.nicknamePrompt.title", defaultValue: "ニックネームを設定"), isPresented: $showNicknamePrompt) {
                TextField(String(localized: "profile.nicknamePrompt.placeholder", defaultValue: "ニックネーム"), text: $nicknameInput)
                Button(String(localized: "common.save", defaultValue: "保存")) {
                    let trimmed = nicknameInput.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    saveNickname(trimmed)
                }
                Button(String(localized: "common.skip", defaultValue: "スキップ"), role: .cancel) {}
            } message: {
                Text(String(localized: "profile.nicknamePrompt.message", defaultValue: "表示名を入力してください"))
            }
        }
        .task {
            await checkICloudStatus()
        }
        .onChange(of: Clerk.shared.session) { old, new in
            if old == nil, new != nil, nickname == nil {
                showNicknamePrompt = true
            }
        }
    }

    // MARK: - Account Section

    @ViewBuilder
    private var accountSection: some View {
        if isSignedIn {
            Section {
                NavigationLink {
                    ProfileEditView()
                } label: {
                    profileRow
                }
            }

            Section(String(localized: "settings.accountHeader", defaultValue: "アカウント")) {

                Button(role: .destructive) {
                    showSignOutConfirmation = true
                } label: {
                    HStack {
                        if isSigningOut {
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        } else {
                            Label(
                                String(localized: "settings.signOut", defaultValue: "サインアウト"),
                                systemImage: "rectangle.portrait.and.arrow.right"
                            )
                        }
                    }
                }
                .disabled(isSigningOut)

                Button(role: .destructive) {
                    showDeleteAccountConfirmation = true
                } label: {
                    HStack {
                        if isDeletingAccount {
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        } else {
                            Label(String(localized: "deleteAccount.title", defaultValue: "アカウントを削除"), systemImage: "trash")
                        }
                    }
                }
                .disabled(isDeletingAccount)
            }
        } else {
            Section {
                Button {
                    showSignIn = true
                } label: {
                    Label(
                        String(localized: "settings.signIn", defaultValue: "サインイン"),
                        systemImage: "person.crop.circle.badge.plus"
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Appearance Section

    @ViewBuilder
    private func appearanceSection(theme: Bindable<AppTheme>) -> some View {
        Section(String(localized: "settings.appearanceHeader", defaultValue: "外観")) {
            Picker(
                String(localized: "settings.theme", defaultValue: "テーマ"),
                selection: Binding(
                    get: { appTheme.preference },
                    set: { appTheme.preference = $0 }
                )
            ) {
                ForEach(ThemePreference.allCases) { pref in
                    Text(pref.displayName).tag(pref)
                }
            }

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Label(
                        String(localized: "settings.language", defaultValue: "言語"),
                        systemImage: "globe"
                    )
                    Spacer()
                    Text(Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "ja") ?? String(localized: "settings.language.japanese", defaultValue: "日本語"))
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Section(String(localized: "settings.notificationsHeader", defaultValue: "通知")) {
            NavigationLink {
                NotificationSettingsView()
            } label: {
                Label(
                    String(localized: "settings.notificationSettings", defaultValue: "通知設定"),
                    systemImage: "bell.badge"
                )
            }
        }
    }

    // MARK: - Subscription Section

    private var subscriptionSection: some View {
        Section {
            NavigationLink {
                SubscriptionView()
            } label: {
                HStack {
                    Label("WizMark Pro", systemImage: "crown.fill")
                        .foregroundStyle(.yellow)
                    Spacer()
                    if services.purchases.isSubscribed {
                        Text(String(localized: "subscription.active", defaultValue: "加入中"))
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        Section(String(localized: "settings.dataHeader", defaultValue: "データ")) {
            HStack {
                Label(
                    String(localized: "settings.iCloudSync", defaultValue: "iCloud同期"),
                    systemImage: "icloud"
                )
                Spacer()
                iCloudStatusIndicator
            }
        }
    }

    // MARK: - Support Section

    private var supportSection: some View {
        Section(String(localized: "settings.supportHeader", defaultValue: "サポート")) {
            NavigationLink {
                FeedbackView()
            } label: {
                Label(
                    String(localized: "settings.feedback", defaultValue: "フィードバック"),
                    systemImage: "bubble.left.and.text.bubble.right"
                )
            }

            Button {
                requestReview()
            } label: {
                Label(
                    String(localized: "settings.rateApp", defaultValue: "App Storeで評価する"),
                    systemImage: "star"
                )
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section(String(localized: "settings.aboutHeader", defaultValue: "WizMarkについて")) {
            Link(destination: URL(string: "https://wizmark.protoductai.com")!) {
                HStack {
                    Label(
                        String(localized: "settings.about", defaultValue: "Wizmarkについて"),
                        systemImage: "info.circle"
                    )
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Legal Section

    private var legalSection: some View {
        Section(String(localized: "settings.legalHeader", defaultValue: "法務情報")) {
            Link(destination: URL(string: "https://wizmark.protoductai.com/privacy")!) {
                HStack {
                    Label(
                        String(localized: "settings.privacyPolicy", defaultValue: "プライバシーポリシー"),
                        systemImage: "lock.shield"
                    )
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Link(destination: URL(string: "https://wizmark.protoductai.com/terms")!) {
                HStack {
                    Label(
                        String(localized: "settings.termsOfService", defaultValue: "利用規約"),
                        systemImage: "doc.text"
                    )
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MIT と Apache-2.0 はライセンス本文を製品に同梱することを求める
            // ため、外部リンクではなくアプリ内に持つ。
            NavigationLink {
                OpenSourceLicensesView()
            } label: {
                Label(
                    String(
                        localized: "settings.licenses.title",
                        defaultValue: "オープンソースライセンス"
                    ),
                    systemImage: "shippingbox"
                )
            }
        }
    }

    // MARK: - Profile Row

    private var profileRow: some View {
        HStack(spacing: 12) {
            humationAvatar
                .frame(width: 48, height: 48)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(clerkDisplayName)
                    .font(.headline)
                if let email = Clerk.shared.user?.primaryEmailAddress?.emailAddress {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var humationAvatar: some View {
        UserAvatarView(pixels: 96, fallbackInitial: String(clerkDisplayName.prefix(1)))
    }

    private var clerkDisplayName: String {
        let user = Clerk.shared.user
        let first = user?.firstName ?? ""
        let last = user?.lastName ?? ""
        let full = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        if !full.isEmpty { return full }
        return nickname ?? user?.primaryEmailAddress?.emailAddress ?? String(localized: "profile.defaultName", defaultValue: "ユーザー")
    }

    // MARK: - iCloud Status Indicator

    @ViewBuilder
    private var iCloudStatusIndicator: some View {
        switch iCloudStatus {
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .unavailable:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        case .restricted:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Computed

    // MARK: - Actions

    private func performDeleteAccount() {
        isDeletingAccount = true
        Task {
            do {
                try await Clerk.shared.user?.delete()
                await services.stopConvexServices()
                isDeletingAccount = false
            } catch {
                signOutError = error
                isDeletingAccount = false
            }
        }
    }

    private func performSignOut() {
        isSigningOut = true
        Task {
            do {
                try await Clerk.shared.auth.signOut()
                isSigningOut = false
            } catch {
                signOutError = error
                isSigningOut = false
            }
        }
    }

    // MARK: - Dev Section

    #if DEBUG
    @State private var showOnboardingPreview = false

    private var devSection: some View {
        Section(String(localized: "settings.devTools", defaultValue: "開発者ツール")) {
            Button {
                Storage.set(false, for: .hasCompletedOnboarding)
                showOnboardingPreview = true
            } label: {
                Label(String(localized: "settings.resetOnboarding", defaultValue: "オンボーディングを再表示"), systemImage: "arrow.counterclockwise")
            }
            .fullScreenCover(isPresented: $showOnboardingPreview) {
                OnboardingContainerView(
                    viewModel: OnboardingViewModel()
                )
            }
        }
    }
    #endif

    // MARK: - Nickname

    /// Persists the nickname to Clerk, which owns the display name.
    ///
    /// Keeping it only in `@AppStorage` made the prompt pointless: the name shown
    /// on screen comes from Clerk whenever Clerk holds one, so a locally-stored
    /// nickname never appeared. Convex mirrors the value when it is running.
    private func saveNickname(_ trimmed: String) {
        // Kept locally as well, so the name still renders while the Clerk update
        // is in flight and for accounts that carry no Clerk name.
        nickname = trimmed

        Task {
            do {
                // Stored whole with lastName cleared. Splitting the nickname and
                // passing nil for a missing surname left the old surname behind,
                // so it reappeared appended to the newly entered name.
                try await Clerk.shared.user?.update(.init(
                    firstName: trimmed,
                    lastName: ""
                ))

                if let userService = services.user {
                    try await userService.updateProfile(displayName: trimmed)
                }
            } catch {
                Logger(subsystem: "com.protoductai.wizmark", category: "Profile")
                    .error("Failed to save nickname: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - iCloud

    private func checkICloudStatus() async {
        do {
            let status = try await CKContainer.default().accountStatus()
            switch status {
            case .available:
                iCloudStatus = .available
            case .restricted:
                iCloudStatus = .restricted
            case .noAccount, .couldNotDetermine, .temporarilyUnavailable:
                iCloudStatus = .unavailable
            @unknown default:
                iCloudStatus = .unavailable
            }
        } catch {
            iCloudStatus = .unavailable
        }
    }


}

// MARK: - ICloudSyncStatus

private enum ICloudSyncStatus {
    case checking
    case available
    case unavailable
    case restricted
}
