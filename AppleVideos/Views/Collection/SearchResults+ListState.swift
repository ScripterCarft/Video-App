import UIKit

extension SearchResults {
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
            return .unavailable(.retry(title: "Search Unavailable", message: errorMessage,
                action: UIAction { [weak self] _ in Task { await self?.reload() } }))
        }
        var noResults = UIContentUnavailableConfiguration.search()
        noResults.text = "No Results for “\(query)”"
        noResults.secondaryText = "Check the spelling or try a new search."
        return .unavailable(noResults)
    }
}
