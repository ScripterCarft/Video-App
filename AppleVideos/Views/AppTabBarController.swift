import SwiftUI
import UIKit

/// The app's tab bar: Home, Explore, Library and Search as `UITab`s. Home is
/// UIKit; the other tabs are SwiftUI in hosting controllers until they are
/// rebuilt in UIKit. Search is a normal tab in the bar, like before.
///
/// Also reports a download that could not be completed, wherever the app is.
final class AppTabBarController: UITabBarController {
    private enum Identifier {
        static let home = "home"
        static let explore = "explore"
        static let library = "library"
        static let search = "search"
    }

    /// Opens videos on Home; its routes are what Home restores.
    let homeNavigator: VideoNavigator
    private let downloads = DownloadManager.shared
    /// The failure the alert on screen reports, so it is shown only once.
    private var reportedFailureID: UUID?

    init(library: LibraryStore, restoration: SceneRestoration) {
        homeNavigator = VideoNavigator(library: library)
        super.init(nibName: nil, bundle: nil)

        let home = HomeViewController(library: library, downloads: downloads, navigator: homeNavigator)
        let homeNavigation = VideoNavigationController(rootViewController: home)
        homeNavigation.navigationBar.prefersLargeTitles = true
        homeNavigator.navigationController = homeNavigation
        for route in restoration.homeRoutes {
            homeNavigator.open(route, animated: false)
        }

        func hosted(_ view: some View) -> UIViewController {
            UIHostingController(rootView: view
                .environment(library)
                .environment(DownloadManager.shared)
                .environment(\.sceneRestoration, restoration)
                .modelContainer(LibraryDatabase.container))
        }

        tabs = [
            UITab(title: "Home", image: UIImage(systemName: "house"), identifier: Identifier.home) { _ in
                homeNavigation
            },
            UITab(title: "Explore", image: UIImage(systemName: "safari"), identifier: Identifier.explore) { _ in
                hosted(ExploreView())
            },
            UITab(title: "Library", image: UIImage(systemName: "rectangle.stack"), identifier: Identifier.library) { _ in
                hosted(LibraryView())
            },
            UITab(title: "Search", image: UIImage(systemName: "magnifyingglass"), identifier: Identifier.search) { _ in
                hosted(SearchView())
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
