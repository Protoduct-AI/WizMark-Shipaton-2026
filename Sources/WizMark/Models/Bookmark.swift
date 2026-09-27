import Foundation
import SwiftData

// MARK: - Bookmark

/// A saved bookmark with URL, OGP metadata, and optional AI enrichment.
/// Persisted via SwiftData with automatic iCloud sync through CloudKit.
@Model
final class Bookmark {

    // MARK: - Core Fields

    /// The bookmarked URL.
    var url: String = ""

    /// Page title (from OGP or HTML `<title>`).
    var title: String = ""

    /// Page description (OGP `og:description` or meta description).
    var bookmarkDescription: String?

    /// Thumbnail image URL (OGP `og:image`).
    var thumbnailUrl: String?

    /// User-written note attached to the bookmark.
    var note: String?

    /// Rich text note data (NSAttributedString archived as Data).
    var noteRichData: Data?

    /// User-assigned tags. Always present (empty array when no tags).
    var tags: [String] = []

    /// When the bookmark was created.
    var createdAt: Date = Date()

    /// When the bookmark was last updated.
    var updatedAt: Date = Date()

    /// Display order for manual sorting. Lower values appear first.
    var displayOrder: Int = 0

    // MARK: - OGP Metadata (flat fields, no nested object)

    /// The site name from OGP metadata (e.g. "GitHub").
    var siteName: String?

    /// The OGP type (e.g. "article", "website").
    var ogType: String?

    /// The canonical URL from OGP metadata.
    var canonicalUrl: String?

    /// The favicon URL.
    var favicon: String?

    /// The locale from OGP metadata.
    var ogLocale: String?

    /// The page author from OGP or meta tags.
    var ogAuthor: String?

    // MARK: - AI Extraction Request Flags

    var requestAiSummary: Bool = false
    var requestAiTags: Bool = false
    var requestAiCategory: Bool = false
    var requestAiPlaceName: Bool = false
    var requestAiPlaceAddress: Bool = false
    var requestAiPhoneNumber: Bool = false
    var requestAiBusinessHours: Bool = false
    var requestAiEventDateTime: Bool = false
    var requestAiRecipe: Bool = false
    var requestAiRating: Bool = false

    // MARK: - AI Enrichment (flat fields, no nested object)

    /// Enrichment status: "pending", "done", or "failed".
    var aiStatus: String?

    /// 2-3 sentence summary of the bookmarked page.
    var aiSummary: String?

    /// AI-generated tags (3-6 related tags).
    /// Every place found on the page, as JSON.
    ///
    /// The single `aiPlaceName` / `aiPlaceAddress` pair below still holds the
    /// first entry: existing rows have it, search reads it, and the detail
    /// screen falls back to it. This is the full list.
    var aiPlacesData: Data?

    /// Retained for records written before AI tags were removed.
    ///
    /// Nothing writes or shows this any more. Dropping it from the schema would
    /// force a migration on every existing install for no gain.
    var aiTags: [String]?

    /// Single category (e.g. "Tech Article", "Restaurant", "Product", "News").
    var aiCategory: String?

    /// Place name if the page is about a real-world location.
    var aiPlaceName: String?

    /// Place address if the page is about a real-world location.
    var aiPlaceAddress: String?

    /// Place map URL if available.
    var aiPlaceMapUrl: String?

    /// Phone number extracted from the page.
    var aiPhoneNumber: String?

    /// Business hours extracted from the page.
    var aiBusinessHours: String?

    /// Event date/time extracted from the page.
    var aiEventDateTime: String?

    /// Recipe (ingredients + steps) extracted from the page.
    var aiRecipe: String?

    /// Rating/review score extracted from the page (e.g. "4.5/5").
    var aiRating: String?

    /// Error message if enrichment failed.
    var aiError: String?

    /// When AI enrichment was performed.
    var aiEnrichedAt: Date?

    // MARK: - Display Preferences

    var showImage: Bool = true
    var showDescription: Bool = true
    var showTags: Bool = true
    var showDate: Bool = true
    var showSiteName: Bool = true
    var showAuthor: Bool = true
    var showFavicon: Bool = false
    var showOgType: Bool = false
    var showCanonicalUrl: Bool = false
    var showLocale: Bool = false
    var showAiSummary: Bool = true
    var showAiTags: Bool = true
    var showAiCategory: Bool = true
    var showPlaceName: Bool = true
    var showPlaceAddress: Bool = true
    var showPlaceMap: Bool = true
    var showPhoneNumber: Bool = true
    var showBusinessHours: Bool = true
    var showEventDateTime: Bool = true
    var showRecipe: Bool = true
    var showRating: Bool = true

    // MARK: - Relationship

    /// The collection this bookmark belongs to. Nil means "Inbox" / uncategorized.
    var collection: BookmarkCollection?

    // MARK: - Init

    init(
        url: String,
        title: String = "",
        description: String? = nil,
        thumbnailUrl: String? = nil
    ) {
        self.url = url
        self.title = title
        self.bookmarkDescription = description
        self.thumbnailUrl = thumbnailUrl
    }

    // MARK: - Places

    /// Every place the extractor found, newest extraction wins.
    ///
    /// Falls back to the single-place fields so bookmarks saved before this
    /// existed still show their place.
    var extractedPlaces: [ExtractedPlace] {
        get {
            let stored = [ExtractedPlace].decoded(from: aiPlacesData)
            if !stored.isEmpty { return stored }

            let legacy = ExtractedPlace(
                name: aiPlaceName,
                address: aiPlaceAddress,
                phone: aiPhoneNumber,
                hours: aiBusinessHours,
                rating: aiRating
            )
            return legacy.isEmpty ? [] : [legacy]
        }
        set {
            let places = newValue.nonEmpty
            aiPlacesData = places.encoded()

            // Keep the flat fields in step: search matches on them, and older
            // screens read them directly.
            let first = places.first
            aiPlaceName = first?.name
            aiPlaceAddress = first?.address
            aiPhoneNumber = first?.phone
            aiBusinessHours = first?.hours
            aiRating = first?.rating
        }
    }

    // MARK: - Limits

    /// Longest title that will be stored.
    ///
    /// Page titles run to about a hundred characters at their worst; anything
    /// past this is a paste accident. The cap keeps a stray novel out of the
    /// row, out of the navigation bar, and out of the payload sent to everyone
    /// a collection is shared with.
    static let titleCharacterLimit = 200

    // MARK: - Computed

    /// Whether AI enrichment completed successfully.
    var isEnriched: Bool { aiStatus == "done" }

    /// Whether AI enrichment is queued or running.
    ///
    /// Covers both states on purpose. A bookmark moves from "pending" to
    /// "processing" the moment the extractor picks it up, and checking only the
    /// former left the UI showing nothing for the entire time the request was
    /// actually in flight — which is all of it.
    var isEnriching: Bool { aiStatus == "pending" || aiStatus == "processing" }

    /// Whether AI enrichment failed.
    var isEnrichmentFailed: Bool { aiStatus == "failed" }

    /// The domain extracted from the bookmark URL.
    var domain: String? { URL(string: url)?.host(percentEncoded: false) }
}
