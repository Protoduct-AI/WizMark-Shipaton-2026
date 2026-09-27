import Foundation
@preconcurrency import ConvexMobile
import SwiftData
import UserNotifications
import os

@MainActor
final class AIExtractionService {

    static let shared = AIExtractionService()

    var convexClient: ConvexClientWithAuth<String>?

    /// Why the most recent extraction failed, so the reason survives long
    /// enough to be written onto the bookmark.
    private var lastFailure: ExtractionFailure?

    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "AIExtraction")

    // MARK: - Public

    func processAllPending(context: ModelContext, purchaseService: PurchaseService) async {
        guard purchaseService.isSubscribed else {
            logger.info("AI extraction skipped: Pro subscription required")
            return
        }

        let predicate = #Predicate<Bookmark> { $0.aiStatus == "pending" }
        let descriptor = FetchDescriptor(predicate: predicate)

        guard let bookmarks = try? context.fetch(descriptor) else { return }

        for bookmark in bookmarks {
            await process(bookmark: bookmark, context: context)
        }
    }

    func process(bookmark: Bookmark, context: ModelContext) async {
        // Guard against double-processing: mark as "processing" immediately so
        // the "pending" predicate will not pick this bookmark up again.
        bookmark.aiStatus = "processing"
        bookmark.aiError = nil
        lastFailure = nil
        try? context.save()

        var requestedFields = buildRequestedFields(bookmark)
        guard !requestedFields.isEmpty else {
            bookmark.aiStatus = nil
            return
        }

        let shouldAutoClassify = bookmark.requestAiCategory
        if shouldAutoClassify {
            requestedFields = requestedFields.filter { $0 != "category" }
            requestedFields.append("collection_suggestion")
        }

        let collectionNames = fetchCollectionNames(context: context)

        let result = await extract(
            url: bookmark.url,
            title: bookmark.title,
            description: bookmark.bookmarkDescription,
            requestedFields: requestedFields,
            collectionNames: shouldAutoClassify ? collectionNames : nil
        )

        guard let result else {
            bookmark.aiStatus = "failed"
            bookmark.aiError = (lastFailure ?? .unknown).message
            lastFailure = nil
            bookmark.aiEnrichedAt = Date()
            try? context.save()
            return
        }

        applyResult(result, to: bookmark)

        if shouldAutoClassify, bookmark.collection == nil,
           let suggestion = result.collectionSuggestion, !suggestion.isEmpty {
            assignCollection(named: suggestion, to: bookmark, context: context)
        }

        bookmark.aiStatus = "done"
        bookmark.aiEnrichedAt = Date()
        try? context.save()
        await sendCompletionNotification(title: bookmark.title)
    }

    // MARK: - Collection Helpers

    private func fetchCollectionNames(context: ModelContext) -> [String] {
        let descriptor = FetchDescriptor<BookmarkCollection>(sortBy: [SortDescriptor(\.order)])
        guard let collections = try? context.fetch(descriptor) else { return [] }
        return collections.map(\.name)
    }

    private func assignCollection(named name: String, to bookmark: Bookmark, context: ModelContext) {
        let descriptor = FetchDescriptor<BookmarkCollection>()
        guard let collections = try? context.fetch(descriptor) else { return }
        if let match = collections.first(where: { $0.name == name }) {
            bookmark.collection = match
            bookmark.aiCategory = name
            logger.info("Auto-classified to collection: \(name)")
        }
    }

    // MARK: - Notification

    private func sendCompletionNotification(title: String) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "ai.notification.title", defaultValue: "AI分析完了")
        let name = title.isEmpty ? String(localized: "ai.notification.bookmark", defaultValue: "ブックマーク") : title
        content.body = String(localized: "ai.notification.body", defaultValue: "AI分析が完了しました") + " - " + name
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "ai-extraction-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Build Request

    private func buildRequestedFields(_ bookmark: Bookmark) -> [String] {
        var fields: [String] = []
        if bookmark.requestAiSummary { fields.append("summary") }
        if bookmark.requestAiCategory { fields.append("category") }
        // The place toggles are separate in the UI but ask for one thing: the
        // places on the page. Splitting them into four requests made the model
        // answer about a different place in each.
        let wantsPlaces = bookmark.requestAiPlaceName
            || bookmark.requestAiPlaceAddress
            || bookmark.requestAiPhoneNumber
            || bookmark.requestAiBusinessHours
        if wantsPlaces { fields.append("places") }
        if bookmark.requestAiEventDateTime { fields.append("event_datetime") }
        if bookmark.requestAiRecipe { fields.append("recipe") }
        if bookmark.requestAiRating { fields.append("rating") }
        return fields
    }

    // MARK: - Gemini API with Google Search Grounding

    private var userLanguage: String {
        Locale.current.language.languageCode?.identifier ?? "ja"
    }

    private func extract(
        url: String,
        title: String,
        description: String?,
        requestedFields: [String],
        collectionNames: [String]? = nil
    ) async -> ExtractionResult? {
        guard let client = convexClient else {
            lastFailure = .notAuthenticated
            return nil
        }
        return await extractViaConvex(
            client: client, url: url, title: title,
            description: description, requestedFields: requestedFields,
            collectionNames: collectionNames
        )
    }

    // MARK: - Authenticated Convex Proxy

    private func extractViaConvex(
        client: ConvexClientWithAuth<String>,
        url: String, title: String, description: String?,
        requestedFields: [String], collectionNames: [String]?
    ) async -> ExtractionResult? {
        do {
            var args: [String: ConvexEncodable?] = [
                "url": url,
                "title": title,
                "language": userLanguage,
            ]
            args["requestedFields"] = requestedFields.map { $0 as ConvexEncodable? } as [ConvexEncodable?]
            if let description { args["description"] = description }
            if let collectionNames { args["collectionNames"] = collectionNames.map { $0 as ConvexEncodable? } as [ConvexEncodable?] }

            nonisolated(unsafe) let c = client
            let json: String = try await c.action("aiExtract:extract", with: args)

            guard let data = json.data(using: .utf8) else {
                lastFailure = .malformedResponse
                return nil
            }
            return try JSONDecoder().decode(ExtractionResult.self, from: data)
        } catch {
            logger.error("Convex AI extraction failed: \(error.localizedDescription)")
            lastFailure = ExtractionFailure.classify(error)
            return nil
        }
    }

    // MARK: - Apply Result

    private func applyResult(_ result: ExtractionResult, to bookmark: Bookmark) {
        if let v = result.summary { bookmark.aiSummary = v }
        if let v = result.category { bookmark.aiCategory = v }
        // Setting this also fills the flat place fields from the first entry,
        // which is what search and the older screens read.
        if let places = result.places?.nonEmpty, !places.isEmpty {
            bookmark.extractedPlaces = places
        } else {
            // A response from the previous prompt, or a single-place page the
            // model answered in the old shape.
            if let v = result.placeName { bookmark.aiPlaceName = v }
            if let v = result.placeAddress { bookmark.aiPlaceAddress = v }
            if let v = result.phoneNumber { bookmark.aiPhoneNumber = v }
            if let v = result.businessHours { bookmark.aiBusinessHours = v }
        }
        if let v = result.eventDatetime { bookmark.aiEventDateTime = v }
        if let v = result.recipe { bookmark.aiRecipe = v }
        if let v = result.rating { bookmark.aiRating = v }
    }

}

