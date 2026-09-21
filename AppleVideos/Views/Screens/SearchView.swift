import SwiftUI

struct SearchView: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView {
                        Label("Search YouTube", systemImage: "play.rectangle.on.rectangle")
                    } description: {
                        Text("Find videos without leaving Apple Videos.")
                    }
                } else {
                    SearchResultsView(query: query)
                        .id(query)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Videos, topics, or creators")
        }
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
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
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

