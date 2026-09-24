import SwiftUI

struct LibraryView: View {
    private enum Route: Hashable {
        case saved
        case history
        case playlist(UUID)
    }

    @Environment(LibraryStore.self) private var library
    @State private var isCreatingPlaylist = false
    @State private var playlistName = ""
    @Namespace private var transition

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(value: Route.saved) {
                        LibraryRow(title: "Saved", subtitle: "^[\(library.savedVideos.count) video](inflect: true)", icon: "bookmark.fill", color: .red)
                    }

                    NavigationLink(value: Route.history) {
                        LibraryRow(title: "History", subtitle: "\(library.recentlyWatched.count) recently watched", icon: "clock.fill", color: .gray)
                    }
                }

                Section("Playlists") {
                    ForEach(library.playlists) { playlist in
                        NavigationLink(value: Route.playlist(playlist.id)) {
                            LibraryRow(
                                title: playlist.name,
                                subtitle: "^[\(playlist.videoIDs.count) video](inflect: true)",
                                icon: "text.badge.checkmark",
                                color: .purple
                            )
                        }
                    }
                    .onDelete { offsets in
                        library.deletePlaylists(at: offsets)
                    }

                    Button {
                        isCreatingPlaylist = true
                    } label: {
                        Label("New Playlist", systemImage: "plus")
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
                case .history:
                    HistoryView(transition: transition)
                case let .playlist(id):
                    PlaylistView(playlistID: id, transition: transition)
                }
            }
            .videoDestination(transition: transition)
            .alert("New Playlist", isPresented: $isCreatingPlaylist) {
                TextField("Playlist name", text: $playlistName)
                Button("Cancel", role: .cancel) { playlistName = "" }
                Button("Create") {
                    library.createPlaylist(named: playlistName)
                    playlistName = ""
                }
            } message: {
                Text("Create a collection for videos you want to keep together.")
            }
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

private struct HistoryView: View {
    @Environment(LibraryStore.self) private var library
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
    }
}

private struct PlaylistView: View {
    @Environment(LibraryStore.self) private var library
    let playlistID: UUID
    let transition: Namespace.ID

    var body: some View {
        // Look the playlist up on every update so the list stays current.
        let playlist = library.playlists.first { $0.id == playlistID }
        VideoCollectionView(
            title: playlist?.name ?? "Playlist",
            section: "playlist-\(playlistID.uuidString)",
            emptyTitle: "Playlist is Empty",
            emptyDescription: "Add a video from its context menu.",
            videos: playlist.map { library.videos(in: $0) } ?? [],
            transition: transition
        )
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
