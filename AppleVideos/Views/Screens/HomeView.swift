import SwiftUI

struct HomeView: View {
    @Namespace private var transition
    @Environment(LibraryStore.self) private var library
    @State private var playback = PlaybackStarter()

    private let featured = Video.curated[0]
    private let picks = Array(Video.curated.dropFirst())

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    VideoLink(video: featured, section: "featured", transition: transition) {
                        featuredHero
                    }
                    // Play sits above the link so that it starts playback while the
                    // rest of the hero opens the detail screen.
                    .overlay(alignment: .bottomLeading) {
                        Button {
                            if playback.isPreparing {
                                playback.cancel()
                            } else {
                                playback.start(featured, description: featured.descriptionText, library: library)
                            }
                        } label: {
                            featuredPlayLabel
                        }
                        .buttonStyle(.plain)
                        .padding(22)
                        .padding(.horizontal, 16)
                    }

                    // Shows the Watchlist: started videos and videos added by hand.
                    let watchlist = library.watchlist
                    if !watchlist.isEmpty {
                        videoRow(
                            title: "Continue Watching",
                            subtitle: "Pick up where you left off",
                            videos: watchlist,
                            sectionID: "continue"
                        )
                    }

                    videoRow(
                        title: "Made for Tonight",
                        subtitle: "Kurzgesagt, Veritasium, and more",
                        videos: picks,
                        sectionID: "picks"
                    )

                    editorialCollection
                }
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Home")
            .videoDestination(transition: transition)
            .playbackPresentation(playback)
            .task {
                // The featured video has a Play button right on Home.
                await NativePlayback.prefetch(featured)
            }
        }
    }

    private var featuredPlayLabel: some View {
        PlayButtonContent(
            progress: library.progress(for: featured),
            isPreparing: playback.isPreparing
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.black)
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
        .background(.white, in: Capsule())
    }

    private var featuredHero: some View {
        ZStack(alignment: .bottomLeading) {
            VideoHeroArtwork(video: featured, cornerRadius: 22, stageAspectRatio: 2.0 / 3.0)
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
                Text(featured.title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                HStack(alignment: .center) {
                    // Reserves the Play button's space; the button itself is an
                    // overlay outside the navigation link.
                    featuredPlayLabel
                        .hidden()

                    Spacer()

                    if let duration = featured.duration {
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

    private func videoRow(title: String, subtitle: String, videos: [Video], sectionID: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, 16)

            // A lazy stack sizes the row from the cards it has loaded, which
            // squeezed a card with a longer title. The row always has the
            // height of a card with a two-line title; each card keeps its own
            // height inside it.
            VideoCard.CompactHeightTemplate()
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(videos) { video in
                                VideoLink(video: video, section: sectionID, transition: transition) {
                                    VideoCard(video: video, compact: true)
                                        .frame(width: 272, alignment: .top)
                                }
                                .frame(width: 272)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .contentMargins(.horizontal, 16, for: .scrollContent)
                    // Shelves snap to cards like the App Store and TV app.
                    .scrollTargetBehavior(.viewAligned)
                    // Scroll views clip their content by default, which cut off a
                    // card lifted for its context menu at the edge of the row.
                    .scrollClipDisabled()
                    .scrollIndicators(.hidden)
                }
        }
    }

    private var editorialCollection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Apple Videos Spotlight",
                subtitle: "Beautiful stories, selected by hand"
            )
            .padding(.horizontal, 16)

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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 16)
        }
    }
}
