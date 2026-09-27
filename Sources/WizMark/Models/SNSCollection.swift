import Foundation

// MARK: - SNS Collection

/// A hardcoded "smart" collection that auto-sorts bookmarks by URL domain.
struct SNSCollection: Identifiable {
    let id: String
    let name: String
    let assetName: String
    let domainPatterns: [String]

    static let all: [SNSCollection] = [
        SNSCollection(id: "sns-instagram", name: "Instagram", assetName: "Instagram", domainPatterns: ["instagram.com"]),
        SNSCollection(id: "sns-x", name: "X", assetName: "X", domainPatterns: ["x.com", "twitter.com"]),
        SNSCollection(id: "sns-tiktok", name: "TikTok", assetName: "TikTok", domainPatterns: ["tiktok.com"]),
        SNSCollection(id: "sns-youtube", name: "YouTube", assetName: "YouTube", domainPatterns: ["youtube.com", "youtu.be"]),
    ]

    /// Whether a bookmark URL matches any of this collection's domain patterns.
    func matches(url: String) -> Bool {
        let lowered = url.lowercased()
        return domainPatterns.contains { lowered.contains($0) }
    }
}

// MARK: - SNS Filter Destination

/// Navigation destination for a filtered SNS bookmark list.
struct SNSFilterDestination: Hashable {
    let name: String
    let assetName: String
    let domainPatterns: [String]
}
