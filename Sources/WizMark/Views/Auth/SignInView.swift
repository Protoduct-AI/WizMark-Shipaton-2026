import AuthenticationServices
import SwiftUI

// MARK: - SignInView

/// Sign-in / sign-up view using stock Apple UI.
///
/// Steps controlled by `AuthViewModel.step`:
/// 1. **Initial** -- Apple/Google social buttons, divider, email field, continue button.
/// 2. **Verifying** -- 6-digit code input with back/verify.
/// 3. **Password steps** -- password field for sign-in, sign-up, or reset.
struct SignInView: View {

    @Bindable var viewModel: AuthViewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email, code, password
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 40)
                headerSection
                formContent
                    .padding(.horizontal, 24)
                Spacer(minLength: 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemBackground))
        .overlay { loadingOverlay }
        .alert(
            String(localized: "auth.error"),
            isPresented: Binding(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            ),
            actions: { Button(String(localized: "auth.ok")) { viewModel.error = nil } },
            message: { Text(viewModel.error?.message ?? "") }
        )
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "paperclip")
                .font(.largeTitle)
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("WizMark")
                .font(.title.bold())

            Text(String(localized: "auth.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Form Content

    @ViewBuilder
    private var formContent: some View {
        switch viewModel.step {
        case .initial:
            initialContent
        case .verifying:
            verifyContent
        case .settingPassword:
            passwordStepContent(
                title: String(localized: "auth.setPassword"),
                icon: "lock.shield",
                buttonTitle: String(localized: "auth.createAccount"),
                disabled: viewModel.password.trimmingCharacters(in: .whitespacesAndNewlines).count < 8
            ) {
                await viewModel.setPassword()
            }
        case .signingInWithPassword:
            signInPasswordContent
        case .resettingPassword:
            resetPasswordContent
        }
    }

    // MARK: - Initial (Social + Email)

    private var initialContent: some View {
        VStack(spacing: 12) {
            // Apple Sign In (native)
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { _ in
                // Clerk handles the actual flow; we just trigger it.
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .cornerRadius(10)
            .accessibilityIdentifier("sign-in-apple-button")
            .overlay {
                // Invisible button to use viewModel's Apple sign-in
                Button {
                    Task { await viewModel.signInWithApple() }
                } label: {
                    Color.clear
                }
                .accessibilityHidden(true)
            }

            Button {
                Task { await viewModel.signInWithGoogle() }
            } label: {
                Label(String(localized: "auth.continueWithGoogle"), systemImage: "globe")
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("sign-in-google-button")

            divider

            TextField(String(localized: "auth.emailAddress"), text: $viewModel.email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .email)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("sign-in-email-input")

            Button {
                Task { await viewModel.sendEmailCode() }
            } label: {
                Text(String(localized: "auth.continueWithEmail"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("sign-in-email-button")
        }
    }

    // MARK: - Verify Code

    private var verifyContent: some View {
        VStack(spacing: 16) {
            Label(
                String.localized("auth.enterCodeSentTo", with: viewModel.email),
                systemImage: "envelope.badge"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            TextField(String(localized: "auth.sixDigitCode"), text: $viewModel.verificationCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focusedField, equals: .code)
                .multilineTextAlignment(.center)
                .font(.title2.monospaced())
                .textFieldStyle(.roundedBorder)
                .onChange(of: viewModel.verificationCode) { _, newValue in
                    let digits = newValue.filter(\.isWholeNumber)
                    if digits.count > 6 {
                        viewModel.verificationCode = String(digits.prefix(6))
                    } else if digits != newValue {
                        viewModel.verificationCode = digits
                    }
                }

            Button {
                Task { await viewModel.verifyCode() }
            } label: {
                Text(String(localized: "auth.verifyCode"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            backButton
        }
    }

    // MARK: - Sign In With Password

    private var signInPasswordContent: some View {
        VStack(spacing: 16) {
            Label(String(localized: "auth.enterPassword"), systemImage: "person.badge.key")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SecureField(String(localized: "auth.passwordPlaceholder"), text: $viewModel.password)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("sign-in-password-input")

            Button {
                Task { await viewModel.signInWithPassword() }
            } label: {
                Text(String(localized: "auth.signIn"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("sign-in-password-button")

            Button(String(localized: "passwordReset.forgotPassword")) {
                Task { await viewModel.startPasswordReset() }
            }
            .font(.footnote)

            backButton
        }
    }

    // MARK: - Reset Password

    private var resetPasswordContent: some View {
        VStack(spacing: 16) {
            Label(
                String.localized("auth.enterCodeSentTo", with: viewModel.email),
                systemImage: "key"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            TextField(String(localized: "auth.sixDigitCode"), text: $viewModel.verificationCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focusedField, equals: .code)
                .multilineTextAlignment(.center)
                .font(.title2.monospaced())
                .textFieldStyle(.roundedBorder)

            SecureField(String(localized: "auth.passwordPlaceholder"), text: $viewModel.password)
                .textContentType(.newPassword)
                .focused($focusedField, equals: .password)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await viewModel.completePasswordReset() }
            } label: {
                Text(String(localized: "passwordReset.resetButton"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(
                viewModel.verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || viewModel.password.trimmingCharacters(in: .whitespacesAndNewlines).count < 8
            )

            backButton
        }
    }

    // MARK: - Reusable: Password Step

    private func passwordStepContent(
        title: String,
        icon: String,
        buttonTitle: String,
        disabled: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        VStack(spacing: 16) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SecureField(String(localized: "auth.passwordPlaceholder"), text: $viewModel.password)
                .textContentType(.newPassword)
                .focused($focusedField, equals: .password)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await action() }
            } label: {
                Text(buttonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(disabled)

            backButton
        }
    }

    // MARK: - Shared Components

    private var divider: some View {
        HStack {
            Rectangle().fill(Color(.separator)).frame(height: 1)
            Text(String(localized: "auth.or"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Rectangle().fill(Color(.separator)).frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private var backButton: some View {
        Button {
            viewModel.resetFlow()
        } label: {
            Label(String(localized: "auth.back"), systemImage: "chevron.left")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    // MARK: - Loading Overlay

    @ViewBuilder
    private var loadingOverlay: some View {
        if viewModel.isLoading {
            Color.black.opacity(0.15)
                .ignoresSafeArea()
                .overlay { ProgressView() .controlSize(.large) }
                .allowsHitTesting(true)
        }
    }
}

// MARK: - Preview

#Preview("Sign In - Initial") {
    SignInView(viewModel: AuthViewModel())
}

#Preview("Sign In - Verifying") {
    let vm = AuthViewModel()
    vm.step = .verifying
    vm.email = "user@example.com"
    return SignInView(viewModel: vm)
}
