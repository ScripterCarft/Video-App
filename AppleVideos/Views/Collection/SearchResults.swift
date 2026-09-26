import Observation
import UIKit

/// YouTube search results for a query, observable, for a
/// `VideoListViewController`: Search's results and Explore's topics.
/// Results stay loaded when the list reappears; a new query replaces them.
@MainActor
@Observable
final class SearchResults {
    private(set) var query = ""
    private(set) var videos: [Video] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    @ObservationIgnored private var loadedQuery: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Searches for `query`, unless its results are already loaded. An empty
    /// query clears the results.
    func search(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != loadedQuery || query != self.query else { return }
        self.query = query
        task?.cancel()
        videos = []
        errorMessage = nil
        guard !query.isEmpty else {
            loadedQuery = nil
            isLoading = false
            return
        }
        task = Task { await load() }
    }

    /// Loads the current query again, past the search cache.
    func reload() async {
        task?.cancel()
        await load(bypassingCache: true)
    }

    private func load(bypassingCache: Bool = false) async {
        let query = query
        isLoading = true
        errorMessage = nil
        do {
            let found = try await YouTubeService.shared.search(query, bypassingCache: bypassingCache)
            guard !Task.isCancelled else { return }
            videos = found
            loadedQuery = query
        } catch {
            // A newer query cancelled this request. URLSession reports that as
            // URLError.cancelled rather than CancellationError, so check the task.
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// The list's state: the results, loading, an error with Try Again, or
    /// no results. `idle` shows before anything was searched.
    func listState(idle: UIContentUnavailableConfiguration? = nil) -> VideoListViewController.State {
        if query.isEmpty, let idle {
            return .unavailable(idle)
        }
        if !videos.isEmpty {
            return .videos(videos)
        }
        if isLoading {
            return .loading("Searching YouTube…")
        }
        if let errorMessage {
            var unavailable = UIContentUnavailableConfiguration.empty()
            unavailable.image = UIImage(systemName: "wifi.exclamationmark")
            unavailable.text = "Search Unavailable"
            unavailable.secondaryText = errorMessage
            var button = UIButton.Configuration.borderedProminent()
            button.title = "Try Again"
            unavailable.button = button
            unavailable.buttonProperties.primaryAction = UIAction { [weak self] _ in
                Task { await self?.reload() }
            }
            return .unavailable(unavailable)
        }
        var noResults = UIContentUnavailableConfiguration.search()
        noResults.text = "No Results for “\(query)”"
        noResults.secondaryText = "Check the spelling or try a new search."
        return .unavailable(noResults)
    }
}
