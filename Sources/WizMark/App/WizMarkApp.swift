import ClerkKit
import ClerkKitUI
import os
import Sentry
import SwiftUI

// MARK: - WizMarkApp

/// Application entry point.
///
/// Orchestrates the root view hierarchy based on onboarding state:
///
/// 1. **Onboarding** -- shown once on first launch.
/// 2. **Main App** -- the bookmark management interface (local-first, no auth required).
///
/// All data is persisted locally via SwiftData with automatic iCloud sync
/// through CloudKit. No authentication is required for basic CRUD operations.
///
/// Convex-backed services are optional and only started when the user signs
/// in, enabling future group/sharing features.
///
/// All shared services, the router, and the theme are injected into the
/// SwiftUI environment so every descendant view can access them.
@main
struct WizMarkApp: App {

    // MARK: - UIKit Delegate

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // MARK: - App State

    @State private var appServices: AppServices
    @State private var router = Router()
    @State private var appTheme = AppTheme()
    @State private var onboardingViewModel: OnboardingViewModel?
    @State private var hasCompletedOnboarding = {
        #if DEBUG
        if DemoSeed.isRequested { return true }
        #endif
        return OnboardingViewModel.hasCompletedOnboarding
    }()
    @State private var wizmarkImportError: WizMarkImportError?
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Private

    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "App")

    // MARK: - Init

    init() {
        // Clerk is configured synchronously so it is ready for optional sign-in.
        Clerk.configure(publishableKey: Config.clerkPublishableKey)
        _appServices = State(initialValue: AppServices())

        configureGlobalAppearance()
    }

    private func configureGlobalAppearance() {}

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            rootView
                .environment(appServices)
                .environment(router)
                .environment(appTheme)
                .modelContainer(appServices.modelContainer)
                .preferredColorScheme(appTheme.resolvedColorScheme)
                .onOpenURL { url in
                    if url.pathExtension == "wizmark" {
                        handleWizMarkImport(url: url)
                    } else {
                        router.handleDeepLink(url: url)
                    }
                }
                .alert(
                    String(localized: "import.error.title", defaultValue: "インポートエラー"),
                    isPresented: Binding(
                        get: { wizmarkImportError != nil },
                        set: { if !$0 { wizmarkImportError = nil } }
                    )
                ) {
                    Button("OK") { wizmarkImportError = nil }
                } message: {
                    if let error = wizmarkImportError {
                        Text(error.localizedDescription)
                    }
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: .didRegisterForRemoteNotifications)
                ) { notification in
                    if let tokenData = notification.userInfo?["tokenData"] as? Data {
                        appServices.notifications.handleDeviceToken(tokenData)
                    }
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: .didFailToRegisterForRemoteNotifications)
                ) { notification in
                    if let error = notification.userInfo?["error"] as? Error {
                        appServices.notifications.handleRegistrationError(error)
                    }
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: .didReceiveNotificationDeepLink)
                ) { notification in
                    if let url = notification.userInfo?["url"] as? URL {
                        router.handleDeepLink(url: url)
                    }
                }
                .task {
                    await configureSentry()
                    await appServices.startPlatformServices()
                    await startConvexServicesIfSignedIn()
                    let context = await appServices.modelContainer.mainContext
                    #if DEBUG
                    DemoSeed.seedIfRequested(into: context)
                    #endif
                    nonisolated(unsafe) let ctx = context
                    await AIExtractionService.shared.processAllPending(context: ctx, purchaseService: appServices.purchases)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task {
                            let context = await appServices.modelContainer.mainContext
                            nonisolated(unsafe) let ctx = context
                            await AIExtractionService.shared.processAllPending(context: ctx, purchaseService: appServices.purchases)
                        }
                    }
                }
                // Signing in mid-session has to start Convex too. Without this,
                // the services stay nil until the next cold launch, so anything
                // that needs `AppServices.user` silently does nothing.
                .onChange(of: Clerk.shared.session?.id) { _, newSessionId in
                    guard newSessionId != nil else { return }
                    Task { await startConvexServicesIfSignedIn() }
                }
        }
    }

    // MARK: - Root View

    @ViewBuilder
    private var rootView: some View {
        if !hasCompletedOnboarding {
            onboardingView
        } else {
            mainAppView
                .transition(.opacity)
                .task {
                    appDelegate.requestTrackingIfNeeded()
                }
        }
    }

    // MARK: - Onboarding

    private var onboardingView: some View {
        Group {
            if let vm = onboardingViewModel {
                OnboardingContainerView(viewModel: vm)
                    .onChange(of: vm.isComplete) { _, completed in
                        if completed {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                hasCompletedOnboarding = true
                            }
                            appDelegate.requestTrackingIfNeeded()
                        }
                    }
            } else {
                Color.wizmarkBackground
                    .ignoresSafeArea()
                    .task {
                        onboardingViewModel = OnboardingViewModel()
                    }
            }
        }
    }

    // MARK: - Main App

    private var mainAppView: some View {
        @Bindable var bindableRouter = router

        return NavigationStack {
            HomeView()
        }
        .sheet(item: $bindableRouter.sheetRoute) { route in
            NavigationStack {
                destinationView(for: route)
            }
        }
    }

    // MARK: - Route Destinations

    @ViewBuilder
    private func destinationView(for route: Route) -> some View {
        switch route {
        case .bookmarkDetail(let bookmark):
            BookmarkDetailView(bookmark: bookmark)

        case .bookmarkNew:
            BookmarkFormView()

        case .bookmarkEdit(let bookmark):
            BookmarkFormView(bookmark: bookmark)

        case .collectionNew:
            CollectionFormView(mode: .create())

        case .collectionEdit(let collection):
            CollectionFormView(mode: .edit(collection))

        case .settings:
            ProfileView()

        case .profileEdit:
            ProfileEditView()

        case .notificationSettings:
            NotificationSettingsView()

        case .dataExport:
            DataExportView()

        case .feedback:
            FeedbackView()

        case .about:
            AboutView()

        case .privacyPolicy:
            PrivacyPolicyView()

        case .termsOfService:
            TermsOfServiceView()
        }
    }

    // MARK: - WizMark Import

    /// Handle opening a `.wizmark` file by importing its contents into SwiftData.
    private func handleWizMarkImport(url: URL) {
        let context = appServices.modelContainer.mainContext
        do {
            try WizMarkImporter.importFile(at: url, into: context)
            logger.info("Successfully imported .wizmark file")
        } catch let error as WizMarkImportError {
            wizmarkImportError = error
            logger.error("Failed to import .wizmark file: \(error.localizedDescription)")
        } catch {
            wizmarkImportError = .invalidFormat(underlying: error)
            logger.error("Unexpected error importing .wizmark file: \(error.localizedDescription)")
        }
    }

    // MARK: - Service Lifecycle

    /// Configure Sentry error tracking.
    private func configureSentry() async {
        let sentryDsn = Config.sentryDsn
        if !sentryDsn.isEmpty {
            SentrySDK.start { options in
                options.dsn = sentryDsn
                options.tracesSampleRate = 0.2
                options.profilesSampleRate = 0.1
                options.enableAutoSessionTracking = true
                options.attachScreenshot = true
                options.enableUserInteractionTracing = true
                options.environment = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
                    ? "staging"
                    : "production"
            }
            logger.info("Sentry configured")
        }
    }

    /// Start Convex services and identify the user when already signed in.
    ///
    /// This is a best-effort operation -- the app works fully offline without
    /// Convex. If the user is not signed in, this is a no-op.
    private func startConvexServicesIfSignedIn() async {
        guard Clerk.shared.session != nil else { return }

        appServices.startConvexServices()

        if let user = Clerk.shared.user {
            await appServices.identifyUser(
                userId: user.id,
                email: user.primaryEmailAddress?.emailAddress,
                name: "\(user.firstName ?? "") \(user.lastName ?? "")".trimmingCharacters(in: .whitespaces)
            )
        }
    }
}

// MARK: - Route + Identifiable

extension Route: Identifiable {
    var id: String {
        switch self {
        case .bookmarkDetail(let b): "bookmarkDetail-\(b.persistentModelID)"
        case .bookmarkNew: "bookmarkNew"
        case .bookmarkEdit(let b): "bookmarkEdit-\(b.persistentModelID)"
        case .collectionNew: "collectionNew"
        case .collectionEdit(let c): "collectionEdit-\(c.persistentModelID)"
        case .settings: "settings"
        case .profileEdit: "profileEdit"
        case .notificationSettings: "notificationSettings"
        case .dataExport: "dataExport"
        case .feedback: "feedback"
        case .about: "about"
        case .privacyPolicy: "privacyPolicy"
        case .termsOfService: "termsOfService"
        }
    }
}
