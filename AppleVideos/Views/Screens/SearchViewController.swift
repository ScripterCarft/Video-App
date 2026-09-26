import UIKit

/// Search as a UIKit screen: a `UISearchController` in the navigation bar,
/// always visible, and the results in the shared video list below. While
/// the field is active and empty, the search controller's results
/// controller shows suggestions as a plain list. Before a search, and after
/// the field is cleared, the list shows what to search for.
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
    private let suggestionsController: SearchSuggestionsViewController
    private let searchController: UISearchController

    init(library: LibraryStore, navigator: VideoNavigator) {
        let suggestionsController = SearchSuggestionsViewController(suggestions: Self.suggestions)
        self.suggestionsController = suggestionsController
        searchController = UISearchController(searchResultsController: suggestionsController)
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
        // The large title sits in the bar at the leading edge, like Home.
        navigationItem.largeTitleDisplayMode = .inline
        list.onRefresh = {
            await results.reload()
        }

        searchController.searchBar.placeholder = "Videos, topics, or creators"
        searchController.searchBar.delegate = self
        searchController.searchResultsUpdater = self
        // The results show in this screen's own list; the suggestions only
        // while the field is empty (see `updateSearchResults`).
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.automaticallyShowsSearchResultsController = false
        suggestionsController.onSelect = { [weak self] suggestion in
            self?.search(for: suggestion)
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

    /// Called when the field becomes active or inactive and as its text
    /// changes: the suggestions show while it is active and empty.
    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text ?? ""
        searchController.showsSearchResultsController = searchController.isActive
            && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A suggestion was chosen: search for it right away.
    private func search(for suggestion: String) {
        searchController.searchBar.text = suggestion
        searchController.showsSearchResultsController = false
        searchController.searchBar.resignFirstResponder()
        results.search(suggestion)
    }
}
