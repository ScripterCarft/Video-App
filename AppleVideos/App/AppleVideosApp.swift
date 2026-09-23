import SwiftUI

@main
struct AppleVideosApp: App {
    @State private var library = LibraryStore()

    init() {
        // Artwork is requested with `returnCacheDataElseLoad`. The default shared
        // cache is too small to hold thumbnails while scrolling or across launches.
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            directory: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(library)
                .tint(.red)
                .task {
                    await library.refreshRecentlyWatched()
                }
        }
    }
}
