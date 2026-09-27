import Foundation
import RevenueCat
import os

// MARK: - PurchaseService

/// Wraps the RevenueCat Purchases SDK for subscription management.
/// Provides reactive state for subscription status, available packages, and purchase flow.
@Observable
@MainActor
final class PurchaseService {

    // MARK: - Configuration

    /// RevenueCat API keys per platform.
    enum PurchaseConfig {
        static var apiKey: String {
            Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String ?? ""
        }
        static let proEntitlementId = "pro"
        static let adFreeEntitlementId = "ad_free"
    }

    // MARK: - Published State

    private(set) var isInitialized: Bool = false

    /// Whether the current user has an active Pro subscription (all features + ad-free).
    ///
    /// Seeded from the launch argument in debug builds so the paid experience is
    /// in place from the first frame, before RevenueCat has answered.
    private(set) var isSubscribed: Bool = {
        #if DEBUG
        if PurchaseService.isProForcedByLaunchArgument { return true }
        #endif
        return false
    }()

    /// Whether the user purchased ad-free (lifetime).
    private(set) var isAdFree: Bool = false

    /// Available subscription packages from the current offering.
    private(set) var offerings: [RevenueCat.Package] = []

    /// The current customer info from RevenueCat.
    private(set) var customerInfo: CustomerInfo?

    // MARK: - Private

    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "Purchases")

    // MARK: - Init / Configuration

    /// Configure RevenueCat and load initial customer info and offerings.
    /// Call once at app launch.
    func configure() async {
        guard !isInitialized else { return }

        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: PurchaseConfig.apiKey)

        do {
            let info = try await Purchases.shared.customerInfo()
            applyCustomerInfo(info)

            await loadOfferings()

            Purchases.shared.delegate = PurchasesDelegateProxy.shared
            PurchasesDelegateProxy.shared.onCustomerInfoUpdate = { [weak self] info in
                Task { @MainActor [weak self] in
                    self?.applyCustomerInfo(info)
                }
            }

            isInitialized = true
            logger.info("RevenueCat configured, subscribed=\(self.isSubscribed)")
        } catch {
            logger.error("Failed to initialize RevenueCat: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Public API

    /// Purchase a specific package.
    /// - Parameter package: The RevenueCat package to purchase.
    /// - Throws: Purchase errors (except user cancellation, which returns silently).
    func purchase(package: RevenueCat.Package) async throws {
        let result = try await Purchases.shared.purchase(package: package)

        if result.userCancelled {
            logger.debug("User cancelled purchase")
            return
        }

        applyCustomerInfo(result.customerInfo)
        logger.info("Purchase completed for \(package.identifier, privacy: .public)")
    }

    /// Restore previous purchases (e.g. after reinstall or device transfer).
    /// - Throws: Restore errors.
    func restorePurchases() async throws {
        let info = try await Purchases.shared.restorePurchases()
        applyCustomerInfo(info)
        logger.info("Purchases restored, subscribed=\(self.isSubscribed)")
    }

    /// Reload available offerings from RevenueCat.
    func loadOfferings() async {
        do {
            let offeringsResult = try await Purchases.shared.offerings()
            offerings = offeringsResult.current?.availablePackages ?? []
            logger.debug("Loaded \(self.offerings.count) packages")
        } catch {
            logger.error("Failed to load offerings: \(error.localizedDescription, privacy: .public)")
            offerings = []
        }
    }

    /// Associate the RevenueCat anonymous user with a Clerk user ID.
    /// Call after sign-in to merge purchase history.
    /// - Parameter userId: The Clerk subject identifier.
    func logIn(userId: String) async {
        do {
            let (info, _) = try await Purchases.shared.logIn(userId)
            applyCustomerInfo(info)
            logger.debug("RevenueCat logged in as \(userId, privacy: .private(mask: .hash))")
        } catch {
            logger.error("RevenueCat login failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Clear the RevenueCat user identity on sign-out.
    func logOut() async {
        do {
            let info = try await Purchases.shared.logOut()
            applyCustomerInfo(info)
            logger.debug("RevenueCat logged out")
        } catch {
            logger.error("RevenueCat logout failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private Helpers

    private func applyCustomerInfo(_ info: CustomerInfo) {
        customerInfo = info
        isSubscribed = info.entitlements[PurchaseConfig.proEntitlementId]?.isActive == true
        isAdFree = info.entitlements[PurchaseConfig.adFreeEntitlementId]?.isActive == true

        #if DEBUG
        // Applied after the real values so a later RevenueCat update cannot
        // silently turn the demo build back into a free one mid-recording.
        if Self.isProForcedByLaunchArgument {
            isSubscribed = true
        }
        #endif

        let shared = AppGroup.defaults
        shared?.set(isSubscribed, forKey: "is_pro_subscriber")
        shared?.set(shouldHideAds, forKey: "should_hide_ads")
    }

    /// Whether ads should be hidden (Pro subscriber OR ad-free purchaser).
    var shouldHideAds: Bool { isSubscribed || isAdFree }

    #if DEBUG
    /// Whether this launch was told to behave as if Pro were purchased.
    ///
    /// Recording a demo or reviewing a paid screen otherwise means driving a
    /// sandbox purchase on every fresh simulator. A launch argument rather than
    /// a setting, so it is set once from the command line and cannot be left on
    /// by accident:
    ///
    ///     xcrun simctl launch <udid> com.protoductai.wizmark -forcePro
    ///
    /// Compiled out of Release, so a shipped build has no path to it.
    /// Once set, stays set until the app is reinstalled.
    ///
    /// Persisting rather than reading the argument each time lets a UI runner
    /// relaunch the app — which it does between scenes — without the paid state
    /// dropping out from under the recording. Reinstalling clears it.
    static var isProForcedByLaunchArgument: Bool {
        let key = "debug_force_pro"
        let store = AppGroup.defaults ?? .standard
        if ProcessInfo.processInfo.arguments.contains("-forcePro") {
            store.set(true, forKey: key)
            return true
        }
        return store.bool(forKey: key)
    }
    #endif
}

// MARK: - PurchasesDelegateProxy

/// A singleton class conforming to PurchasesDelegate that forwards customer info updates
/// to the PurchaseService via a closure. Necessary because @Observable classes cannot
/// directly conform to @objc protocols.
private final class PurchasesDelegateProxy: NSObject, PurchasesDelegate, @unchecked Sendable {

    static let shared = PurchasesDelegateProxy()

    var onCustomerInfoUpdate: (@Sendable (CustomerInfo) -> Void)?

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        onCustomerInfoUpdate?(customerInfo)
    }
}