// MARK: - Extraction Failure

/// Why an extraction did not produce anything.
///
/// The reason used to be discarded and replaced with one sentence, which told
/// the user nothing about whether waiting, reconnecting, or subscribing would
/// change the outcome.
enum ExtractionFailure: String, Codable, Sendable {
    case offline
    case rateLimited
    case notSubscribed
    case notAuthenticated
    case serverError
    case malformedResponse
    case unknown

    /// Built from whatever the transport threw, since the failures arrive as
    /// text rather than as typed errors.
    static func classify(_ error: Error) -> ExtractionFailure {
        let text = error.localizedDescription.lowercased()
        if (error as NSError).domain == NSURLErrorDomain {
            return .offline
        }
        if text.contains("rate") || text.contains("429") || text.contains("quota") {
            return .rateLimited
        }
        if text.contains("not authenticated") || text.contains("unauthenticated") || text.contains("401") {
            return .notAuthenticated
        }
        if text.contains("subscription") || text.contains("entitlement") || text.contains("403") {
            return .notSubscribed
        }
        if text.contains("decode") || text.contains("json") || text.contains("parse") {
            return .malformedResponse
        }
        return .serverError
    }

    var message: String {
        switch self {
        case .offline:
            String(
                localized: "ai.error.offline",
                defaultValue: "通信できませんでした。接続を確認して、もう一度お試しください。"
            )
        case .rateLimited:
            String(
                localized: "ai.error.rateLimited",
                defaultValue: "利用が集中しています。しばらく待ってからお試しください。"
            )
        case .notAuthenticated:
            String(
                localized: "ai.error.notAuthenticated",
                defaultValue: "AI 解析を利用するにはサインインしてください。"
            )
        case .notSubscribed:
            String(
                localized: "ai.error.notSubscribed",
                defaultValue: "この機能には WizMark Pro が必要です。"
            )
        case .serverError:
            String(
                localized: "ai.error.server",
                defaultValue: "解析中に問題が起きました。もう一度お試しください。"
            )
        case .malformedResponse:
            String(
                localized: "ai.error.malformed",
                defaultValue: "結果を読み取れませんでした。もう一度お試しください。"
            )
        case .unknown:
            String(
                localized: "ai.error.extractionFailed",
                defaultValue: "AI 解析に失敗しました。"
            )
        }
    }

    /// Whether trying again has a chance of working.
    var isRetryable: Bool { self != .notSubscribed && self != .notAuthenticated }
}

// MARK: - Extraction Result

struct ExtractionResult: Codable {
    let summary: String?
    let tags: [String]?
    let category: String?
    let collectionSuggestion: String?
    let places: [ExtractedPlace]?
    /// Kept so a response from the previous prompt still decodes.
    let placeName: String?
    let placeAddress: String?
    let phoneNumber: String?
    let businessHours: String?
    let eventDatetime: String?
    let recipe: String?
    let rating: String?

    enum CodingKeys: String, CodingKey {
        case summary, tags, category, recipe, rating, places
        case collectionSuggestion = "collection_suggestion"
        case placeName = "place_name"
        case placeAddress = "place_address"
        case phoneNumber = "phone_number"
        case businessHours = "business_hours"
        case eventDatetime = "event_datetime"
    }
}
