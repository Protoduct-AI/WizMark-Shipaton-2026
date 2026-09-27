import ClerkKit
@preconcurrency import ConvexMobile
import Foundation
import os

// MARK: - ConvexClerkAuthProvider

/// Supplies Convex with a Clerk JWT minted from the "convex" template.
///
/// The provider bundled with clerk-convex-swift calls `session.getToken()`
/// without a template, which returns Clerk's default session token. Convex
/// validates `aud: "convex"`, a claim only the named template produces, so
/// every authenticated query and mutation waited forever for an auth state
/// that never arrived. Requesting the template explicitly is the fix.
@MainActor
final class ConvexClerkAuthProvider: AuthProvider {

    typealias T = String

    /// Name of the JWT template configured in the Clerk dashboard.
    private static let templateName = "convex"

    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "ConvexAuth")

    private var onIdToken: (@Sendable (String?) -> Void)?
    private var sessionSyncTask: Task<Void, Never>?
    private weak var client: ConvexClientWithAuth<String>?

    // MARK: - Binding

    /// Attaches the client and keeps its auth state in step with Clerk.
    ///
    /// Without this the client is never told about an existing session, so a
    /// user who is already signed in at launch stays unauthenticated to Convex.
    func bind(client: ConvexClientWithAuth<String>) {
        self.client = client
        startSessionSync()
    }

    // MARK: - AuthProvider

    func login(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
        try await authenticate(onIdToken: onIdToken)
    }

    func loginFromCache(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
        try await authenticate(onIdToken: onIdToken)
    }

    func logout() async throws {
        onIdToken?(nil)
        onIdToken = nil
        try await Clerk.shared.auth.signOut()
    }

    nonisolated func extractIdToken(from authResult: String) -> String {
        authResult
    }

    // MARK: - Token

    private func authenticate(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> String {
        self.onIdToken = onIdToken
        let token = try await fetchToken()
        onIdToken(token)
        return token
    }

    private func fetchToken() async throws -> String {
        guard Clerk.shared.isLoaded else {
            throw ConvexAuthError.clerkNotLoaded
        }
        guard let session = Clerk.shared.session, session.status == .active else {
            throw ConvexAuthError.noActiveSession
        }

        var options = Session.GetTokenOptions()
        options.template = Self.templateName

        guard let token = try await session.getToken(options) else {
            throw ConvexAuthError.tokenUnavailable
        }

        logger.info("Obtained Convex token from the \(Self.templateName, privacy: .public) template")
        return token
    }

    // MARK: - Session Sync

    /// Logs the client in when a Clerk session appears and out when it goes.
    private func startSessionSync() {
        sessionSyncTask?.cancel()
        sessionSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }

            await syncCurrentSession()

            for await event in Clerk.shared.auth.events {
                guard !Task.isCancelled else { return }
                if case .sessionChanged = event {
                    await syncCurrentSession()
                }
            }
        }
    }

    private func syncCurrentSession() async {
        guard let client else { return }

        if Clerk.shared.session?.status == .active {
            _ = await client.loginFromCache()
            logger.info("Convex login from cache requested")
        } else {
            onIdToken?(nil)
        }
    }
}

// MARK: - ConvexAuthError

enum ConvexAuthError: LocalizedError {
    case clerkNotLoaded
    case noActiveSession
    case tokenUnavailable

    var errorDescription: String? {
        switch self {
        case .clerkNotLoaded:
            "Clerk has not finished loading."
        case .noActiveSession:
            "There is no active Clerk session."
        case .tokenUnavailable:
            "Clerk returned no token for the convex template."
        }
    }
}
