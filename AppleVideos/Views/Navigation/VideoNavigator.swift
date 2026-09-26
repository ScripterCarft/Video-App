import UIKit

/// A tab's navigation controller. The screen on top decides the status bar
/// style, so the dark detail screen gets light status bar text, and the
/// bar's buttons are white on the detail screen, in the app's tint
/// elsewhere.
final class VideoNavigationController: UINavigationController, UINavigationControllerDelegate {
    override var childForStatusBarStyle: UIViewController? {
        topViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
    }

    /// Sets the bar's tint for the screen about to show, and back for the
    /// previous one if an interactive transition (a swipe back) is cancelled.
    func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        applyTint(for: viewController)
        transitionCoordinator?.notifyWhenInteractionChanges { [weak self] context in
            MainActor.assumeIsolated {
                guard context.isCancelled, let previous = context.viewController(forKey: .from) else { return }
                self?.applyTint(for: previous)
            }
        }
    }

    private func applyTint(for viewController: UIViewController) {
        // The detail screen is always dark, like the TV app's.
        navigationBar.tintColor = viewController is VideoDetailViewController ? .white : nil
    }
}

/// A video's detail screen: only the video's ID, so routes stay small and
/// can be restored after a relaunch. The detail screen reads the video from
/// `VideoCatalog`.
struct VideoRoute: Hashable, Codable {
    let videoID: String

    /// A route to `video`; the catalog remembers the video for the destination.
    @MainActor
    init(video: Video) {
        VideoCatalog.shared.remember(video)
        videoID = video.id
    }
}

/// A screen pushed on a tab's stack, `Codable` so the stack can be restored
/// after a relaunch (`SceneRestoration`).
enum AppRoute: Hashable, Codable {
    /// A video's detail screen.
    case video(VideoRoute)
    /// Explore's results for a topic.
    case topic(String)
    /// One of the Library's lists.
    case library(LibraryList)
}

enum LibraryList: String, Hashable, Codable {
    case saved
    case downloaded
    case history
}

/// A screen that a route shows; the navigator collects the routes of the
/// screens on its stack for restoration. A tab's root screen has none.
@MainActor
protocol RoutedScreen: UIViewController {
    var appRoute: AppRoute? { get }
}

/// Opens screens on a tab's UIKit navigation controller. Videos open with
/// Apple's zoom transition (`preferredTransition = .zoom`): the detail screen
/// grows out of the tapped card's artwork and shrinks back into it, and
/// swiping it away works the same way.
@MainActor
final class VideoNavigator {
    weak var navigationController: UINavigationController?
    private let library: LibraryStore
    /// Builds the tab's screens for routes other than videos.
    var makeScreen: ((AppRoute) -> UIViewController?)?

    init(library: LibraryStore) {
        self.library = library
    }

    /// Pushes the detail screen for `route`. `zoomSource` returns the view to
    /// zoom from and back to, looked up each time, since cells are reused.
    func open(_ route: VideoRoute, zoomSource: (@MainActor () -> UIView?)? = nil, animated: Bool = true) {
        let controller = VideoDetailViewController(route: route, library: library) { [weak self] route, source in
            self?.open(route, zoomSource: source)
        }
        if let zoomSource {
            controller.preferredTransition = .zoom { _ in zoomSource() }
        }
        navigationController?.pushViewController(controller, animated: animated)
    }

    /// Pushes the screen for `route`.
    func show(_ route: AppRoute, animated: Bool = true) {
        if case let .video(videoRoute) = route {
            open(videoRoute, animated: animated)
        } else if let controller = makeScreen?(route) {
            navigationController?.pushViewController(controller, animated: animated)
        }
    }

    /// The routes of the screens on the stack above its root, bottom to top.
    var routes: [AppRoute] {
        navigationController?.viewControllers.compactMap { ($0 as? RoutedScreen)?.appRoute } ?? []
    }
}
