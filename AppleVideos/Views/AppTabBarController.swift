import UIKit

/// The app's tab bar: Home, Explore, Library and Search as `UITab`s, each a
/// `VideoNavigationController` with its own `VideoNavigator`, whose stack is
/// restored after a relaunch. Search is a normal tab in the bar, like before.
///
/// Also reports a download that could not be completed, wherever the app is.
final class AppTabBarController: UITabBarController {
    private enum Identifier {
        static let home = "home"
        static let explore = "explore"
        static let library = "library"
        static let search = "search"
    }

    private let library: LibraryStore
    private let downloads = DownloadManager.shared
    /// The UIKit tabs' navigators by tab, whose routes are restored.
    private var navigators: [String: VideoNavigator] = [:]
    /// The failure the alert on screen reports, so it is shown only once.
    private var reportedFailureID: UUID?

    /// The screens on each UIKit tab's stack, for restoration.
    var stacks: [String: [AppRoute]] {
        navigators.mapValues(\.routes)
    }

    init(library: LibraryStore, restoration: SceneRestoration) {
        self.library = library
        super.init(nibName: nil, bundle: nil)

        let home = navigation(for: Identifier.home, restoring: restoration) { navigator in
            HomeViewController(library: library, downloads: DownloadManager.shared, navigator: navigator)
        }
        let explore = navigation(for: Identifier.explore, restoring: restoration) { navigator in
            ExploreViewController(library: library, navigator: navigator)
        }
        let search = navigation(for: Identifier.search, restoring: restoration) { navigator in
            SearchViewController(library: library, navigator: navigator)
        }
        let libraryTab = navigation(for: Identifier.library, restoring: restoration) { navigator in
            LibraryViewController(library: library, navigator: navigator)
        }

        tabs = [
            UITab(title: "Home", image: UIImage(systemName: "house"), identifier: Identifier.home) { _ in
                home
            },
            UITab(title: "Explore", image: UIImage(systemName: "safari"), identifier: Identifier.explore) { _ in
                explore
            },
            UITab(title: "Library", image: UIImage(systemName: "rectangle.stack"), identifier: Identifier.library) { _ in
                libraryTab
            },
            UITab(title: "Search", image: UIImage(systemName: "magnifyingglass"), identifier: Identifier.search) { _ in
                search
            }
        ]
        if let identifier = restoration.selectedTab, let tab = tab(forIdentifier: identifier) {
            selectedTab = tab
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// A UIKit tab: its navigation controller with `root`, and the screens
    /// that were open on it restored.
    private func navigation(
        for identifier: String,
        restoring restoration: SceneRestoration,
        root: (VideoNavigator) -> UIViewController
    ) -> UINavigationController {
        let navigator = VideoNavigator(library: library)
        navigator.makeScreen = { [weak self, weak navigator] route in
            guard let self, let navigator else { return nil }
            return self.screen(for: route, navigator: navigator)
        }
        let navigationController = VideoNavigationController(rootViewController: root(navigator))
        navigationController.navigationBar.prefersLargeTitles = true
        navigator.navigationController = navigationController
        navigators[identifier] = navigator
        for route in restoration.stacks[identifier] ?? [] {
            navigator.show(route, animated: false)
        }
        return navigationController
    }

    /// The screens that routes other than videos show.
    private func screen(for route: AppRoute, navigator: VideoNavigator) -> UIViewController? {
        switch route {
        case .video:
            return nil
        case let .topic(title):
            let results = SearchResults()
            results.search(title)
            let controller = VideoListViewController(
                title: title,
                section: "topic-\(title)",
                route: route,
                library: library,
                navigator: navigator,
                emptyState: .search()
            ) {
                results.listState()
            }
            controller.onRefresh = {
                await results.reload()
            }
            controller.navigationItem.largeTitleDisplayMode = .always
            return controller
        case let .library(list):
            return libraryScreen(list, route: route, navigator: navigator)
        }
    }

    /// Saved, Downloaded or History: the stored videos, refreshed when the
    /// list opens, with Remove All as a system menu for Downloaded and
    /// History.
    private func libraryScreen(_ list: LibraryList, route: AppRoute, navigator: VideoNavigator) -> UIViewController {
        let library = library
        let downloads = downloads
        let videos: @MainActor () -> [Video]
        let title: String
        var empty = UIContentUnavailableConfiguration.empty()
        empty.image = UIImage(systemName: "rectangle.stack.badge.plus")
        var removeAll: UIMenu?

        switch list {
        case .saved:
            title = "Saved"
            videos = { library.savedVideos }
            empty.text = "No Saved Videos"
            empty.secondaryText = "Use the bookmark button or a video's context menu to save it."
        case .downloaded:
            title = "Downloaded"
            videos = { downloads.videos }
            empty.text = "No Downloads"
            empty.secondaryText = "Use the download button or a video's context menu to watch it offline."
            removeAll = Self.removeAllMenu(
                header: "All downloaded videos will be removed from your iPhone.",
                action: "Remove All Downloads"
            ) {
                downloads.removeAll()
            }
        case .history:
            title = "History"
            videos = { library.recentlyWatched }
            empty.text = "No Watch History"
            empty.secondaryText = "Videos you play will appear here."
            removeAll = Self.removeAllMenu(
                header: "Your watch history and the saved positions of these videos will be removed. Downloaded videos stay.",
                action: "Remove All from History"
            ) {
                library.removeAllFromRecentlyWatched { downloads.isDownloaded($0) }
            }
        }

        let controller = VideoListViewController(
            title: title,
            section: list.rawValue,
            route: route,
            library: library,
            navigator: navigator,
            emptyState: empty
        ) {
            .videos(videos())
        }
        // Stored data shows right away; cards update as fresh data arrives.
        controller.onAppear = {
            await library.refreshMetadata(of: videos())
        }
        if let removeAll {
            controller.trailingItem = UIBarButtonItem(title: "Remove All", menu: removeAll)
        }
        return controller
    }

    /// Remove All as a system menu: an explanation as the section header
    /// above the destructive action.
    private static func removeAllMenu(header: String, action: String, perform: @escaping @MainActor () -> Void) -> UIMenu {
        UIMenu(children: [
            UIMenu(title: header, options: .displayInline, children: [
                UIAction(title: action, image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    perform()
                }
            ])
        ])
    }

    /// The selected tab's screen decides the status bar style, so the dark
    /// detail screen gets light status bar text.
    override var childForStatusBarStyle: UIViewController? {
        selectedViewController
    }

    /// UIKit tracks the observable download failure read here and calls
    /// this again when it changes.
    override func updateProperties() {
        super.updateProperties()
        guard let failure = downloads.failure, failure.id != reportedFailureID else { return }
        reportedFailureID = failure.id

        let alert = UIAlertController(
            title: "Download Failed",
            message: "“\(failure.video.title)” couldn't be downloaded. \(failure.message)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Try Again", style: .default) { [downloads] _ in
            downloads.failure = nil
            downloads.download(failure.video)
        })
        alert.addAction(UIAlertAction(title: "OK", style: .cancel) { [downloads] _ in
            downloads.failure = nil
        })
        (NativePlayback.topViewController() ?? self).present(alert, animated: true)
    }
}
