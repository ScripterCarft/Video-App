import SwiftUI

struct HomeView: View {
    @Namespace private var transition
    @Environment(LibraryStore.self) private var library
    @Environment(DownloadManager.self) private var downloads
    @State private var playback = PlaybackStarter()

    private let featured = Video.curated[0]
    private let picks = Array(Video.curated.dropFirst())

    var body: some View {
        RestorableNavigationStack(id: "home.path") { path in
            HomeCollection(
                featured: featured,
                shelves: shelves,
                transition: transition,
                library: library,
                downloads: downloads,
                playback: playback,
                onOpen: { route in path.wrappedValue.append(route) }
            )
            // The collection view reaches under the bars and insets itself.
            .ignoresSafeArea()
            .navigationTitle("Home")
            // The large title sits in the bar at the leading edge, like the TV app.
            .toolbarTitleDisplayMode(.inlineLarge)
            .videoDestination(transition: transition)
            .playbackPresentation(playback)
            .task {
                // The featured video has a Play button right on Home.
                await NativePlayback.prefetch(featured)
            }
        }
    }

    private var shelves: [HomeCollection.Shelf] {
        [
            // The Watchlist: started videos and videos added by hand.
            HomeCollection.Shelf(
                id: "continue",
                title: "Continue Watching",
                subtitle: "Pick up where you left off",
                videos: library.watchlist
            ),
            HomeCollection.Shelf(
                id: "picks",
                title: "Made for Tonight",
                subtitle: "Kurzgesagt, Veritasium, and more",
                videos: picks
            )
        ]
    }
}
