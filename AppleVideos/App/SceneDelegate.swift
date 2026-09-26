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
        guard let windowScene = scene as? UIWindowScene,
              let library = (UIApplication.shared.delegate as? AppDelegate)?.library
        else { return }

        let restoration = SceneRestoration(activity: session.stateRestorationActivity)
        self.restoration = restoration

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = AppTabBarController(library: library, restoration: restoration)
        window.makeKeyAndVisible()
        self.window = window
    }

    /// Saved by the system when the scene goes to the background.
    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        guard let restoration, let tabBarController = window?.rootViewController as? AppTabBarController else {
            return nil
        }
        return restoration.activity(
            selectedTab: tabBarController.selectedTab?.identifier,
            homeRoutes: tabBarController.homeNavigator.routes
        )
    }
}
