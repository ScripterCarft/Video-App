import SwiftUI

@main
struct AppleVideosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library: LibraryStore

    init() {
        // Artwork is requested with `returnCacheDataElseLoad`. The default shared
        // cache is too small to hold thumbnails while scrolling or across launches.
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            directory: nil
        )

        // The app is initialized once per launch. Load YouTube's configuration
        // right away so the first search or Play does not wait for it, then
        // refresh the Watchlist exactly once.
        // Start watching for Low Data Mode before the first images load.
        _ = NetworkConditions.shared
        StreamingSettings.registerDefaults()
        DownloadSettings.registerDefaults()
        // Moves the library from earlier UserDefaults storage into SwiftData
        // once, before anything reads the store.
        LegacyLibraryMigration.run()
        // Reconnects to downloads that kept running while the app was closed.
        _ = DownloadManager.shared
        let library = LibraryStore()
        _library = State(initialValue: library)
        Task {
            await YouTubeWebConfiguration.shared.prewarm()
            await library.refreshWatchlist()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .downloadFailureAlert()
                .environment(library)
                .environment(DownloadManager.shared)
                .modelContainer(LibraryDatabase.container)
        }
    }
}
