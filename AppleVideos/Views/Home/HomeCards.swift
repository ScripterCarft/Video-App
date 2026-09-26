import SwiftUI

/// The featured video at the top of Home: artwork, title and a Play button.
/// Tapping anywhere else opens its detail screen (the collection view's
/// selection).
struct HomeFeaturedCard: View {
    let video: Video
    let playback: PlaybackStarter

    @Environment(LibraryStore.self) private var library

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VideoHeroArtwork(video: video, cornerRadius: 22, stageAspectRatio: 2.0 / 3.0)
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.15), .black.opacity(0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            VStack(alignment: .leading, spacing: 10) {
                Text("FEATURED")
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.72))
                Text(video.title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                HStack(alignment: .center) {
                    Button {
                        if playback.isPreparing {
                            playback.cancel()
                        } else {
                            playback.start(video, description: video.descriptionText, library: library)
                        }
                    } label: {
                        PlayButtonContent(
                            progress: library.progress(for: video),
                            isPreparing: playback.isPreparing
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 9)
                        .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if let duration = video.duration {
                        Text(duration)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.68), in: Capsule())
                    }
                }
            }
            .padding(22)
        }
        .padding(.horizontal, 16)
    }
}

/// The Spotlight card at the bottom of Home.
struct HomeSpotlightCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles.tv.fill")
                .font(.system(size: 40))
                .symbolRenderingMode(.hierarchical)
            Text("A calmer way to watch")
                .font(.title2.bold())
            Text("No noisy counters or clutter. Just videos, collections, and your library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        // An opaque system color looks like the material here and costs nothing to draw.
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
    }
}
