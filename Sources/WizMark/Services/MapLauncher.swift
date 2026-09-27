import Foundation
import UIKit

/// Opens a place in a maps app.
///
/// The extracted address is the most actionable thing on the screen — someone
/// saving a café is going to want directions — but it was rendered as plain
/// text with no way to act on it.
///
/// Which app to use is the person's call, not ours: someone with Google Maps
/// installed usually has it by choice, and silently picking one is the thing
/// that made this feel broken. ``availableApps`` reports what is actually on the
/// device so the caller can offer a choice, and skip the question when there is
/// only one answer.
enum MapLauncher {

    enum App: String, Identifiable, CaseIterable {
        case apple
        case google

        var id: String { rawValue }

        var label: String {
            switch self {
            case .apple:
                String(localized: "map.app.apple", defaultValue: "マップ")
            case .google:
                String(localized: "map.app.google", defaultValue: "Google マップ")
            }
        }

        var symbol: String {
            switch self {
            case .apple: "map.fill"
            case .google: "globe"
            }
        }

        /// Querying a scheme requires it in `LSApplicationQueriesSchemes`,
        /// otherwise `canOpenURL` always answers false.
        fileprivate var probeURL: URL? {
            switch self {
            case .apple: URL(string: "maps://")
            case .google: URL(string: "comgooglemaps://")
            }
        }

        /// Web addresses, used when the app itself is not installed.
        ///
        /// Both of these open the native app when it is present and the site
        /// otherwise, so a choice is never a dead end.
        fileprivate func webURL(query: String) -> URL? {
            switch self {
            case .apple:
                URL(string: "https://maps.apple.com/?q=\(query)")
            case .google:
                URL(string: "https://www.google.com/maps/search/?api=1&query=\(query)")
            }
        }

        fileprivate func appURL(query: String) -> URL? {
            switch self {
            case .apple: URL(string: "maps://?q=\(query)")
            case .google: URL(string: "comgooglemaps://?q=\(query)")
            }
        }
    }

    /// Every maps app worth offering, whether or not it is installed.
    ///
    /// Filtering by what is installed hid Google Maps from anyone whose device
    /// answered no — including every device where the query scheme had not been
    /// declared, which is a build detail nobody using the app can see. Both
    /// entries have a web address behind them, so choosing one always leads
    /// somewhere.
    static var availableApps: [App] { App.allCases }

    /// Opens the place, preferring a name-and-address query over either alone.
    ///
    /// Searching for the address by itself lands on the building rather than the
    /// business, which is the wrong pin when several share an entrance.
    @MainActor
    static func open(in app: App, placeName: String?, address: String?) {
        guard let query = searchQuery(placeName: placeName, address: address) else { return }

        // The app if it is there, the site if it is not.
        if let native = app.appURL(query: query), UIApplication.shared.canOpenURL(native) {
            UIApplication.shared.open(native)
            return
        }
        if let web = app.webURL(query: query) {
            UIApplication.shared.open(web)
        }
    }

    /// Whether there is anything worth opening for this bookmark.
    static func canOpen(placeName: String?, address: String?) -> Bool {
        searchQuery(placeName: placeName, address: address) != nil
    }

    /// The raw, unencoded query — useful for geocoding as well as for opening.
    static func plainQuery(placeName: String?, address: String?) -> String? {
        let parts = [placeName, address]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private static func searchQuery(placeName: String?, address: String?) -> String? {
        plainQuery(placeName: placeName, address: address)?
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    }
}
