import SwiftUI

struct OnboardingContainerView: View {

    @Bindable var viewModel: OnboardingViewModel

    private var isJapanese: Bool {
        Locale.current.language.languageCode?.identifier == "ja"
    }

    private var tutorialPages: [(img: String, t1: LocalizedStringResource, t2: LocalizedStringResource, sub: LocalizedStringResource)] {
        let suffix = isJapanese ? "" : "_en"
        return [
            ("Onboarding/onboarding1\(suffix)",
             LocalizedStringResource("onboarding.page1.title1", defaultValue: "他のアプリから"),
             LocalizedStringResource("onboarding.page1.title2", defaultValue: "すぐに保存"),
             LocalizedStringResource("onboarding.page1.subtitle", defaultValue: "YouTubeやSafari、SNSなどの\n共有メニューから選ぶだけで\nあとで見返したいリンクをすぐに保存")),
            ("Onboarding/onboarding2\(suffix)",
             LocalizedStringResource("onboarding.page2.title1", defaultValue: "保存前に"),
             LocalizedStringResource("onboarding.page2.title2", defaultValue: "かんたん設定"),
             LocalizedStringResource("onboarding.page2.subtitle", defaultValue: "保存先のコレクションを選んで\nメモやタグも追加できます\nAI要約や自動分類も保存前に設定可能")),
            ("Onboarding/onboarding3\(suffix)",
             LocalizedStringResource("onboarding.page3.title1", defaultValue: "あとからすぐ"),
             LocalizedStringResource("onboarding.page3.title2", defaultValue: "見返せる"),
             LocalizedStringResource("onboarding.page3.subtitle", defaultValue: "保存したリンクをAI要約や\nメモ付きで整理\n見たい情報をあとからすぐ確認できます")),
        ]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.18),
                    Color(red: 0.05, green: 0.08, blue: 0.25),
                    Color(red: 0.02, green: 0.03, blue: 0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if viewModel.currentStep == .paywall {
                paywallPage
            } else {
                VStack(spacing: 0) {
                    TabView(selection: $viewModel.currentStep) {
                        notificationContent
                            .tag(OnboardingStep.notifications)

                        ForEach(Array(tutorialPages.enumerated()), id: \.offset) { i, page in
                            tutorialContent(page: page)
                                .tag(OnboardingStep.allCases[i + 1])
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    fixedBottomControls
                        .padding(.horizontal, 28)
                        .padding(.bottom, 16)
                }
            }
        }
    }

    // MARK: - Fixed Bottom Controls

    private var fixedBottomControls: some View {
        VStack(spacing: 12) {
            if viewModel.currentStep == .notifications {
                Button {
                    Task { await viewModel.requestNotifications() }
                } label: {
                    Text(String(localized: "onboarding.notification.allow", defaultValue: "通知を許可する"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.blue))
                }

                Button {
                    viewModel.skipNotifications()
                } label: {
                    Text(String(localized: "onboarding.notification.skip", defaultValue: "あとで"))
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.5))
                }
            } else {
                Button {
                    if viewModel.currentStep == .review {
                        viewModel.showPaywall()
                    } else {
                        viewModel.advance()
                    }
                } label: {
                    Text(viewModel.currentStep == .review
                         ? String(localized: "onboarding.start", defaultValue: "はじめる")
                         : String(localized: "onboarding.next", defaultValue: "次へ"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.blue))
                }
            }

            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i == viewModel.currentStep.rawValue ? Color.blue : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Notification Content (no button/dots)

    private var notificationContent: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.bottom, 28)

            Text(String(localized: "onboarding.notification.title", defaultValue: "通知を許可"))
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .padding(.bottom, 12)

            Text(String(localized: "onboarding.notification.subtitle", defaultValue: "AI分析の完了やブックマークの\n更新をお知らせします"))
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(5)

            Spacer()
        }
    }

    // MARK: - Tutorial Content (no button/dots)

    private func tutorialContent(page: (img: String, t1: LocalizedStringResource, t2: LocalizedStringResource, sub: LocalizedStringResource)) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: page.t1))
                    .font(.system(size: 36, weight: .bold))
                Text(String(localized: page.t2))
                    .font(.system(size: 36, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 12)

            Text(String(localized: page.sub))
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.7))
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 10)

            Spacer()

            Image(page.img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.5), Color.blue.opacity(0.15)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: Color.blue.opacity(0.3), radius: 24, y: 8)
                .padding(.horizontal, 20)

            Spacer()
        }
    }

    // MARK: - Paywall Page

    private var paywallPage: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    viewModel.completeOnboarding()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .padding(.trailing, 20)
                .padding(.top, 8)
            }

            SubscriptionView()
        }
    }
}
