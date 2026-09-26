import UIKit

/// The app's window: the tab bar controller as its root, restored from the
/// scene's state restoration activity after a relaunch.
@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var restoration: SceneRestoration?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let restoration = SceneRestoration(activity: session.stateRestorationActivity)
        self.restoration = restoration

        let window = UIWindow(windowScene: windowScene)
        self.window = window
        showLibrary()
        window.makeKeyAndVisible()
    }

    private func showLibrary() {
        guard let app = UIApplication.shared.delegate as? AppDelegate,
              let restoration else { return }
        if let library = app.library {
            window?.rootViewController = AppTabBarController(library: library, restoration: restoration)
        } else {
            let unavailable = LibraryUnavailableViewController()
            unavailable.onRetry = { [weak self, weak app] in
                guard let app, app.prepareLibrary() else { return }
                if let issue = LibraryStorageStatus.shared.issue {
                    LibraryStorageStatus.shared.acknowledge(issue.id)
                    LibraryStorageStatus.shared.didSave()
                }
                DownloadManager.shared.reconcileLibrary()
                self?.showLibrary()
                Task { await app.library?.refreshWatchlist() }
            }
            window?.rootViewController = unavailable
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard (UIApplication.shared.delegate as? AppDelegate)?.library != nil else { return }
        DownloadManager.shared.reconcileLibrary()
        window?.rootViewController?.setNeedsUpdateProperties()
    }

    /// Saved by the system when the scene goes to the background.
    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        guard let restoration, let tabBarController = window?.rootViewController as? AppTabBarController else {
            return scene.session.stateRestorationActivity
        }
        return restoration.activity(
            selectedTab: tabBarController.selectedTab?.identifier,
            stacks: tabBarController.stacks
        )
    }
}
