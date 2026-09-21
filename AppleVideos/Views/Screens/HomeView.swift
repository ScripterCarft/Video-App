import SwiftUI

struct HomeView: View {
    @Namespace private var transition
    @Environment(LibraryStore.self) private var library

    private let featured = Video.curated[0]
    private let picks = Array(Video.curated.dropFirst())

    private struct HomeRoute: Hashable {
        let video: Video
        let transitionID: String
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    NavigationLink(value: HomeRoute(video: featured, transitionID: "featured-\(featured.id)")) {
                        featuredHero
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: "featured-\(featured.id)", in: transition)

                    if !library.recentlyWatched.isEmpty {
                        videoRow(
                            title: "Continue Watching",
                            subtitle: "Pick up where you left off",
                            videos: library.recentlyWatched,
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
            .navigationDestination(for: HomeRoute.self) { route in
                VideoDetailView(video: route.video, transition: transition, transitionID: route.transitionID)
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
            VideoHeroArtwork(video: featured, cornerRadius: 22)
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
                    Label("Play", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 9)
                        .background(.white, in: Capsule())

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

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(videos) { video in
                        let sourceID = "\(sectionID)-\(video.id)"
                        NavigationLink(value: HomeRoute(video: video, transitionID: sourceID)) {
                            VideoCard(video: video, compact: true)
                                .frame(width: 272, alignment: .top)
                        }
                        .buttonStyle(.plain)
                        .matchedTransitionSource(id: sourceID, in: transition)
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollIndicators(.hidden)
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
