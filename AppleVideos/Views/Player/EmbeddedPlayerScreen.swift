import SwiftUI

/// Full-screen embedded YouTube player, used when native playback has no
/// compatible source.
struct EmbeddedPlayerScreen: View {
    let video: Video
    let diagnostic: String
    let onClose: () -> Void

    @Environment(LibraryStore.self) private var library
    @State private var didMarkWatched = false
    #if DEBUG
    @State private var showsDiagnostic = true
    #endif

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            YouTubePlayerView(videoID: video.id) {
                markWatchedOnce()
            }
            .ignoresSafeArea()

            Button("Close", systemImage: "xmark", action: onClose)
                .buttonStyle(.borderedProminent)
                .padding()
        }
        .statusBarHidden()
        #if DEBUG
        .alert("Native Playback Debug", isPresented: $showsDiagnostic) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(diagnostic)
        }
        #endif
    }

    private func markWatchedOnce() {
        guard !didMarkWatched else { return }
        didMarkWatched = true
        library.markWatched(video)
    }
}
