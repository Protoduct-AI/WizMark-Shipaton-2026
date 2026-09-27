import Foundation

/// One place the AI found on a saved page.
///
/// A large share of what people save is a round-up — "10 cafés in Shibuya" is
/// one bookmark and ten places. The extractor used to be asked for a single
/// place, so it either picked one arbitrarily or blended several into an answer
/// that matched none of them.
///
/// Stored as JSON on the bookmark rather than as a related SwiftData entity.
/// A relationship would be the textbook answer, but it drags in a CloudKit
/// schema change and a migration on every existing install, for a value that is
/// only ever read as a whole.
struct ExtractedPlace: Codable, Hashable, Identifiable, Sendable {

    var name: String?
    var address: String?
    var phone: String?
    var hours: String?
    var rating: String?

    /// Stable within a bookmark: the extractor returns places in page order and
    /// the list is replaced wholesale, so position is as good as an id.
    var id: String { [name, address].compactMap { $0 }.joined(separator: "|") }

    /// Whether the entry carries anything worth showing.
    var isEmpty: Bool {
        [name, address, phone, hours, rating]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .allSatisfy(\.isEmpty)
    }

    /// The label to show for the place, falling back to the address.
    var displayName: String? {
        if let name, !name.isEmpty { return name }
        return address
    }
}

extension Array where Element == ExtractedPlace {

    /// Drops entries the extractor returned with nothing in them.
    var nonEmpty: [ExtractedPlace] { filter { !$0.isEmpty } }

    func encoded() -> Data? {
        guard !isEmpty else { return nil }
        return try? JSONEncoder().encode(self)
    }

    static func decoded(from data: Data?) -> [ExtractedPlace] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([ExtractedPlace].self, from: data)) ?? []
    }
}
