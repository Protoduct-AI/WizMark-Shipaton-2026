import AuthenticationServices
import ClerkKit
import os
import SwiftUI

// MARK: - AuthStep

/// The current phase of the authentication flow.
enum AuthStep: Equatable {
    /// Initial screen: email input + social sign-in buttons.
    case initial
    /// Code verification after email sign-in or sign-up.
    case verifying
    /// Sign-up requires a password after code verification.
    case settingPassword
    /// Sign-in with existing password.
    case signingInWithPassword
    /// Password reset: enter code + new password.
    case resettingPassword
}

// MARK: - AuthError

/// User-facing authentication error with localized messages.
struct AuthError: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

// MARK: - AuthFlowType

/// Whether the current email flow is a sign-in to an existing account
/// or a sign-up for a new one.
private enum AuthFlowType {
    case signIn
    case signUp
}

// MARK: - AuthViewModel

/// Drives the sign-in / sign-up flow using ClerkKit.
///
/// Supports three authentication strategies:
/// 1. **Email code** -- passwordless OTP sent to the user's email
/// 2. **Apple Sign In** -- native ASAuthorization via ClerkKit's `signInWithApple`
/// 3. **Google Sign In** -- OAuth redirect via ClerkKit's `signInWithOAuth`
///
/// The root navigation layer observes `Clerk.shared.session` to decide when
/// to transition away from the auth screen.
@Observable
@MainActor
final class AuthViewModel {

    // MARK: - Public State

    var email: String = ""
    var verificationCode: String = ""
    var password: String = ""
    var isLoading: Bool = false
    var error: AuthError?
    var step: AuthStep = .initial

    // MARK: - Private

