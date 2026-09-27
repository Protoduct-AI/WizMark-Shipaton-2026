import os
import SwiftData
import SwiftUI

// MARK: - Route

/// All navigable destinations in the application.
///
/// Routes that carry associated data (model objects or document IDs) are used
/// for programmatic navigation via `NavigationPath`. Routes without data are
/// used for sheets.
enum Route: Hashable {

    // MARK: - Bookmark

    /// Full-screen bookmark detail.
    case bookmarkDetail(bookmark: Bookmark)

    /// Bookmark creation form.
    case bookmarkNew

    /// Bookmark edit form.
    case bookmarkEdit(bookmark: Bookmark)

    // MARK: - Collection

    /// Collection detail showing its bookmarks.
    /// Collection creation form.
    case collectionNew

    /// Collection edit form.
    case collectionEdit(collection: BookmarkCollection)

    // MARK: - Settings & Profile

    /// User settings root.
    case settings

    /// Profile editor.
    case profileEdit

    /// Notification preferences.
    case notificationSettings

    /// Data export screen.
    case dataExport

    /// Feedback form.
    case feedback

    /// About the app.
    case about

    /// Privacy policy.
    case privacyPolicy

    /// Terms of service.
    case termsOfService

    // MARK: - Hashable

    static func == (lhs: Route, rhs: Route) -> Bool {
        switch (lhs, rhs) {
        case (.bookmarkDetail(let a), .bookmarkDetail(let b)):
            a.persistentModelID == b.persistentModelID
        case (.bookmarkNew, .bookmarkNew):
            true
        case (.bookmarkEdit(let a), .bookmarkEdit(let b)):
            a.persistentModelID == b.persistentModelID
        case (.collectionNew, .collectionNew):
            true
        case (.collectionEdit(let a), .collectionEdit(let b)):
            a.persistentModelID == b.persistentModelID
        case (.settings, .settings), (.profileEdit, .profileEdit),
             (.notificationSettings, .notificationSettings),
             (.dataExport, .dataExport), (.feedback, .feedback),
             (.about, .about), (.privacyPolicy, .privacyPolicy),
             (.termsOfService, .termsOfService):
            true
        default:
            false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .bookmarkDetail(let b):
            hasher.combine("bookmarkDetail")
            hasher.combine(b.persistentModelID)
        case .bookmarkNew:
            hasher.combine("bookmarkNew")
        case .bookmarkEdit(let b):
            hasher.combine("bookmarkEdit")
            hasher.combine(b.persistentModelID)
        case .collectionNew:
            hasher.combine("collectionNew")
        case .collectionEdit(let c):
            hasher.combine("collectionEdit")
            hasher.combine(c.persistentModelID)
        case .settings:
            hasher.combine("settings")
        case .profileEdit:
            hasher.combine("profileEdit")
        case .notificationSettings:
            hasher.combine("notificationSettings")
        case .dataExport:
            hasher.combine("dataExport")
        case .feedback:
            hasher.combine("feedback")
        case .about:
            hasher.combine("about")
        case .privacyPolicy:
            hasher.combine("privacyPolicy")
        case .termsOfService:
            hasher.combine("termsOfService")
        }
    }
}

// MARK: - Router

/// Observable navigation state shared across the app via the SwiftUI environment.
///
/// Manages a `NavigationPath` for push navigation and an optional `Route`
/// for sheet presentations. Also handles incoming deep links.
///
/// Usage:
/// ```swift
/// @Environment(Router.self) private var router
///
/// // Push navigation
/// router.navigate(to: .bookmarkDetail(bookmark: bookmark))
///
/// // Sheet presentation
/// router.present(sheet: .bookmarkNew)
/// ```
@Observable
@MainActor
final class Router {

    // MARK: - Navigation State

    /// The navigation path driving `NavigationStack` push transitions.
    var path = NavigationPath()

    /// The currently presented sheet route. Set to `nil` to dismiss.
    var sheetRoute: Route?

    /// The currently presented full-screen cover route.
    var fullScreenCoverRoute: Route?

    // MARK: - Private

    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "Router")

    // MARK: - Push Navigation

    /// Push a route onto the navigation stack.
    /// - Parameter route: The destination route.
    func navigate(to route: Route) {
        path.append(route)
        logger.debug("Navigated to \(String(describing: route))")
    }

    /// Pop the top route from the navigation stack.
    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// Pop to the root of the navigation stack.
    func popToRoot() {
        path = NavigationPath()
    }

    // MARK: - Sheet Navigation

    /// Present a route as a sheet.
    /// - Parameter route: The route to present.
    func present(sheet route: Route) {
        sheetRoute = route
        logger.debug("Presenting sheet: \(String(describing: route))")
    }

    /// Present a route as a full-screen cover.
    /// - Parameter route: The route to present.
    func present(fullScreenCover route: Route) {
        fullScreenCoverRoute = route
        logger.debug("Presenting full screen cover: \(String(describing: route))")
    }

    /// Dismiss the currently presented sheet or full-screen cover.
    func dismiss() {
        if sheetRoute != nil {
            sheetRoute = nil
        } else if fullScreenCoverRoute != nil {
            fullScreenCoverRoute = nil
        }
    }

    // MARK: - Deep Linking

    /// Share code from an invitation link waiting to be redeemed.
    ///
    /// Set by deep-link handling and cleared once the view layer has joined,
    /// so the flow survives the app being launched cold by the link.
    var pendingShareCode: String?

    /// Handle an incoming URL (custom scheme or universal link).
    ///
    /// Deep links that reference specific bookmarks or collections by URL
    /// require a `ModelContext` to resolve objects from their identifiers.
    ///
    /// Supported URL formats:
    /// - `wizmark://new` -- open bookmark creation
    /// - `wizmark://bookmark/{url}` -- navigate to bookmark by URL (future)
    /// - `wizmark://collection/{name}` -- navigate to collection by name (future)
    ///
    /// - Parameter url: The incoming URL.
    /// - Returns: `true` if the URL was recognized and handled.
    @discardableResult
    func handleDeepLink(url: URL) -> Bool {
        logger.info("Handling deep link: \(url.absoluteString, privacy: .public)")

        let pathComponents = extractPathComponents(from: url)

        guard let first = pathComponents.first else {
            logger.warning("Deep link has no path components")
            return false
        }

        switch first {
        case "new":
            present(sheet: .bookmarkNew)
            return true

        case "join":
            // An invitation link. The code is consumed by the view layer, which
            // has access to the share service and can prompt for sign-in.
            guard pathComponents.count > 1 else { break }
            pendingShareCode = pathComponents[1]
            return true

        default:
            break
        }

        logger.warning("Unrecognized deep link path: \(first)")
        return false
    }

    // MARK: - Private Helpers

    /// Extract meaningful path components from both custom-scheme and universal-link URLs.
    private func extractPathComponents(from url: URL) -> [String] {
        // Custom scheme: wizmark://bookmark/abc -> host = "bookmark", path = "/abc"
        // Universal link: https://wizmark.protoductai.com/bookmark/abc -> path = "/bookmark/abc"
        var components: [String] = []

        if url.scheme == Config.urlScheme {
            // Custom scheme: host is the first component
            if let host = url.host(percentEncoded: false) {
                components.append(host)
            }
            components.append(
                contentsOf: url.pathComponents.filter { $0 != "/" }
            )
        } else {
            // Universal link: strip leading "/"
            components = url.pathComponents.filter { $0 != "/" }
        }

        return components
    }
}
