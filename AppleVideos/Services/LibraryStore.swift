import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {
    private enum Keys {
        static let saved = "apple-videos.saved"
        static let watchlist = "apple-videos.watchlist"
        static let recent = "apple-videos.recent"
        static let progress = "apple-videos.progress"
        /// Removed playlists, read once to migrate their videos.
        static let legacyPlaylists = "apple-videos.playlists"
        static let legacyPlaylistVideos = "apple-videos.playlist-videos"
    }

    /// A video added to the Watchlist by hand.
    private struct WatchlistEntry: Codable {
        var video: Video
        let addedAt: Date
    }

    private(set) var savedVideos: [Video]
    /// History, shown as "Recently Watched" in menus.
    private(set) var recentlyWatched: [Video]
    private var watchlistEntries: [WatchlistEntry]
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

        let decodedWatchlist = Self.decode(
            [WatchlistEntry].self,
            from: defaults.data(forKey: Keys.watchlist)
        ) ?? []
        var seenWatchlist = Set<String>()
        watchlistEntries = decodedWatchlist.filter { seenWatchlist.insert($0.video.id).inserted }

        let decodedRecent = Self.decode([Video].self, from: defaults.data(forKey: Keys.recent)) ?? []
        recentlyWatched = Array(Self.uniqueVideos(decodedRecent).prefix(Self.historyLimit))

        let decodedProgress = Self.decode(
            [String: PlaybackProgress].self,
            from: defaults.data(forKey: Keys.progress)
        ) ?? [:]
        storedProgress = decodedProgress
        progress = decodedProgress

        migratePlaylists()

        persist(savedVideos, key: Keys.saved)
        persist(watchlistEntries, key: Keys.watchlist)
        persist(recentlyWatched, key: Keys.recent)
    }

    /// The copy to store: a screen may hold older metadata than a details
    /// refresh stored meanwhile, such as the detail screen that started playback.
    private func freshest(_ video: Video) -> Video {
        refreshedThisLaunch[video.id] ?? video
    }

    // MARK: - Saved

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

    // MARK: - History

    private static let historyLimit = 50

    func markWatched(_ video: Video) {
        let video = freshest(video)
        recentlyWatched.removeAll { $0.id == video.id }
        recentlyWatched.insert(video, at: 0)
        recentlyWatched = Array(recentlyWatched.prefix(Self.historyLimit))
        persist(recentlyWatched, key: Keys.recent)
    }

    func isInRecentlyWatched(_ video: Video) -> Bool {
        recentlyWatched.contains { $0.id == video.id }
    }

    /// Removes `video` from History. Its saved position goes too, so it also
    /// leaves the Watchlist unless it was added there by hand.
    func removeFromRecentlyWatched(_ video: Video) {
        forgetProgress(of: video)
        recentlyWatched.removeAll { $0.id == video.id }
        persist(recentlyWatched, key: Keys.recent)
    }

    /// Empties History. Like removing one video, it forgets the saved
    /// positions, so started videos leave the Watchlist unless added by hand.
    func removeAllFromRecentlyWatched() {
        for video in recentlyWatched {
            storedProgress[video.id] = nil
            progress[video.id] = nil
        }
        persist(storedProgress, key: Keys.progress)
        recentlyWatched = []
        persist(recentlyWatched, key: Keys.recent)
    }

    // MARK: - Watchlist

    /// Videos added by hand and videos from History that were started and not
    /// finished, most recent activity first. Finishing a video removes it.
    var watchlist: [Video] {
        var latest: [String: (video: Video, date: Date)] = [:]
        for entry in watchlistEntries {
            latest[entry.video.id] = (entry.video, entry.addedAt)
        }
        for video in recentlyWatched {
            guard let entry = progress(for: video) else { continue }
            let added = latest[video.id]?.date ?? .distantPast
            latest[video.id] = (video, max(entry.updatedAt, added))
        }
        return latest.values.sorted { $0.date > $1.date }.map(\.video)
    }

    func isInWatchlist(_ video: Video) -> Bool {
        watchlistEntries.contains { $0.video.id == video.id }
            || (progress(for: video) != nil && isInRecentlyWatched(video))
    }

    func addToWatchlist(_ video: Video) {
        guard !watchlistEntries.contains(where: { $0.video.id == video.id }) else { return }
        watchlistEntries.append(WatchlistEntry(video: freshest(video), addedAt: .now))
        persist(watchlistEntries, key: Keys.watchlist)
    }

    /// Removes the entry added by hand and forgets the saved position; the
    /// video stays in History.
    func removeFromWatchlist(_ video: Video) {
        forgetProgress(of: video)
        removeWatchlistEntries { $0 == video.id }
    }

    /// Takes `video` off the Watchlist and records it in History as watched.
    func markAsWatched(_ video: Video) {
        removeFromWatchlist(video)
        markWatched(video)
    }

    private func removeWatchlistEntries(where shouldRemove: (String) -> Bool) {
        guard watchlistEntries.contains(where: { shouldRemove($0.video.id) }) else { return }
        watchlistEntries.removeAll { shouldRemove($0.video.id) }
        persist(watchlistEntries, key: Keys.watchlist)
    }

    // MARK: - Refreshing metadata

    /// Refreshes the Watchlist cards visible on Home. Called once at launch.
    func refreshWatchlist() async {
        await refreshMetadata(of: Array(watchlist.prefix(Self.launchRefreshLimit)))
    }

    private static let launchRefreshLimit = 8

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

    /// Replaces every stored copy of `video` (Saved, History, Watchlist) with
    /// fresher metadata, keeping each list's order. Lists without a change are
    /// not rewritten.
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
        if let index = watchlistEntries.firstIndex(where: { $0.video.id == video.id }),
           watchlistEntries[index].video != video {
            watchlistEntries[index].video = video
            persist(watchlistEntries, key: Keys.watchlist)
        }
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

    /// Shows the saved progress in the UI and takes finished videos off the
    /// Watchlist. Called once a player has closed.
    func publishProgress() {
        if progress != storedProgress {
            progress = storedProgress
        }

        let finished = finishedSincePublish
        finishedSincePublish = []
        removeWatchlistEntries { finished.contains($0) }
    }

    private static let maximumProgressEntries = 200

    private func forgetProgress(of video: Video) {
        guard storedProgress.removeValue(forKey: video.id) != nil else { return }
        progress[video.id] = nil
        persist(storedProgress, key: Keys.progress)
    }

    // MARK: - Storage

    /// Playlists were removed. Watch Later becomes the Watchlist; videos from
    /// other playlists move to Saved so nothing is lost.
    private func migratePlaylists() {
        struct LegacyPlaylist: Decodable {
            let id: UUID
            let name: String
            let videoIDs: [String]
        }
        let watchLaterID = UUID(uuidString: "5A1D3C2E-7F4B-4E8A-9C61-0B2D4F6A8E10")

        guard let playlists = Self.decode(
            [LegacyPlaylist].self,
            from: defaults.data(forKey: Keys.legacyPlaylists)
        ) else { return }
        let stored = Self.decode(
            [String: Video].self,
            from: defaults.data(forKey: Keys.legacyPlaylistVideos)
        ) ?? [:]

        for playlist in playlists {
            let videos = playlist.videoIDs.compactMap { id in
                stored[id] ?? savedVideos.first { $0.id == id }
            }
            if playlist.id == watchLaterID || playlist.name == "Watch Later" {
                // Keep the playlist's order, first video newest.
                for (offset, video) in videos.enumerated()
                where !watchlistEntries.contains(where: { $0.video.id == video.id }) {
                    watchlistEntries.append(
                        WatchlistEntry(video: video, addedAt: .now.addingTimeInterval(-Double(offset)))
                    )
                }
            } else {
                for video in videos where !isSaved(video) {
                    savedVideos.append(video)
                }
            }
        }

        defaults.removeObject(forKey: Keys.legacyPlaylists)
        defaults.removeObject(forKey: Keys.legacyPlaylistVideos)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func uniqueVideos(_ videos: [Video]) -> [Video] {
        var seen = Set<String>()
        return videos.filter { seen.insert($0.id).inserted }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