    private var flowType: AuthFlowType?
    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "AuthViewModel")

    // MARK: - Convenience

    private var auth: Auth { Clerk.shared.auth }

    // MARK: - Email Code Flow

    /// Begin the email authentication flow.
    ///
    /// 1. Attempt `auth.signIn` with the email as identifier.
    ///    - If the account supports email code, call `signIn.sendEmailCode()` and move to `.verifying`.
    ///    - If the account supports password, move to `.signingInWithPassword`.
    /// 2. If sign-in creation fails (account not found), fall back to `auth.signUp`
    ///    and prepare email verification, then move to `.verifying`.
    func sendEmailCode() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        error = nil

        var signInCreated = false

        do {
            do {
                let signIn = try await auth.signIn(trimmed)
                signInCreated = true

                let factors = signIn.supportedFirstFactors ?? []

                if factors.contains(where: { $0.strategy == .emailCode }) {
                    try await signIn.sendEmailCode()
                    flowType = .signIn
                    step = .verifying
                    logger.info("Email code sent for sign-in")
                    isLoading = false
                    return
                }

                if factors.contains(where: { $0.strategy == .password }) {
                    flowType = .signIn
                    step = .signingInWithPassword
                    isLoading = false
                    return
                }

                throw AuthInternalError.unsupportedFactor
            } catch let caughtError {
                if signInCreated { throw caughtError }

                // Account does not exist -- create one.
                logger.info("Sign-in failed, attempting sign-up")
                let signUp = try await auth.signUp(emailAddress: trimmed)
                try await signUp.sendEmailCode()
                flowType = .signUp
                step = .verifying
                logger.info("Email code sent for sign-up")
            }
        } catch {
            handleError(error)
        }

        isLoading = false
    }

    /// Verify the 6-digit code the user received by email.
    func verifyCode() async {
        let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, let flowType else { return }

        isLoading = true
        error = nil

        do {
            switch flowType {
            case .signIn:
                guard let signIn = auth.currentSignIn else {
                    throw AuthInternalError.noActiveFlow
                }
                let result = try await signIn.verifyCode(code)
                if result.status == .complete, let sessionId = result.createdSessionId {
                    try await auth.setActive(sessionId: sessionId)
                    step = .initial
                    logger.info("Sign-in complete via email code")
                }

            case .signUp:
                guard let signUp = auth.currentSignUp else {
                    throw AuthInternalError.noActiveFlow
                }
                let result = try await signUp.verifyEmailCode(code)
                if result.status == .complete, let sessionId = result.createdSessionId {
                    try await auth.setActive(sessionId: sessionId)
                    step = .initial
                    logger.info("Sign-up complete via email code")
                } else if result.status == .missingRequirements {
                    step = .settingPassword
                }
            }
        } catch {
            if isAlreadyVerifiedError(error) {
                step = .settingPassword
            } else {
                handleError(error)
            }
        }

        isLoading = false
    }

    /// Set a password for a new sign-up that requires one after email verification.
    func setPassword() async {
        let pw = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pw.count >= 8 else { return }

        isLoading = true
        error = nil

        do {
            guard let signUp = auth.currentSignUp else {
                throw AuthInternalError.noActiveFlow
            }
            let updated = try await signUp.update(password: pw)
            if updated.status == .complete, let sessionId = updated.createdSessionId {
                try await auth.setActive(sessionId: sessionId)
                step = .initial
                logger.info("Sign-up complete with password")
            }
        } catch {
            handleError(error)
        }

        isLoading = false
    }

    /// Sign in with an existing password (when the account has password factor).
    func signInWithPassword() async {
        let pw = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pw.isEmpty else { return }

        isLoading = true
        error = nil

        do {
            guard let signIn = auth.currentSignIn else {
                throw AuthInternalError.noActiveFlow
            }
            let result = try await signIn.authenticateWithPassword(pw)
            if result.status == .complete, let sessionId = result.createdSessionId {
                try await auth.setActive(sessionId: sessionId)
                step = .initial
                logger.info("Sign-in complete with password")
            }
        } catch {
            handleError(error)
        }

        isLoading = false
    }

    // MARK: - Password Reset

    /// Initiate a password reset by sending a reset code to the user's email.
    func startPasswordReset() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        error = nil

        do {
            // Create a sign-in with the identifier, then send reset password code.
            let signIn = try await auth.signIn(trimmed)
            try await signIn.sendResetPasswordEmailCode()
            step = .resettingPassword
            logger.info("Password reset code sent")
        } catch {
            handleError(error)
        }

        isLoading = false
    }

    /// Complete the password reset with the verification code and new password.
    func completePasswordReset() async {
        let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let pw = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, pw.count >= 8 else { return }

        isLoading = true
        error = nil

        do {
            guard let signIn = auth.currentSignIn else {
                throw AuthInternalError.noActiveFlow
            }
            // Verify the reset code, then set the new password.
            let verified = try await signIn.verifyCode(code)
            let result = try await verified.resetPassword(newPassword: pw)
            if result.status == .complete, let sessionId = result.createdSessionId {
                try await auth.setActive(sessionId: sessionId)
                step = .initial
                logger.info("Password reset complete")
            }
        } catch {
            handleError(error)
        }

        isLoading = false
    }

    // MARK: - Apple Sign In

    /// Authenticate with Apple using ClerkKit's built-in Apple Sign In flow.
    /// Handles the entire ASAuthorization + Clerk transfer flow automatically.
    func signInWithApple() async {
        isLoading = true
        error = nil

        do {
            let result = try await auth.signInWithApple()
            switch result {
            case .signIn:
                logger.info("Apple sign-in complete")
            case .signUp:
                logger.info("Apple sign-up complete (transfer flow)")
            }
        } catch let asError as ASAuthorizationError where asError.code == .canceled {
            // User cancelled -- do not show an error.
            logger.debug("Apple Sign In cancelled by user")
        } catch {
            handleError(error)
        }

        isLoading = false
    }

    // MARK: - Google Sign In

    /// Authenticate with Google using ClerkKit's OAuth redirect flow.
    /// Opens a web authentication session for Google OAuth.
    func signInWithGoogle() async {
        isLoading = true
        error = nil

        do {
            let result = try await auth.signInWithOAuth(provider: .google)
            switch result {
            case .signIn:
                logger.info("Google sign-in complete")
            case .signUp:
                logger.info("Google sign-up complete (transfer flow)")
            }
        } catch {
            handleError(error)
        }

        isLoading = false
    }

    // MARK: - Sign Out

    /// Sign out the current Clerk session.
    func signOut() async {
        isLoading = true
        do {
            try await auth.signOut()
            resetFlow()
            logger.info("Signed out")
        } catch {
            handleError(error)
        }
        isLoading = false
    }

    // MARK: - Navigation

    /// Reset all fields and return to the initial step.
    func resetFlow() {
        step = .initial
        flowType = nil
        verificationCode = ""
        password = ""
        error = nil
    }

    // MARK: - Error Handling

    /// Maps a Clerk error code string to a localized, user-friendly message.
    private func mapErrorMessage(for code: String) -> String {
        switch code {
        case "form_code_incorrect", "verification_failed":
            String(localized: "auth.errors.invalidCode")
        case "verification_expired":
            String(localized: "auth.errors.codeExpired")
        case "too_many_requests", "rate_limit_exceeded":
            String(localized: "auth.errors.tooManyRequests")
        case "form_identifier_exists":
            String(localized: "auth.errors.accountExists")
        case "form_identifier_not_found":
            String(localized: "auth.errors.accountNotFound")
        case "form_password_pwned":
            String(localized: "auth.errors.passwordPwned")
        case "form_password_length_too_short":
            String(localized: "auth.errors.passwordTooShort")
        case "form_password_incorrect":
            String(localized: "auth.errors.passwordIncorrect")
        case "session_exists":
            String(localized: "auth.errors.sessionExists")
        case "form_param_nil":
            String(localized: "auth.errors.missingField")
        default:
            String(localized: "auth.errors.generic")
        }
    }

    private func handleError(_ error: Error) {
        logger.error("Auth error: \(error.localizedDescription)")

        // Silently ignore session_exists errors (user is already signed in).
        if isSessionExistsError(error) { return }

        let message = extractClerkErrorMessage(from: error)
        self.error = AuthError(message: message)
    }

    /// Extract a user-facing message from a Clerk SDK error.
    ///
    /// ClerkKit throws `ClerkAPIError` directly with a `code` property.
    /// We match against that code first for reliable error mapping.
    private func extractClerkErrorMessage(from error: Error) -> String {
        // ClerkKit throws ClerkAPIError with a `code` property directly.
        if let apiError = error as? ClerkAPIError {
            return mapErrorMessage(for: apiError.code)
        }

        // ClerkClientError provides a human-readable message.
        if let clientError = error as? ClerkClientError,
           let message = clientError.message, !message.isEmpty
        {
            return message
        }

        let localizedMsg = error.localizedDescription
        if !localizedMsg.isEmpty,
           localizedMsg != "The operation couldn\u{2019}t be completed."
        {
            return localizedMsg
        }

        return String(localized: "auth.errors.generic")
    }

    private func isSessionExistsError(_ error: Error) -> Bool {
        if let apiError = error as? ClerkAPIError {
            return apiError.code == "session_exists"
        }
        return false
    }

    private func isAlreadyVerifiedError(_ error: Error) -> Bool {
        if let apiError = error as? ClerkAPIError {
            return apiError.code == "verification_already_verified"
        }
        // Fallback: check the description for older SDK versions.
        return error.localizedDescription.lowercased().contains("already been verified")
    }
}

// MARK: - AuthInternalError

/// Internal error type for auth-specific failures that do not originate from ClerkKit.
private enum AuthInternalError: LocalizedError {
    case unsupportedFactor
    case noActiveFlow

    var errorDescription: String? {
        switch self {
        case .unsupportedFactor:
            String(localized: "auth.errors.generic")
        case .noActiveFlow:
            String(localized: "auth.errors.generic")
        }
    }
}
