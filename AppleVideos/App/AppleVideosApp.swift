import SwiftUI

@main
struct AppleVideosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(library)
                .task {
                    await library.refreshRecentlyWatched()
                }
        }
    }
}
