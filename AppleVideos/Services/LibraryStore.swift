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
    /// The freshest copy of every video refreshed since launch.
    @ObservationIgnored private var refreshedThisLaunch: [String: Video] = [:]
    @ObservationIgnored private var refreshingIDs: Set<String> = []
    /// Videos played to the end in the open player; applied on close.
    @ObservationIgnored private var finishedSincePublish: Set<String> = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let decodedSaved = Self.decode([Video].self, from: defaults.data(forKey: Keys.saved)) ?? []
        savedVideos = Self.uniqueVideos(decodedSaved)

        let decodedPlaylists = Self.decode(
            [VideoPlaylist].self,
            from: defaults.data(forKey: Keys.playlists)
        ) ?? [
            VideoPlaylist.watchLater,
            VideoPlaylist(name: "Favorites")
        ]
        playlists = Self.withWatchLater(Self.uniquePlaylists(decodedPlaylists))
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
            savedVideos.insert(freshest(video), at: 0)
        }
        persist(savedVideos, key: Keys.saved)
    }

    /// The copy to store: a screen may hold older metadata than a details
    /// refresh stored meanwhile, such as the detail screen that started playback.
    private func freshest(_ video: Video) -> Video {
        refreshedThisLaunch[video.id] ?? video
    }

    func markWatched(_ video: Video) {
        let video = freshest(video)
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
        await refreshMetadata(of: continueWatching)
    }

    /// Loads current metadata for stored videos, such as when a library list
    /// is opened. Each video is requested at most once per launch; the stored
    /// data stays visible and is replaced as each answer arrives, only where
    /// it differs. A failed or cancelled request is retried the next time.
    func refreshMetadata(of videos: [Video]) async {
        let pending = videos.filter {
            $0.source == .youtube && refreshedThisLaunch[$0.id] == nil && !refreshingIDs.contains($0.id)
        }
        guard !pending.isEmpty else { return }
        let ids = pending.map(\.id)
        refreshingIDs.formUnion(ids)
        defer { refreshingIDs.subtract(ids) }

        await withTaskGroup(of: Video?.self) { group in
            // In list order, so the cards on screen come first.
            for (index, video) in pending.enumerated() {
                if index >= Self.concurrentRefreshes, let result = await group.next(), let refreshed = result {
                    updateMetadata(of: refreshed)
                }
                group.addTask {
                    try? await YouTubeService.shared.refreshedVideo(video)
                }
            }
            for await result in group {
                if let refreshed = result {
                    updateMetadata(of: refreshed)
                }
            }
        }
    }

    /// Enough parallel requests to fill the visible cards quickly without
    /// sending fifty at once.
    private static let concurrentRefreshes = 4

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
        if entry.fraction >= PlaybackProgress.finishedFraction {
            finishedSincePublish.insert(videoID)
        }
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

    /// Shows the saved progress in the UI and removes finished videos from
    /// Watch Later. Called once a player has closed.
    func publishProgress() {
        if progress != storedProgress {
            progress = storedProgress
        }

        let finished = finishedSincePublish
        finishedSincePublish = []
        if let index = playlists.firstIndex(where: \.isWatchLater),
           playlists[index].videoIDs.contains(where: { finished.contains($0) }) {
            playlists[index].videoIDs.removeAll { finished.contains($0) }
            persist(playlists, key: Keys.playlists)
            dropUnreferencedPlaylistVideos()
        }
    }

    private static let maximumProgressEntries = 200

    /// Forgets the saved position, which removes the video from Continue
    /// Watching; it stays in History.
    func removeFromContinueWatching(_ video: Video) {
        guard storedProgress.removeValue(forKey: video.id) != nil else { return }
        progress[video.id] = nil
        persist(storedProgress, key: Keys.progress)
    }

    /// Replaces every stored copy of `video` (Saved, playlists, Continue
    /// Watching) with fresher metadata, keeping each list's order. Lists
    /// without a change are not rewritten.
    func updateMetadata(of video: Video) {
        refreshedThisLaunch[video.id] = video

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

    /// Deletes user playlists; Watch Later is a system list and stays.
    func deletePlaylists(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where playlists.indices.contains(index) && !playlists[index].isWatchLater {
            playlists.remove(at: index)
        }
        persist(playlists, key: Keys.playlists)
        dropUnreferencedPlaylistVideos()
    }

    /// Drops stored videos that no playlist refers to.
    private func dropUnreferencedPlaylistVideos() {
        let referencedIDs = Set(playlists.flatMap(\.videoIDs))
        playlistVideos = playlistVideos.filter { referencedIDs.contains($0.key) }
        persist(playlistVideos, key: Keys.playlistVideos)
    }

    func add(_ video: Video, to playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlistVideos[video.id] = freshest(video)
        persist(playlistVideos, key: Keys.playlistVideos)
        if !playlists[index].videoIDs.contains(video.id) {
            playlists[index].videoIDs.append(video.id)
            persist(playlists, key: Keys.playlists)
        }
    }

    func remove(_ video: Video, from playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }),
              playlists[index].videoIDs.contains(video.id)
        else { return }
        playlists[index].videoIDs.removeAll { $0 == video.id }
        persist(playlists, key: Keys.playlists)
        dropUnreferencedPlaylistVideos()
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

    /// Ensures the Watch Later system list exists. The former default list
    /// named "Watch Later" becomes it, keeping its videos.
    private static func withWatchLater(_ playlists: [VideoPlaylist]) -> [VideoPlaylist] {
        guard !playlists.contains(where: \.isWatchLater) else { return playlists }
        var playlists = playlists
        if let index = playlists.firstIndex(where: { $0.name == VideoPlaylist.watchLater.name }) {
            var watchLater = VideoPlaylist.watchLater
            watchLater.videoIDs = playlists[index].videoIDs
            playlists[index] = watchLater
        } else {
            playlists.insert(.watchLater, at: 0)
        }
        return playlists
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

