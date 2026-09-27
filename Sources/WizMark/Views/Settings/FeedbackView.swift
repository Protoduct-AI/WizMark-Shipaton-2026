import SwiftUI

// MARK: - FeedbackView

/// Submit user feedback: category picker, message body, and submit.
/// When the user is signed in, submits via Convex. Otherwise opens a
/// pre-filled mailto: link as a fallback so feedback always works.
struct FeedbackView: View {

    // MARK: - Environment

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    // MARK: - State

    @State private var category: FeedbackCategory = .bug
    @State private var message: String = ""
    @State private var isSubmitting: Bool = false
    @State private var showSuccessAlert: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var showMailFallbackAlert: Bool = false

    // MARK: - Constants

    private let supportEmail = "info@protoductai.com"
    private let maxMessageLength = 4000

    // MARK: - Computed

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedMessage.isEmpty && !isSubmitting
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    /// True when Convex feedback service is available (user is signed in).
    private var hasConvexFeedback: Bool {
        services.feedback != nil
    }

    // MARK: - Body

    var body: some View {
        Form {
            categorySection
            messageSection
            submitSection
        }
        .navigationTitle(String(localized: "feedback.title"))
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .alert(
            String(localized: "feedback.successTitle"),
            isPresented: $showSuccessAlert
        ) {
            Button(String(localized: "common.ok")) {
                resetForm()
                dismiss()
            }
        } message: {
            Text(String(localized: "feedback.successMessage"))
        }
        .alert(
            String(localized: "feedback.errorTitle"),
            isPresented: $showErrorAlert
        ) {
            Button(String(localized: "common.ok"), role: .cancel) {}
            // Offer mailto fallback when Convex submission fails.
            Button(String(localized: "feedback.sendViaEmail")) {
                openMailto()
            }
        } message: {
            Text(String(localized: "feedback.errorFallbackMessage",
                         defaultValue: "Submission failed. You can send feedback via email instead."))
        }
        .alert(
            String(localized: "feedback.emailSentTitle", defaultValue: "Send via Email"),
            isPresented: $showMailFallbackAlert
        ) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(String(localized: "feedback.emailSentMessage",
                         defaultValue: "Your default mail app will open with the feedback pre-filled."))
        }
    }

    // MARK: - Category Section

    private var categorySection: some View {
        Section {
            Picker(String(localized: "feedback.categoryLabel"), selection: $category) {
                ForEach(FeedbackCategory.allCases, id: \.self) { cat in
                    Text(cat.displayName).tag(cat)
                }
            }
        } header: {
            Text(String(localized: "feedback.categoryHeader", defaultValue: "Category"))
        }
    }

    // MARK: - Message Section

    private var messageSection: some View {
        Section {
            TextEditor(text: $message)
                .frame(minHeight: 120)
                .overlay(alignment: .topLeading) {
                    if message.isEmpty {
                        Text(String(localized: "feedback.messagePlaceholder"))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
        } header: {
            Text(String(localized: "feedback.messageLabel"))
        } footer: {
            Text("\(trimmedMessage.count) / \(maxMessageLength)")
                .font(.caption)
                .foregroundStyle(
                    trimmedMessage.count > maxMessageLength ? .red : .secondary
                )
        }
    }

    // MARK: - Submit Section

    private var submitSection: some View {
        Section {
            if hasConvexFeedback {
                // Primary: submit via Convex backend.
                Button {
                    Task { await submitViaConvex() }
                } label: {
                    HStack {
                        Text(String(localized: "feedback.submitButton"))
                        Spacer()
                        if isSubmitting {
                            ProgressView()
                        }
                    }
                }
                .disabled(!canSubmit || trimmedMessage.count > maxMessageLength)
            } else {
                // Fallback: open mailto when not signed in.
                Button {
                    openMailto()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope")
                        Text(String(localized: "feedback.sendViaEmail", defaultValue: "Send via Email"))
                    }
                }
                .disabled(!canSubmit || trimmedMessage.count > maxMessageLength)
            }
        } footer: {
            if !hasConvexFeedback {
                Text(String(localized: "feedback.signInHint",
                             defaultValue: "Sign in to submit feedback directly from the app."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    /// Submit feedback through the Convex backend.
    private func submitViaConvex() async {
        guard canSubmit, let feedbackService = services.feedback else { return }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await feedbackService.submit(
                category: category,
                message: trimmedMessage,
                appVersion: appVersion
            )
            showSuccessAlert = true
        } catch {
            showErrorAlert = true
        }
    }

    /// Open the system mail compose via mailto: URL with pre-filled fields.
    private func openMailto() {
        let subject = mailSubject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let body = mailBody.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "mailto:\(supportEmail)?subject=\(subject)&body=\(body)") else {
            return
        }
        openURL(url)
    }

    private var mailSubject: String {
        "[WizMark Feedback] \(category.displayName)"
    }

    private var mailBody: String {
        """
        \(trimmedMessage)

        ---
        App: WizMark \(appVersion)
        Platform: iOS
        Category: \(category.displayName)
        """
    }

    /// Reset the form fields after successful submission.
    private func resetForm() {
        category = .bug
        message = ""
    }
}

// MARK: - FeedbackCategory Display

extension FeedbackCategory: CaseIterable {
    static var allCases: [FeedbackCategory] { [.bug, .feature, .other] }

    var displayName: String {
        switch self {
        case .bug: String(localized: "feedback.bug")
        case .feature: String(localized: "feedback.feature")
        case .other: String(localized: "feedback.other")
        }
    }
}
