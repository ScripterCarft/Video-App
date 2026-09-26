import AVKit
import UIKit

/// The app's entry point: launch-time setup once per launch, and the scene
/// configuration whose `SceneDelegate` builds the window.
@main
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Saved, History, the Watchlist and watch progress, shared by all screens.
    /// Created in `didFinishLaunching`, after the one-time migrations.
    private(set) var library: LibraryStore?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set the playback category once at launch, as Apple recommends for media
        // apps. AVPlayer activates the session itself when playback starts.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)

        // Artwork is requested with the default cache policy. The default shared
        // cache is too small to hold thumbnails while scrolling or across launches.
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            directory: nil
        )

        // Start watching for Low Data Mode before the first images load.
        _ = NetworkConditions.shared
        StreamingSettings.registerDefaults()
        DownloadSettings.registerDefaults()
        // Moves the library from earlier UserDefaults storage into SwiftData
        // once, before anything reads the store.
        prepareLibrary()
        // Reconnects to downloads that kept running while the app was closed.
        _ = DownloadManager.shared
        // Load YouTube's configuration right away so the first search or Play
        // does not wait for it, then refresh the Watchlist exactly once.
        Task {
            await YouTubeWebConfiguration.shared.prewarm()
            await self.library?.refreshWatchlist()
        }
        return true
    }

    /// Opening and importing must finish before any library screen is built.
    /// A failed attempt leaves both the old payload and the durable store in
    /// place; the scene offers Retry without deleting or replacing either.
    @discardableResult
    func prepareLibrary() -> Bool {
        if library != nil { return true }
        do {
            try LibraryDatabase.open()
            try LegacyLibraryMigration.run()
            try WatchProgressMigration.run()
            library = try LibraryStore()
            return true
        } catch {
            LibraryStorageStatus.shared.report(error, operation: "open your library")
            return false
        }
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    /// The system relaunches the app when background downloads finish; the
    /// download manager calls the handler once it has processed the events.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        DownloadManager.shared.backgroundCompletionHandlers[identifier] = completionHandler
    }

    /// The app itself is portrait only; only the full-screen player may rotate.
    /// Info.plist still lists landscape because it caps every view controller,
    /// including AVPlayerViewController.
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        if let player = top as? AVPlayerViewController, !player.isBeingDismissed {
            return .allButUpsideDown
        }
        return .portrait
    }
}
