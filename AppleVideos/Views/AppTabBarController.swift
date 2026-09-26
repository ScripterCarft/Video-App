import SwiftUI
import UIKit

/// The app's tab bar: Home, Explore, Library and Search as `UITab`s, each
/// UIKit tab a `VideoNavigationController` with its own `VideoNavigator`.
/// Tabs not yet rebuilt in UIKit are SwiftUI in hosting controllers. Search
/// is a normal tab in the bar, like before.
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

        func hosted(_ view: some View) -> UIViewController {
            UIHostingController(rootView: view
                .environment(library)
                .environment(DownloadManager.shared)
                .environment(\.sceneRestoration, restoration)
                .modelContainer(LibraryDatabase.container))
        }

        let home = navigation(for: Identifier.home, restoring: restoration) { navigator in
            HomeViewController(library: library, downloads: DownloadManager.shared, navigator: navigator)
        }
        let explore = navigation(for: Identifier.explore, restoring: restoration) { navigator in
            ExploreViewController(library: library, navigator: navigator)
        }
        let search = navigation(for: Identifier.search, restoring: restoration) { navigator in
            SearchViewController(library: library, navigator: navigator)
        }

        tabs = [
            UITab(title: "Home", image: UIImage(systemName: "house"), identifier: Identifier.home) { _ in
                home
            },
            UITab(title: "Explore", image: UIImage(systemName: "safari"), identifier: Identifier.explore) { _ in
                explore
            },
            UITab(title: "Library", image: UIImage(systemName: "rectangle.stack"), identifier: Identifier.library) { _ in
                hosted(LibraryView())
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
        case .library:
            return nil
        }
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
