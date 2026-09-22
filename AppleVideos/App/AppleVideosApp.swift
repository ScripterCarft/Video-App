import SwiftUI

@main
struct AppleVideosApp: App {
    @State private var library = LibraryStore()

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

