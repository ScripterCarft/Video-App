import SwiftUI

struct HomeView: View {
    @Namespace private var transition
    @Environment(LibraryStore.self) private var library

    private let featured = Video.curated[0]
    private let picks = Array(Video.curated.dropFirst())

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    NavigationLink(value: featured) {
                        featuredHero
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: featured.id, in: transition)

                    if !library.recentlyWatched.isEmpty {
                        videoRow(
                            title: "Continue Watching",
                            subtitle: "Pick up where you left off",
                            videos: library.recentlyWatched
                        )
                    }

                    videoRow(
                        title: "Made for Tonight",
                        subtitle: "A few hand-picked videos to get started",
                        videos: picks
                    )

                    editorialCollection
                }
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Home")
            .navigationDestination(for: Video.self) { video in
                VideoDetailView(video: video, transition: transition)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Profile")
                }
            }
        }
    }

    private var featuredHero: some View {
        ZStack(alignment: .bottomLeading) {
            VideoArtwork(video: featured, cornerRadius: 26)
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
                Label("Play", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .background(.white, in: Capsule())
            }
            .padding(22)
        }
        .padding(.horizontal)
    }

    private func videoRow(title: String, subtitle: String, videos: [Video]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: title, subtitle: subtitle)
                .padding(.horizontal)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(videos) { video in
                        NavigationLink(value: video) {
                            VideoCard(video: video, compact: true)
                                .frame(width: 260)
                        }
                        .buttonStyle(.plain)
                        .matchedTransitionSource(id: video.id, in: transition)
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var editorialCollection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Apple Videos Spotlight",
                subtitle: "Beautiful stories, selected by hand"
            )
            .padding(.horizontal)

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
            .padding(.horizontal)
        }
    }
}

