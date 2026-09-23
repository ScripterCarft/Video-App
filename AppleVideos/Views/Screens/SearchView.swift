import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var submittedQuery = ""
    @Namespace private var transition

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
                    SearchResultsView(query: submittedQuery, section: "search", transition: transition)
                }
            }
            .navigationTitle("Search")
            .videoDestination(transition: transition)
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

/// Search results for a query. The enclosing navigation stack must register
/// `videoDestination(transition:)` with the same namespace.
struct SearchResultsView: View {
    let query: String
    let section: String
    let transition: Namespace.ID

    @State private var results: [Video] = []
    @State private var loadedQuery: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

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
                        Task { await load(bypassingCache: true) }
                    }
                    .buttonStyle(.borderedProminent)
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .padding(.top, 60)
                } else {
                    ForEach(results) { video in
                        VideoLink(video: video, section: section, transition: transition) {
                            VideoCard(video: video)
                        }
                    }
                }
            }
            .padding()
        }
        .task(id: query) {
            // Returning from a detail screen re-runs this task; keep the loaded
            // results and scroll position instead of searching again.
            guard loadedQuery != query else { return }
            results = []
            await load()
        }
        .refreshable {
            await load(bypassingCache: true)
        }
    }

    @MainActor
    private func load(bypassingCache: Bool = false) async {
        isLoading = true
        errorMessage = nil
        do {
            let found = try await YouTubeService.shared.search(query, bypassingCache: bypassingCache)
            guard !Task.isCancelled else { return }
            results = found
            loadedQuery = query
        } catch {
            // A newer query cancelled this request. URLSession reports that as
            // URLError.cancelled rather than CancellationError, so check the task.
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
