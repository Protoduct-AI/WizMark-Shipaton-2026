import SwiftUI

// MARK: - PrivacyPolicyView

/// Displays the privacy policy with localized content (Japanese/English).
struct PrivacyPolicyView: View {

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "legal.lastUpdated"))
                    .font(.subheadline)
                    .foregroundStyle(Color.wizmarkTextSecondary)

                Text(localizedBody)
                    .font(.body)
                    .foregroundStyle(Color.wizmarkText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
            }
            .padding(16)
        }
        .background(Color.wizmarkBackground)
        .navigationTitle(String(localized: "legal.privacyTitle"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Localized Content

    private var localizedBody: String {
        let isEnglish = AppLanguage.current == .en
        return isEnglish ? Self.bodyEN : Self.bodyJA
    }

    // MARK: - Japanese

    private static let bodyJA = """
    本プライバシーポリシーは、本アプリケーション（以下「本アプリ」）における個人情報の取扱いについて定めるものです。

    1. 取得する情報
    ・メールアドレス（認証のため）
    ・表示名、プロフィール画像（任意）
    ・デバイス情報（OS、アプリバージョン等）
    ・利用状況（分析・改善のため）

    2. 利用目的
    ・本アプリのサービス提供
    ・利用者の認証とアカウント管理
    ・サービスの改善および新機能の開発
    ・重要なお知らせの配信

    3. 第三者提供
    取得した個人情報は、以下の場合を除き第三者に提供しません。
    ・利用者の同意がある場合
    ・法令に基づく場合
    ・サービス提供に必要な範囲での業務委託先（認証・分析・プッシュ通知等）

    4. データ保管
    個人情報は暗号化された通信路で送受信され、アクセス制御された環境で保管されます。

    5. 利用者の権利
    利用者は自らの個人情報の開示、訂正、削除を求めることができます。アプリ内の「アカウント削除」からいつでもアカウントおよび関連データを削除できます。

    6. お問い合わせ
    本ポリシーに関するお問い合わせはアプリ内フィードバックよりお寄せください。
    """

    // MARK: - English

    private static let bodyEN = """
    This Privacy Policy describes how personal information is handled in this application ("the App").

    1. Information Collected
    - Email address (for authentication)
    - Display name and profile image (optional)
    - Device information (OS, app version, etc.)
    - Usage data (for analytics and improvement)

    2. Purpose of Use
    - Providing the App's services
    - User authentication and account management
    - Service improvement and feature development
    - Delivering important notifications

    3. Third-Party Sharing
    Personal information is not shared with third parties except:
    - With user consent
    - When required by law
    - With service providers (auth, analytics, push notifications) necessary to operate the service

    4. Data Storage
    Personal information is transmitted over encrypted channels and stored in access-controlled environments.

    5. User Rights
    Users may request disclosure, correction, or deletion of their personal information. Account and related data can be deleted at any time via "Delete Account" in the app.

    6. Contact
    For questions about this policy, please use the in-app feedback form.
    """
}
