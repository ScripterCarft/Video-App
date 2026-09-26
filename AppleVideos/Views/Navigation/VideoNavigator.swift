import SwiftUI
import UIKit

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
        let controller = VideoDetailHostingController(route: route, library: library, navigator: self)
        if let zoomSource {
            controller.preferredTransition = .zoom { _ in zoomSource() }
        }
        navigationController?.pushViewController(controller, animated: animated)
    }

    /// The routes of the detail screens on the stack, bottom to top.
    var routes: [VideoRoute] {
        navigationController?.viewControllers.compactMap { ($0 as? VideoDetailHostingController)?.route } ?? []
    }
}

/// The detail screen on a UIKit navigation stack. For now it hosts the
/// SwiftUI detail screen; the next step replaces it with a UIKit controller.
final class VideoDetailHostingController: UIHostingController<AnyView> {
    let route: VideoRoute

    init(route: VideoRoute, library: LibraryStore, navigator: VideoNavigator) {
        self.route = route
        let screen = VideoDetailScreen(route: route, transition: nil)
            .environment(library)
            .environment(DownloadManager.shared)
            // Up Next opens on the same stack.
            .environment(\.openVideo, OpenVideoAction { [weak navigator] route in
                navigator?.open(route)
            })
        super.init(rootView: AnyView(screen))
        // The detail screen is always dark, like the TV app's.
        overrideUserInterfaceStyle = .dark
        navigationItem.largeTitleDisplayMode = .never
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // White bar buttons on the dark screen, like the TV app.
        navigationController?.navigationBar.tintColor = .white
    }
}
