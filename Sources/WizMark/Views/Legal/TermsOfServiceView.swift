import SwiftUI

// MARK: - TermsOfServiceView

/// Displays the terms of service with localized content (Japanese/English).
struct TermsOfServiceView: View {

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
        .navigationTitle(String(localized: "legal.termsTitle"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Localized Content

    private var localizedBody: String {
        let isEnglish = AppLanguage.current == .en
        return isEnglish ? Self.bodyEN : Self.bodyJA
    }

    // MARK: - Japanese

    private static let bodyJA = """
    本利用規約は、本アプリケーション（以下「本アプリ」）の利用条件を定めるものです。利用者は本アプリを利用することにより、本規約に同意したものとみなされます。

    1. 利用条件
    本アプリは個人利用のために提供されます。商業目的での利用はあらかじめ運営者の書面による許可を得る必要があります。

    2. 禁止事項
    ・法令または公序良俗に違反する行為
    ・他の利用者または第三者の権利を侵害する行為
    ・本アプリのサーバーまたはネットワークに過大な負荷を与える行為
    ・リバースエンジニアリング、デコンパイル、逆アセンブル行為

    3. 免責
    本アプリは現状有姿で提供されます。運営者は本アプリの利用により生じた損害について、法令上許される最大限において責任を負いません。

    4. サービスの変更・終了
    運営者は、利用者への事前通知なく本アプリの内容を変更または終了することができます。

    5. 準拠法
    本規約は日本法に準拠します。
    """

    // MARK: - English

    private static let bodyEN = """
    These Terms of Service govern your use of this application ("the App"). By using the App, you agree to be bound by these Terms.

    1. Use
    The App is provided for personal use. Commercial use requires prior written consent.

    2. Prohibited Activities
    - Violation of applicable laws or public order
    - Infringement of rights of other users or third parties
    - Imposing excessive load on the App's servers or networks
    - Reverse engineering, decompiling, or disassembling

    3. Disclaimer
    The App is provided "as is". The operator shall not be liable for any damages arising from use of the App to the maximum extent permitted by law.

    4. Changes and Termination
    The operator may modify or terminate the App without prior notice.

    5. Governing Law
    These Terms are governed by the laws of Japan.
    """
}
