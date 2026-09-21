import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var submittedQuery = ""

    private let suggestions = [
        "Kurzgesagt",
        "Veritasium",
        "Physics",
        "Space documentaries",
        "Technology"
    ]

    var body: some View {
        NavigationStack {
            Group {
                if submittedQuery.isEmpty {
                    ContentUnavailableView {
                        Label("Search YouTube", systemImage: "play.rectangle.on.rectangle")
                    } description: {
                        Text("Search for videos, topics, or creators.")
                    }
                } else {
                    SearchResultsView(query: submittedQuery)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Videos, topics, or creators")
            .searchSuggestions {
                ForEach(suggestions, id: \.self) { suggestion in
                    Label(suggestion, systemImage: "magnifyingglass")
                        .searchCompletion(suggestion)
                }
            }
            .onSubmit(of: .search) {
                submitSearch()
            }
            .onChange(of: query) { _, newValue in
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    submittedQuery = ""
                }
            }
        }
    }

    private func submitSearch() {
        submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SearchResultsView: View {
    let query: String

    @State private var results: [Video] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Namespace private var transition

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 22) {
                if isLoading && results.isEmpty {
                    ProgressView("Searching YouTube…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if let errorMessage, results.isEmpty {
                    ContentUnavailableView(
                        "Search Unavailable",
                        systemImage: "wifi.exclamationmark",
                        description: Text(errorMessage)
                    )
                    Button("Try Again") {
                        Task { await load() }
                    }
                    .buttonStyle(.borderedProminent)
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .padding(.top, 60)
                } else {
                    ForEach(results) { video in
                        NavigationLink(value: video) {
                            VideoCard(video: video)
                        }
                        .buttonStyle(.plain)
                        .matchedTransitionSource(id: video.id, in: transition)
                    }
                }
            }
            .padding()
        }
        .navigationDestination(for: Video.self) { video in
            VideoDetailView(video: video, transition: transition)
        }
        .task(id: query) {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            results = try await YouTubeService.shared.search(query)
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
