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

        // The app is initialized once per launch, so Continue Watching is
        // refreshed exactly once.
        let library = LibraryStore()
        _library = State(initialValue: library)
        Task {
            await library.refreshRecentlyWatched()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(library)
                .tint(.red)
        }
    }
}
