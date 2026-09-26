import SwiftUI

struct ExploreView: View {
    @Namespace private var transition

    /// Navigation value for a topic's results; only the title, so the path
    /// can be restored after a relaunch.
    private struct TopicRoute: Hashable, Codable {
        let title: String
    }

    private struct Topic: Identifiable, Hashable {
        let title: String
        let systemImage: String
        let color: Color

        var id: String { title }
    }

    private let topics = [
        Topic(title: "Technology", systemImage: "cpu", color: .blue),
        Topic(title: "Film", systemImage: "film.stack", color: .indigo),
        Topic(title: "Science", systemImage: "atom", color: .teal),
        Topic(title: "Music", systemImage: "music.note", color: .pink),
        Topic(title: "Gaming", systemImage: "gamecontroller", color: .purple),
        Topic(title: "Learning", systemImage: "graduationcap", color: .orange)
    ]

    var body: some View {
        RestorableNavigationStack(id: "explore.path") { _ in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Browse Topics", subtitle: "Find something worth watching")

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(topics) { topic in
                                NavigationLink(value: TopicRoute(title: topic.title)) {
                                    Label(topic.title, systemImage: topic.systemImage)
                                        .font(.headline)
                                        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                                        .padding(.horizontal, 16)
                                        .foregroundStyle(.white)
                                        .background(topic.color.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Trending Now", subtitle: "A first editorial selection")
                            .padding(.horizontal)

                        ForEach(Video.curated) { video in
                            VideoLink(video: video, section: "trending", transition: transition) {
                                VideoCard(video: video)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Explore")
            // Value-based like the video links; mixing view-destination links
            // with value-based ones can pop a video right after it was pushed.
            .navigationDestination(for: TopicRoute.self) { topic in
                SearchResultsView(
                    query: topic.title,
                    section: "topic-\(topic.title)",
                    transition: transition
                )
                .navigationTitle(topic.title)
                .navigationBarTitleDisplayMode(.large)
            }
            .videoDestination(transition: transition)
        }
    }
}
