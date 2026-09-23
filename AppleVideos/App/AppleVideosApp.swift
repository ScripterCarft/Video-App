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
        // refresh Continue Watching exactly once.
        // Start watching for Low Data Mode before the first images load.
        _ = NetworkConditions.shared
        let library = LibraryStore()
        _library = State(initialValue: library)
        Task {
            await YouTubeWebConfiguration.shared.prewarm()
            await library.refreshRecentlyWatched()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(library)
        }
    }
}
