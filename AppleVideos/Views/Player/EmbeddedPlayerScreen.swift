import SwiftUI
import UIKit

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

extension View {
    /// Shows the embedded player when `starter` falls back, and cancels a start
    /// that is still resolving when the screen goes away. While AVKit is
    /// presented nothing is resolving, so presenting the player does not cancel it.
    func playbackPresentation(_ starter: PlaybackStarter) -> some View {
        overlay {
            if let fallback = starter.fallback {
                EmbeddedPlayerScreen(video: fallback.video, diagnostic: fallback.diagnostic) {
                    starter.fallback = nil
                }
                .ignoresSafeArea()
            }
        }
        .onDisappear {
            if starter.isPreparing {
                starter.cancel()
            }
        }
        .alert(
            "Mobile Data Is Turned Off",
            isPresented: Binding(
                get: { starter.isShowingMobileDataAlert },
                set: { starter.isShowingMobileDataAlert = $0 }
            )
        ) {
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Turn on Use Mobile Data in Settings to stream videos over mobile data.")
        }
    }
}
