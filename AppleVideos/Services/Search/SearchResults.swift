import Foundation
import Observation

/// Search and topic results. Every search/refresh owns an immutable query and
/// request ID; obsolete completions may change neither content nor load state.
@MainActor
@Observable
final class SearchResults {
    typealias Fetch = @MainActor (String, Bool) async throws -> [Video]

    private(set) var query = ""
    private(set) var videos: [Video] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    @ObservationIgnored private var loadedQuery: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private let fetch: Fetch

    init(fetch: @escaping Fetch = { query, bypassingCache in
        try await YouTubeService.shared.search(query, bypassingCache: bypassingCache)
    }) {
        self.fetch = fetch
    }

    deinit { task?.cancel() }

    #if SEARCH_CHECKS
    var currentTask: Task<Void, Never>? { task }
    #endif

    func search(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != self.query || (!isLoading && loadedQuery != query) else { return }
        self.query = query
        videos = []
        loadedQuery = nil
        start(bypassingCache: false)
    }

    /// Uses the same owned request as normal searches. Keep displayed results
    /// while refreshing, and keep the refresh control waiting for this request.
    func reload() async {
        guard !Task.isCancelled else { return }
        guard let request = start(bypassingCache: true) else { return }
        await withTaskCancellationHandler {
            await request.value
        } onCancel: {
            request.cancel()
        }
    }

    @discardableResult
    private func start(bypassingCache: Bool) -> Task<Void, Never>? {
        task?.cancel()
        task = nil
        requestID = nil
        errorMessage = nil
        isLoading = !query.isEmpty
        guard !query.isEmpty else { return nil }

        let id = UUID()
        let query = query
        let fetch = fetch
        requestID = id
        let request = Task { [weak self] in
            // Cleanup belongs to this request too: an old completion must not
            // stop the spinner or discard the handle of a newer request.
            defer {
                if let self, self.requestID == id {
                    self.isLoading = false
                    self.task = nil
                    self.requestID = nil
                }
            }
            do {
                try Task.checkCancellation()
                let found = try await fetch(query, bypassingCache)
                try Task.checkCancellation()
                guard let self, self.requestID == id else { return }
                self.videos = found
                self.loadedQuery = query
            } catch {
                guard !Task.isCancelled, let self, self.requestID == id else { return }
                self.errorMessage = error.localizedDescription
            }
        }
        task = request
        return request
    }
}
