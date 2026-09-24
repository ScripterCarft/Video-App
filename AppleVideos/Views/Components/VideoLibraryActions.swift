import SwiftUI

/// The Watchlist and History actions for a video in the card's context
/// menu. Each appears only when it applies.
struct VideoLibraryActions: View {
    let video: Video
    /// Called after an action, for haptic feedback.
    let onAction: () -> Void

    @Environment(LibraryStore.self) private var library

    var body: some View {
        if library.isInWatchlist(video) {
            Button("Remove from Watchlist", systemImage: "minus.circle") {
                perform { library.removeFromWatchlist(video) }
            }
            Button("Mark as Watched", systemImage: "rectangle.badge.checkmark") {
                perform { library.markAsWatched(video) }
            }
        } else {
            Button("Add to Watchlist", systemImage: "plus.circle") {
                perform { library.addToWatchlist(video) }
            }
        }

        if library.isInRecentlyWatched(video) {
            Button("Remove from Recently Watched", systemImage: "trash") {
                perform { library.removeFromRecentlyWatched(video) }
            }
        }
    }

    private func perform(_ action: () -> Void) {
        // Cards leaving a list animate out.
        withAnimation {
            action()
        }
        onAction()
    }
}
