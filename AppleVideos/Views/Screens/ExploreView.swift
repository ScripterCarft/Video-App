import SwiftUI

struct ExploreView: View {
    @Namespace private var transition

    private let topics = [
        ("Technology", "cpu", Color.blue),
        ("Film", "film.stack", Color.indigo),
        ("Science", "atom", Color.teal),
        ("Music", "music.note", Color.pink),
        ("Gaming", "gamecontroller", Color.purple),
        ("Learning", "graduationcap", Color.orange)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Browse Topics", subtitle: "Find something worth watching")

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(topics, id: \.0) { topic in
                                NavigationLink {
                                    TopicView(title: topic.0, query: topic.0)
                                } label: {
                                    Label(topic.0, systemImage: topic.1)
                                        .font(.headline)
                                        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                                        .padding(.horizontal, 16)
                                        .foregroundStyle(.white)
                                        .background(topic.2.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                            NavigationLink(value: video) {
                                VideoCard(video: video)
                            }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: video.id, in: transition)
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Explore")
            .navigationDestination(for: Video.self) { video in
                VideoDetailView(video: video, transition: transition)
            }
        }
    }
}

private struct TopicView: View {
    let title: String
    let query: String

    var body: some View {
        SearchResultsView(query: query)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
    }
}

