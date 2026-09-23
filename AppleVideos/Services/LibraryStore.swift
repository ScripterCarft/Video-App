import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {
    private enum Keys {
        static let saved = "apple-videos.saved"
        static let playlists = "apple-videos.playlists"
        static let playlistVideos = "apple-videos.playlist-videos"
        static let recent = "apple-videos.recent"
    }

    private(set) var savedVideos: [Video]
    private(set) var playlists: [VideoPlaylist]
    private var playlistVideos: [String: Video]
    private(set) var recentlyWatched: [Video]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let decodedSaved = Self.decode([Video].self, from: defaults.data(forKey: Keys.saved)) ?? []
        savedVideos = Self.uniqueVideos(decodedSaved)

        let decodedPlaylists = Self.decode(
            [VideoPlaylist].self,
            from: defaults.data(forKey: Keys.playlists)
        ) ?? [
            VideoPlaylist(name: "Watch Later"),
            VideoPlaylist(name: "Favorites")
        ]
        playlists = Self.uniquePlaylists(decodedPlaylists)
        playlistVideos = Self.decode(
            [String: Video].self,
            from: defaults.data(forKey: Keys.playlistVideos)
        ) ?? [:]

        let decodedRecent = Self.decode([Video].self, from: defaults.data(forKey: Keys.recent)) ?? []
        recentlyWatched = Array(Self.uniqueVideos(decodedRecent).prefix(8))

        // Migrate existing playlists while their videos are still in Saved.
        for video in savedVideos where playlists.contains(where: { $0.videoIDs.contains(video.id) }) {
            playlistVideos[video.id] = video
        }

        persist(savedVideos, key: Keys.saved)
        persist(playlists, key: Keys.playlists)
        persist(playlistVideos, key: Keys.playlistVideos)
        persist(recentlyWatched, key: Keys.recent)
    }

    func isSaved(_ video: Video) -> Bool {
        savedVideos.contains { $0.id == video.id }
    }

    func toggleSaved(_ video: Video) {
        if let index = savedVideos.firstIndex(where: { $0.id == video.id }) {
            savedVideos.remove(at: index)
        } else {
            savedVideos.insert(video, at: 0)
        }
        persist(savedVideos, key: Keys.saved)
    }

    func markWatched(_ video: Video) {
        recentlyWatched.removeAll { $0.id == video.id }
        recentlyWatched.insert(video, at: 0)
        recentlyWatched = Array(recentlyWatched.prefix(8))
        persist(recentlyWatched, key: Keys.recent)
    }

    func refreshRecentlyWatched() async {
        let current = Array(recentlyWatched.prefix(8))
        guard !current.isEmpty else { return }

        let updates = await withTaskGroup(
            of: (String, Video?).self,
            returning: [String: Video].self
        ) { group in
            for video in current {
                group.addTask {
                    let refreshed = try? await YouTubeService.shared.refreshedVideo(video)
                    return (video.id, refreshed)
                }
            }

            var values: [String: Video] = [:]
            for await (id, video) in group {
                if let video {
                    values[id] = video
                }
            }
            return values
        }

        // Preserve videos watched while the refresh requests were running.
        recentlyWatched = recentlyWatched.map { updates[$0.id] ?? $0 }
        persist(recentlyWatched, key: Keys.recent)
    }

    func createPlaylist(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        playlists.append(VideoPlaylist(name: trimmed))
        persist(playlists, key: Keys.playlists)
    }

    func deletePlaylists(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where playlists.indices.contains(index) {
            playlists.remove(at: index)
        }
        persist(playlists, key: Keys.playlists)

        // Drop stored videos that no remaining playlist refers to.
        let referencedIDs = Set(playlists.flatMap(\.videoIDs))
        playlistVideos = playlistVideos.filter { referencedIDs.contains($0.key) }
        persist(playlistVideos, key: Keys.playlistVideos)
    }

    func add(_ video: Video, to playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlistVideos[video.id] = video
        persist(playlistVideos, key: Keys.playlistVideos)
        if !playlists[index].videoIDs.contains(video.id) {
            playlists[index].videoIDs.append(video.id)
            persist(playlists, key: Keys.playlists)
        }
        if !isSaved(video) {
            savedVideos.insert(video, at: 0)
            persist(savedVideos, key: Keys.saved)
        }
    }

    func videos(in playlist: VideoPlaylist) -> [Video] {
        playlist.videoIDs.compactMap { id in
            savedVideos.first { $0.id == id } ?? playlistVideos[id]
        }
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func uniqueVideos(_ videos: [Video]) -> [Video] {
        var seen = Set<String>()
        return videos.filter { seen.insert($0.id).inserted }
    }

    private static func uniquePlaylists(_ playlists: [VideoPlaylist]) -> [VideoPlaylist] {
        var seenPlaylists = Set<UUID>()

        return playlists.compactMap { playlist in
            guard seenPlaylists.insert(playlist.id).inserted else { return nil }

            var normalized = playlist
            var seenVideos = Set<String>()
            normalized.videoIDs = playlist.videoIDs.filter {
                seenVideos.insert($0).inserted
            }
            return normalized
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

