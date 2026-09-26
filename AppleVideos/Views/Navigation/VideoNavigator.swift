import UIKit

/// A tab's navigation controller. The screen on top decides the status bar
/// style, so the dark detail screen gets light status bar text.
final class VideoNavigationController: UINavigationController {
    override var childForStatusBarStyle: UIViewController? {
        topViewController
    }
}

/// Opens videos on a UIKit navigation controller with Apple's zoom
/// transition (`preferredTransition = .zoom`): the detail screen grows out
/// of the tapped card's artwork and shrinks back into it, and swiping it
/// away works the same way.
@MainActor
final class VideoNavigator {
    weak var navigationController: UINavigationController?
    private let library: LibraryStore

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

    /// The routes of the detail screens on the stack, bottom to top.
    var routes: [VideoRoute] {
        navigationController?.viewControllers.compactMap { ($0 as? VideoDetailViewController)?.route } ?? []
    }
}
