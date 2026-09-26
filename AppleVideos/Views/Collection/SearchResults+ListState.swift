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
