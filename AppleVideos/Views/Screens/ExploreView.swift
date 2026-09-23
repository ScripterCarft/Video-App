import SwiftUI

struct ExploreView: View {
    @Namespace private var transition

    private struct Topic: Identifiable {
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
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Browse Topics", subtitle: "Find something worth watching")

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(topics) { topic in
                                NavigationLink {
                                    SearchResultsView(
                                        query: topic.title,
                                        section: "topic-\(topic.title)",
                                        transition: transition
                                    )
                                    .navigationTitle(topic.title)
                                    .navigationBarTitleDisplayMode(.large)
                                } label: {
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
            .videoDestination(transition: transition)
        }
    }
}
