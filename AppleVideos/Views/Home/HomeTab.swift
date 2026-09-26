import SwiftUI
import UIKit

/// The Home tab: a UIKit navigation controller with `HomeViewController`,
/// inside the app's SwiftUI tab view. Videos open with UIKit's zoom
/// transition. The open detail screens are kept in scene storage and
/// restored after a relaunch.
struct HomeTab: View {
    @Environment(LibraryStore.self) private var library
    @State private var playback = PlaybackStarter()
    @SceneStorage("home.routes") private var storedRoutes: Data?

    var body: some View {
        HomeNavigation(
            library: library,
            playback: playback,
            restoredRoutes: storedRoutes.flatMap { try? JSONDecoder().decode([VideoRoute].self, from: $0) } ?? [],
            onRoutesChange: { routes in
                storedRoutes = try? JSONEncoder().encode(routes)
            }
        )
        // The navigation controller reaches under the bars and insets itself.
        .ignoresSafeArea()
        // The featured card's Play button: fallback player and alerts.
        .playbackPresentation(playback)
    }
}

private struct HomeNavigation: UIViewControllerRepresentable {
    let library: LibraryStore
    let playback: PlaybackStarter
    let restoredRoutes: [VideoRoute]
    let onRoutesChange: ([VideoRoute]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> VideoNavigationController {
        let navigator = VideoNavigator(library: library)
        let home = HomeViewController(
            library: library,
            downloads: DownloadManager.shared,
            playback: playback,
            navigator: navigator
        )
        let navigationController = VideoNavigationController(rootViewController: home)
        navigationController.navigationBar.prefersLargeTitles = true
        navigator.navigationController = navigationController

        context.coordinator.navigator = navigator
        context.coordinator.onRoutesChange = onRoutesChange
        navigationController.delegate = context.coordinator
        for route in restoredRoutes {
            navigator.open(route, animated: false)
        }
        return navigationController
    }

    func updateUIViewController(_ navigationController: VideoNavigationController, context: Context) {
        context.coordinator.onRoutesChange = onRoutesChange
    }

    /// Stores the open detail screens whenever the stack changes.
    @MainActor
    final class Coordinator: NSObject, UINavigationControllerDelegate {
        var navigator: VideoNavigator?
        var onRoutesChange: (([VideoRoute]) -> Void)?

        func navigationController(
            _ navigationController: UINavigationController,
            didShow viewController: UIViewController,
            animated: Bool
        ) {
            onRoutesChange?(navigator?.routes ?? [])
        }
    }
}
