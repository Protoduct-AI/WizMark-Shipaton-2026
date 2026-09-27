import SwiftUI

// MARK: - WizMarkExport

/// Codable model for .wizmark file export/import.
struct WizMarkExport: Codable {
    let collectionName: String
    let icon: String?
    let color: String?
    let bookmarks: [BookmarkEntry]

    struct BookmarkEntry: Codable {
        let url: String
        let title: String
        let tags: [String]
        let note: String?
    }
}

// MARK: - ShareSheetView

/// UIKit-backed share sheet for sharing file URLs (used for .wizmark export).
struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

}
