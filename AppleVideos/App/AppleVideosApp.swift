import SwiftUI

@main
struct AppleVideosApp: App {
    @State private var library = LibraryStore()
    @State private var playback = PlaybackStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(library)
                .environment(playback)
                .tint(.red)
        }
    }
}
