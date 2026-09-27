import SwiftUI
import UIKit

// MARK: - ActivityShareSheet

/// Presents the system share sheet for items that are only known at runtime.
///
/// `ShareLink` covers the common case, but it needs its payload up front.
/// Invitation links are issued asynchronously, so they are handed to
/// `UIActivityViewController` once the CloudKit share resolves.
struct ActivityShareSheet: UIViewControllerRepresentable {

    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - ShareTarget

/// Identifiable wrapper so a resolved URL can drive `sheet(item:)`.
struct ShareTarget: Identifiable {
    let id = UUID()
    let url: URL
}
