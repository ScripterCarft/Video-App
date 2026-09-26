import UIKit

/// Search as a UIKit screen: a `UISearchController` in the navigation bar,
/// always visible, with the system's search suggestions, and the results in
/// the shared video list below. Before a search, and after the field is
/// cleared, the list shows what to search for.
final class SearchViewController: UIViewController, UISearchBarDelegate, UISearchResultsUpdating {
    private static let suggestions = [
        "Kurzgesagt",
        "Veritasium",
        "Physics",
        "Space documentaries",
        "Technology"
    ]

    private let results: SearchResults
    private let list: VideoListViewController
    private let searchController = UISearchController(searchResultsController: nil)

    init(library: LibraryStore, navigator: VideoNavigator) {
        var idle = UIContentUnavailableConfiguration.empty()
        idle.image = UIImage(systemName: "play.rectangle.on.rectangle")
        idle.text = "Search YouTube"
        idle.secondaryText = "Search for videos, topics, or creators."

        let results = SearchResults()
        self.results = results
        list = VideoListViewController(
            title: "Search",
            section: "search",
            route: nil,
            library: library,
            navigator: navigator,
            emptyState: .search()
        ) {
            results.listState(idle: idle)
        }
        super.init(nibName: nil, bundle: nil)
        title = "Search"
        list.onRefresh = {
            await results.reload()
        }

        searchController.searchBar.placeholder = "Videos, topics, or creators"
        searchController.searchBar.delegate = self
        searchController.searchResultsUpdater = self
        // The results show in this screen's own list.
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchSuggestions = Self.suggestions.map {
            UISearchSuggestionItem(localizedSuggestion: $0, localizedDescription: nil, iconImage: UIImage(systemName: "magnifyingglass"))
        }
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(list)
        list.view.frame = view.bounds
        list.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(list.view)
        list.didMove(toParent: self)
        // The bar's large title and scroll edge effect follow the list.
        setContentScrollView(list.scrollView, for: .top)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The app's tint again after the white of the detail screen.
        navigationController?.navigationBar.tintColor = nil
    }

    // MARK: - Searching

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        results.search(searchBar.text ?? "")
    }

    /// Clearing the field returns to what to search for.
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results.search("")
        }
    }

    func updateSearchResults(for searchController: UISearchController) {}

    /// A suggestion was chosen: search for it right away.
    func updateSearchResults(for searchController: UISearchController, selecting searchSuggestion: any UISearchSuggestion) {
        let text = searchSuggestion.localizedSuggestion ?? ""
        searchController.searchBar.text = text
        results.search(text)
        searchController.searchBar.resignFirstResponder()
    }
}
