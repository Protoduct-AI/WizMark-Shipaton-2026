import Foundation
import Combine
import ConvexMobile
import os

// MARK: - TagService

/// Subscribes to the user's tags via Convex real-time query.
/// Tags are sorted by usage count descending (server-side).
@Observable
@MainActor
final class TagService {

    // MARK: - Published State

    /// All tags for the current user, sorted by usage count descending.
    private(set) var tags: [Tag] = []

    /// Whether the initial tag load is in progress.
    private(set) var isLoading: Bool = false

    /// Last error from subscription or query.
    private(set) var error: Error?

    // MARK: - Private

    private let client: ConvexClientWithAuth<String>
    private let logger = Logger(subsystem: "com.protoductai.wizmark", category: "TagService")
    private var subscriptionCancellable: AnyCancellable?

    // MARK: - Init

    init(client: ConvexClientWithAuth<String>) {
        self.client = client
    }

    // MARK: - Subscription

    /// Start a real-time subscription to the user's tags.
    /// Each update replaces the full `tags` array.
    func subscribe() {
        unsubscribe()
        isLoading = true
        error = nil

        let publisher: AnyPublisher<[Tag], ClientError> = client.subscribe(to: "tags:list")
        subscriptionCancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self else { return }
                    if case .failure(let subscriptionError) = completion {
                        self.error = subscriptionError
                        self.isLoading = false
                        self.logger.error("Tag subscription failed: \(subscriptionError.localizedDescription, privacy: .public)")
                    }
                },
                receiveValue: { [weak self] (decoded: [Tag]) in
                    guard let self else { return }
                    self.tags = decoded
                    self.isLoading = false
                    self.error = nil
                }
            )

        logger.debug("Tag subscription started")
    }

    /// Stop the real-time subscription.
    func unsubscribe() {
        subscriptionCancellable?.cancel()
        subscriptionCancellable = nil
    }
}
