import StoreKit
import SwiftUI

// MARK: - AboutView

/// Displays app information: icon, name, version, build, and useful links.
/// Uses a standard Form layout in the style of Apple's Settings app.
struct AboutView: View {

    // MARK: - Environment

    @Environment(\.requestReview) private var requestReview

    // MARK: - Constants

    private let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "WizMark"
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    private let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"

    private let websiteURL = URL(string: "https://wizmark.protoductai.com")!

    // MARK: - Body

    var body: some View {
        Form {
            appHeaderSection
            linksSection
            developmentSection
        }
        .navigationTitle(String(localized: "about.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - App Header Section

    private var appHeaderSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "paperclip")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.accentColor)
                    )

                Text(appName)
                    .font(.title2.weight(.bold))

                Text(verbatim: "Version \(version) (\(build))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Links Section

    private var linksSection: some View {
        Section {
            Link(destination: websiteURL) {
                Label(
                    String(localized: "about.website", defaultValue: "ウェブサイト"),
                    systemImage: "globe"
                )
            }

            Button {
                requestReview()
            } label: {
                Label(
                    String(localized: "about.rateApp", defaultValue: "App Storeで評価"),
                    systemImage: "star.fill"
                )
            }

            NavigationLink {
                TermsOfServiceView()
            } label: {
                Label(
                    String(localized: "about.terms", defaultValue: "利用規約"),
                    systemImage: "doc.text"
                )
            }

            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label(
                    String(localized: "about.privacy", defaultValue: "プライバシーポリシー"),
                    systemImage: "lock.shield"
                )
            }
        }
    }

    // MARK: - Development Section

    private var developmentSection: some View {
        Section(
            header: Text(String(localized: "about.developmentHeader", defaultValue: "開発"))
        ) {
            Text("© 2026 Protoduct AI")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
