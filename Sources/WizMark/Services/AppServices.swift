import Foundation
import SwiftData
import ConvexMobile
import ClerkConvex
import os

// MARK: - AppServices

/// Central service container that holds all application services.
/// Initialized once at app launch and injected into the SwiftUI environment.
///
/// Core data is persisted locally via SwiftData with automatic iCloud sync
/// through CloudKit. No authentication is required for basic CRUD.
///
/// Convex-backed services (bookmarks, collections, tags, user, feedback)
/// are optional and only initialized when the user signs in, enabling
/// future group/sharing features.
///
/// Usage in the App struct:
/// ```swift
/// @State private var services = AppServices()
///
/// var body: some Scene {
///     WindowGroup {
///         ContentView()
///             .modelContainer(services.modelContainer)
///             .environment(services)
///     }
/// }
/// ```
///
/// Usage in views:
/// ```swift
/// @Environment(AppServices.self) private var services
/// ```
@Observable
@MainActor
final class AppServices {

    // MARK: - SwiftData

    /// The SwiftData container with CloudKit sync for local-first persistence.
    let modelContainer: ModelContainer

    // MARK: - Local-First Services (SwiftData)

    /// Bookmark CRUD via SwiftData. Available immediately — no auth required.
    let bookmarks: BookmarkService

    /// Collection (folder) management via SwiftData. Available immediately — no auth required.
    let collections: CollectionService

    /// Collections shared through Convex. Available once signed in.
    private(set) var shares: ShareService?

    /// Messages shown behind the bell: announcements and share events.
    var inbox: NotificationInboxService?

    // MARK: - Convex (Optional, signed-in features only)

    /// The authenticated Convex client, initialized on sign-in.
    private(set) var convexClient: ConvexClientWithAuth<String>?

    /// Tag listing with usage counts via Convex.
    private(set) var tags: TagService?

    /// Current user profile management via Convex.
    private(set) var user: UserService?

    /// Feedback submission via Convex.
    private(set) var feedback: FeedbackService?



    // MARK: - Platform Services

    /// In-app purchases and subscription management.
    let purchases: PurchaseService

    /// Push notification permission and token management.
    let notifications: NotificationService

    /// Event tracking and user identification.
    let analytics: AnalyticsService

    /// Biometric authentication (Face ID / Touch ID).
    let biometric: BiometricService

    /// Network connectivity monitoring.
    let network: NetworkMonitor

    // MARK: - Private

    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "AppServices")

    // MARK: - Init

    init() {
        // SwiftData container with CloudKit automatic sync.
        let schema = Schema([Bookmark.self, BookmarkCollection.self])
        let config = ModelConfiguration(
            "WizMark",
            schema: schema,
            groupContainer: .identifier(AppGroup.identifier),
            cloudKitDatabase: .automatic
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Local-first services use the SwiftData model context.
        let context = modelContainer.mainContext
        self.bookmarks = BookmarkService(modelContext: context)
        self.collections = CollectionService(modelContext: context)

        // Platform services are independent of auth.
        self.purchases = PurchaseService()
        self.notifications = NotificationService()
        self.analytics = AnalyticsService()
        self.biometric = BiometricService()
        self.network = NetworkMonitor()

        logger.info("AppServices initialized (local-first, no auth required)")
    }

    // MARK: - Lifecycle

    /// Called once at app launch to configure platform services that
    /// do not require authentication.
    func startPlatformServices() async {
        // Configure analytics.
        analytics.configure(apiKey: Config.posthogApiKey, host: Config.posthogHost)

        // Configure RevenueCat.
        await purchases.configure()

        // Register for push notifications if previously authorized.
        if notifications.isAuthorized {
            notifications.registerForRemoteNotifications()
        }

        logger.info("Platform services started")
    }

    /// Called after sign-in to initialize Convex-backed services and
    /// start real-time subscriptions for group/sharing features.
    func startConvexServices() {
        // Only initialize Convex when actually signing in.
        // This keeps the app functional without any auth dependency.
        guard convexClient == nil else {
            logger.debug("Convex services already running")
            return
        }

        let client = createConvexClient()
        self.convexClient = client

        self.tags = TagService(client: client)
        self.user = UserService(client: client)
        self.feedback = FeedbackService(client: client)
        self.shares = ShareService(client: client)
        self.inbox = NotificationInboxService(client: client)

        // Start real-time subscriptions.
        // `tags` is deliberately not subscribed: the deployment has no
        // `tags:list` function and nothing reads TagService.tags, so
        // subscribing only produced a recurring ServerError in the logs.
        // Re-enable once the backend function exists.
        user?.subscribe()
        shares?.subscribe()
        inbox?.subscribe()

        AIExtractionService.shared.convexClient = client

        logger.info("Convex services started")
    }

    /// Called on sign-out to tear down Convex subscriptions and reset state.
    func stopConvexServices() async {
        // Stop Convex subscriptions.
        tags?.unsubscribe()
        user?.unsubscribe()
        shares?.unsubscribe()
        inbox?.stop()

        // Tear down references.
        self.tags = nil
        self.user = nil
        self.feedback = nil
        self.shares = nil
        self.inbox = nil
        self.convexClient = nil
        AIExtractionService.shared.convexClient = nil

        // Reset analytics identity.
        analytics.reset()

        // Log out of RevenueCat.
        await purchases.logOut()

        logger.info("Convex services stopped, local data remains available")
    }

    /// Identify the user across analytics and purchase services after sign-in.
    /// - Parameters:
    ///   - userId: The Clerk subject identifier.
    ///   - email: The user's email address.
    ///   - name: The user's display name.
    func identifyUser(userId: String, email: String? = nil, name: String? = nil) async {
        // PostHog identification.
        var properties: [String: Any] = [:]
        if let email { properties["email"] = email }
        if let name { properties["name"] = name }
        analytics.identify(userId: userId, properties: properties.isEmpty ? nil : properties)

        // RevenueCat user association.
        await purchases.logIn(userId: userId)

        logger.debug("User identified across services")
    }

    // MARK: - Private Helpers

    /// Creates the authenticated Convex client with Clerk auth.
    /// Separated to keep `init()` free of Convex dependencies.
    private func createConvexClient() -> ConvexClientWithAuth<String> {
        // Uses the local provider rather than the one bundled with
        // clerk-convex-swift: that one requests a token without naming the
        // "convex" JWT template, so Convex never accepted it.
        let authProvider = ConvexClerkAuthProvider()
        let client = ConvexClientWithAuth(
            deploymentUrl: Config.convexUrl,
            authProvider: authProvider as any AuthProvider<String>
        )
        authProvider.bind(client: client)
        return client
    }
}

