import SwiftUI

struct LibraryView: View {
    private enum Route: Hashable {
        case saved
        case downloaded
        case history
    }

    @Environment(LibraryStore.self) private var library
    @Environment(DownloadManager.self) private var downloads
    @Namespace private var transition

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(value: Route.saved) {
                        LibraryRow(title: "Saved", subtitle: "^[\(library.savedVideos.count) video](inflect: true)", icon: "bookmark.fill", color: .red)
                    }

                    NavigationLink(value: Route.downloaded) {
                        LibraryRow(title: "Downloaded", subtitle: "^[\(downloads.videos.count) video](inflect: true)", icon: "arrow.down.circle.fill", color: .blue)
                    }

                    NavigationLink(value: Route.history) {
                        LibraryRow(title: "History", subtitle: "\(library.recentlyWatched.count) recently watched", icon: "clock.fill", color: .gray)
                    }
                }
            }
            .navigationTitle("Library")
            // All navigation in this stack is value-based. Mixing view-destination
            // links in the List with value-based video links could make the stack
            // rebuild its path and pop a just-pushed video.
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .saved:
                    SavedVideosView(transition: transition)
                case .downloaded:
                    DownloadedVideosView(transition: transition)
                case .history:
                    HistoryView(transition: transition)
                }
            }
            .videoDestination(transition: transition)
        }
    }
}

private struct LibraryRow: View {
    let title: String
    /// Localized so that counts use automatic grammar agreement ("1 video").
    let subtitle: LocalizedStringKey
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct SavedVideosView: View {
    @Environment(LibraryStore.self) private var library
    let transition: Namespace.ID

    var body: some View {
        VideoCollectionView(
            title: "Saved",
            section: "saved",
            emptyTitle: "No Saved Videos",
            emptyDescription: "Use the bookmark button or a video's context menu to save it.",
            videos: library.savedVideos,
            transition: transition
        )
    }
}

private struct DownloadedVideosView: View {
    @Environment(DownloadManager.self) private var downloads
    @State private var isConfirmingRemoveAll = false
    let transition: Namespace.ID

    var body: some View {
        VideoCollectionView(
            title: "Downloaded",
            section: "downloaded",
            emptyTitle: "No Downloads",
            emptyDescription: "Use the download button or a video's context menu to watch it offline.",
            videos: downloads.videos,
            transition: transition
        )
        .toolbar {
            if !downloads.videos.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Remove All") {
                        isConfirmingRemoveAll = true
                    }
                }
            }
        }
        .confirmationDialog("Remove All Downloads", isPresented: $isConfirmingRemoveAll, titleVisibility: .hidden) {
            Button("Remove All Downloads", role: .destructive) {
                withAnimation {
                    downloads.removeAll()
                }
            }
        } message: {
            Text("All downloaded videos will be removed from your iPhone.")
        }
    }
}

private struct HistoryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(DownloadManager.self) private var downloads
    @State private var isConfirmingRemoveAll = false
    let transition: Namespace.ID

    var body: some View {
        VideoCollectionView(
            title: "History",
            section: "history",
            emptyTitle: "No Watch History",
            emptyDescription: "Videos you play will appear here.",
            videos: library.recentlyWatched,
            transition: transition
        )
        .toolbar {
            if !library.recentlyWatched.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Remove All") {
                        isConfirmingRemoveAll = true
                    }
                }
            }
        }
        .confirmationDialog("Remove All from History", isPresented: $isConfirmingRemoveAll, titleVisibility: .hidden) {
            Button("Remove All from History", role: .destructive) {
                withAnimation {
                    library.removeAllFromRecentlyWatched { downloads.isDownloaded($0) }
                }
            }
        } message: {
            Text("Your watch history and the saved positions of these videos will be removed. Downloaded videos stay.")
        }
    }
}

private struct VideoCollectionView: View {
    @Environment(LibraryStore.self) private var library
    let title: String
    let section: String
    let emptyTitle: String
    let emptyDescription: String
    let videos: [Video]
    let transition: Namespace.ID

    var body: some View {
        Group {
            if videos.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "rectangle.stack.badge.plus", description: Text(emptyDescription))
            } else {
                ScrollView {
                    LazyVStack(spacing: 22) {
                        ForEach(videos) { video in
                            VideoLink(video: video, section: section, transition: transition) {
                                VideoCard(video: video)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(title)
        .task {
            // Stored data shows right away; cards update as fresh data arrives.
            await library.refreshMetadata(of: videos)
        }
    }
}
