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
        static let progress = "apple-videos.progress"
    }

    private(set) var savedVideos: [Video]
    private(set) var playlists: [VideoPlaylist]
    private var playlistVideos: [String: Video]
    private(set) var recentlyWatched: [Video]
    /// Watch progress as last shown in the UI. Updated when a player closes, so
    /// nothing re-renders while AVKit is on screen.
    private(set) var progress: [String: PlaybackProgress]
    /// Watch progress as last saved, written continuously during playback.
    @ObservationIgnored private var storedProgress: [String: PlaybackProgress]
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
        recentlyWatched = Array(Self.uniqueVideos(decodedRecent).prefix(Self.historyLimit))

        let decodedProgress = Self.decode(
            [String: PlaybackProgress].self,
            from: defaults.data(forKey: Keys.progress)
        ) ?? [:]
        storedProgress = decodedProgress
        progress = decodedProgress

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
        recentlyWatched = Array(recentlyWatched.prefix(Self.historyLimit))
        persist(recentlyWatched, key: Keys.recent)
    }

    /// Videos from History that were started and not finished, newest first.
    /// Finishing a video clears its progress, which removes it from here while
    /// it stays in History.
    var continueWatching: [Video] {
        Array(recentlyWatched.lazy.filter { self.progress(for: $0) != nil }.prefix(Self.continueWatchingLimit))
    }

    private static let historyLimit = 50
    private static let continueWatchingLimit = 8

    /// Refreshes Continue Watching metadata. Called once at launch.
    func refreshContinueWatching() async {
        let current = continueWatching
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

    // MARK: - Watch progress

    /// Where to resume `video`, if it was started and not finished.
    func resumePosition(for video: Video) -> Double? {
        guard let entry = storedProgress[video.id], entry.isResumable else { return nil }
        return entry.position
    }

    /// The progress to show for `video`, if it can be resumed.
    func progress(for video: Video) -> PlaybackProgress? {
        guard let entry = progress[video.id], entry.isResumable else { return nil }
        return entry
    }

    /// Saves the playback position. Called repeatedly during playback, so it
    /// writes to storage right away (surviving a crash or a terminated app)
    /// but does not update the UI; see `publishProgress()`. Positions near
    /// the start or the end remove the entry.
    func recordProgress(for videoID: String, position: Double, duration: Double) {
        guard position.isFinite, duration.isFinite, duration > 0 else { return }

        let entry = PlaybackProgress(position: position, duration: duration, updatedAt: .now)
        if entry.isResumable {
            storedProgress[videoID] = entry
        } else if storedProgress.removeValue(forKey: videoID) == nil {
            return
        }

        if storedProgress.count > Self.maximumProgressEntries {
            let kept = storedProgress
                .sorted { $0.value.updatedAt > $1.value.updatedAt }
                .prefix(Self.maximumProgressEntries)
            storedProgress = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
        persist(storedProgress, key: Keys.progress)
    }

    /// Shows the saved progress in the UI. Called once a player has closed.
    func publishProgress() {
        if progress != storedProgress {
            progress = storedProgress
        }
    }

    private static let maximumProgressEntries = 200

    /// Replaces every stored copy of `video` (Saved, playlists, Continue
    /// Watching) with fresher metadata, keeping each list's order. Lists
    /// without a change are not rewritten.
    func updateMetadata(of video: Video) {
        func replaced(in videos: [Video]) -> [Video]? {
            guard videos.contains(where: { $0.id == video.id && $0 != video }) else { return nil }
            return videos.map { $0.id == video.id ? video : $0 }
        }

        if let updated = replaced(in: savedVideos) {
            savedVideos = updated
            persist(savedVideos, key: Keys.saved)
        }
        if let updated = replaced(in: recentlyWatched) {
            recentlyWatched = updated
            persist(recentlyWatched, key: Keys.recent)
        }
        if let stored = playlistVideos[video.id], stored != video {
            playlistVideos[video.id] = video
            persist(playlistVideos, key: Keys.playlistVideos)
        }
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

