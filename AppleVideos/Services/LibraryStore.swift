import Foundation
import Observation
import SwiftData

/// Saved, History, the Watchlist and watch progress, stored in SwiftData with
/// one `StoredVideo` per video and one `WatchProgress` per started video.
/// The lists come from SwiftData's `ResultsObserver`s, which update by
/// themselves after each save, including the downloads' saves; screens that
/// read them update through observation. Library screens query the store
/// directly.
///
/// Watch progress is written to the store during playback (it survives a
/// crash) but `progress`, which the UI reads, changes only when a player has
/// closed, so nothing re-renders while AVKit is on screen. Because progress is
/// a separate model, saving a changed position leaves the lists alone.
@MainActor
@Observable
final class LibraryStore {
    private let saved = LibraryDatabase.observe(
        #Predicate { $0.savedAt != nil },
        sortedBy: SortDescriptor(\.savedAt, order: .reverse)
    )
    private let watched = LibraryDatabase.observe(
        #Predicate { $0.watchedAt != nil },
        sortedBy: SortDescriptor(\.watchedAt, order: .reverse)
    )
    private let addedToWatchlist = LibraryDatabase.observe(
        #Predicate { $0.watchlistAddedAt != nil },
        sortedBy: SortDescriptor(\.watchlistAddedAt, order: .reverse)
    )
    /// Watch progress as last shown in the UI.
    private(set) var progress: [String: PlaybackProgress] = [:]

    /// The freshest copy of every video refreshed since launch.
    @ObservationIgnored private var refreshedThisLaunch: [String: Video] = [:]
    @ObservationIgnored private var refreshingIDs: Set<String> = []
    /// Videos played to the end in the open player; applied on close.
    @ObservationIgnored private var finishedSincePublish: Set<String> = []

    private static let historyLimit = 50
    private static let maximumProgressEntries = 200

    init() {
        progress = Self.storedProgress()
    }

    var savedVideos: [Video] {
        saved?.results.map(\.video) ?? []
    }

    /// History, shown as "Recently Watched" in menus.
    var recentlyWatched: [Video] {
        watched?.results.map(\.video) ?? []
    }

    /// The copy to store: a screen may hold older metadata than a details
    /// refresh stored meanwhile, such as the detail screen that started playback.
    private func freshest(_ video: Video) -> Video {
        refreshedThisLaunch[video.id] ?? video
    }

    // MARK: - Saved

    func isSaved(_ video: Video) -> Bool {
        saved?.results.contains { $0.id == video.id } ?? false
    }

    func toggleSaved(_ video: Video) {
        let record = LibraryDatabase.record(for: freshest(video))
        record.savedAt = record.savedAt == nil ? .now : nil
        commit(record)
    }

    // MARK: - History

    func markWatched(_ video: Video) {
        let record = LibraryDatabase.record(for: freshest(video))
        record.update(from: freshest(video))
        record.watchedAt = .now
        trimHistory()
        commit(record)
    }

    func isInRecentlyWatched(_ video: Video) -> Bool {
        watched?.results.contains { $0.id == video.id } ?? false
    }

    /// Removes `video` from History. Its saved position goes too, so it also
    /// leaves the Watchlist unless it was added there by hand.
    func removeFromRecentlyWatched(_ video: Video) {
        guard let record = LibraryDatabase.record(id: video.id) else { return }
        record.watchedAt = nil
        LibraryDatabase.setProgress(nil, for: record.id)
        progress[video.id] = nil
        commit(record)
    }

    /// Empties History except the videos `keeping` returns true for, such as
    /// downloads. Like removing one video, it forgets the removed videos'
    /// saved positions, so they leave the Watchlist unless added by hand.
    func removeAllFromRecentlyWatched(keeping: (Video) -> Bool) {
        for record in LibraryDatabase.allRecords() where record.watchedAt != nil && !keeping(record.video) {
            record.watchedAt = nil
            LibraryDatabase.setProgress(nil, for: record.id)
            progress[record.id] = nil
            LibraryDatabase.deleteIfUnused(record)
        }
        LibraryDatabase.save()
    }

    /// Keeps the most recent videos in History; older ones leave it.
    private func trimHistory() {
        let watched = LibraryDatabase.allRecords()
            .filter { $0.watchedAt != nil }
            .sorted { $0.watchedAt! > $1.watchedAt! }
        for record in watched.dropFirst(Self.historyLimit) {
            record.watchedAt = nil
            LibraryDatabase.deleteIfUnused(record)
        }
    }

    // MARK: - Watchlist

    /// Videos added by hand and videos from History that were started and not
    /// finished, most recent activity first. Finishing a video removes it.
    var watchlist: [Video] {
        var latest: [String: (video: Video, date: Date)] = [:]
        if let records = addedToWatchlist?.results {
            for record in records {
                if let addedAt = record.watchlistAddedAt {
                    latest[record.id] = (record.video, addedAt)
                }
            }
        }
        for video in recentlyWatched {
            guard let entry = progress(for: video) else { continue }
            let added = latest[video.id]?.date ?? .distantPast
            latest[video.id] = (video, max(entry.updatedAt, added))
        }
        return latest.values.sorted { $0.date > $1.date }.map(\.video)
    }

    func isInWatchlist(_ video: Video) -> Bool {
        (addedToWatchlist?.results.contains { $0.id == video.id } ?? false)
            || (progress(for: video) != nil && isInRecentlyWatched(video))
    }

    func addToWatchlist(_ video: Video) {
        let record = LibraryDatabase.record(for: freshest(video))
        guard record.watchlistAddedAt == nil else { return }
        record.watchlistAddedAt = .now
        commit(record)
    }

    /// Removes the entry added by hand and forgets the saved position; the
    /// video stays in History.
    func removeFromWatchlist(_ video: Video) {
        guard let record = LibraryDatabase.record(id: video.id) else { return }
        record.watchlistAddedAt = nil
        LibraryDatabase.setProgress(nil, for: record.id)
        progress[video.id] = nil
        commit(record)
    }

    /// Takes `video` off the Watchlist and records it in History as watched.
    func markAsWatched(_ video: Video) {
        removeFromWatchlist(video)
        markWatched(video)
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

    /// Remembers fresher metadata without storing it yet, so a video recorded
    /// meanwhile (for example when its player closes) is stored with it.
    func rememberFresh(_ video: Video) {
        refreshedThisLaunch[video.id] = video
    }

    /// Stores fresher metadata for `video`. It is kept once, so every list
    /// showing it updates; nothing is written when nothing changed or the
    /// video is not stored.
    func updateMetadata(of video: Video) {
        refreshedThisLaunch[video.id] = video
        guard let record = LibraryDatabase.record(id: video.id), record.update(from: video) else { return }
        commit(record)
    }

    // MARK: - Watch progress

    /// Where to resume `video`, if it was started and not finished.
    func resumePosition(for video: Video) -> Double? {
        guard let entry = LibraryDatabase.progress(id: video.id)?.progress, entry.isResumable else { return nil }
        return entry.position
    }

    /// The progress to show for `video`, if it can be resumed.
    func progress(for video: Video) -> PlaybackProgress? {
        guard let entry = progress[video.id], entry.isResumable else { return nil }
        return entry
    }

    /// Saves the playback position. Called repeatedly during playback, so it
    /// writes to the store right away (surviving a crash or a terminated app)
    /// but does not update the UI; see `publishProgress()`. Positions near
    /// the start or the end remove the entry.
    func recordProgress(for video: Video, position: Double, duration: Double) {
        guard position.isFinite, duration.isFinite, duration > 0 else { return }

        let entry = PlaybackProgress(position: position, duration: duration, updatedAt: .now)
        if entry.fraction >= PlaybackProgress.finishedFraction {
            finishedSincePublish.insert(video.id)
        }
        if entry.isResumable {
            LibraryDatabase.setProgress(entry, for: video.id)
            trimProgress()
        } else if LibraryDatabase.progress(id: video.id) != nil {
            LibraryDatabase.setProgress(nil, for: video.id)
        } else {
            return
        }
        LibraryDatabase.save()
    }

    /// Shows the saved progress in the UI and takes finished videos off the
    /// Watchlist. Called once a player has closed.
    func publishProgress() {
        let stored = Self.storedProgress()
        if progress != stored {
            progress = stored
        }

        let finished = finishedSincePublish
        finishedSincePublish = []
        for id in finished {
            guard let record = LibraryDatabase.record(id: id), record.watchlistAddedAt != nil else { continue }
            record.watchlistAddedAt = nil
            LibraryDatabase.deleteIfUnused(record)
        }
        LibraryDatabase.save()
    }

    /// Keeps the most recent saved positions.
    private func trimProgress() {
        let entries = LibraryDatabase.allProgress().sorted { $0.updatedAt > $1.updatedAt }
        for entry in entries.dropFirst(Self.maximumProgressEntries) {
            LibraryDatabase.context.delete(entry)
        }
    }

    private static func storedProgress() -> [String: PlaybackProgress] {
        Dictionary(
            LibraryDatabase.allProgress().map { ($0.videoID, $0.progress) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Storage

    /// Saves a change to `record` and drops it when nothing needs it any
    /// more. The lists update by themselves after the save.
    private func commit(_ record: StoredVideo) {
        LibraryDatabase.deleteIfUnused(record)
        LibraryDatabase.save()
    }
}

/// Moves the library that earlier versions kept as JSON in UserDefaults into
/// SwiftData, once. Order is kept by spacing the dates a second apart.
@MainActor
enum LegacyLibraryMigration {
    private enum Keys {
        static let saved = "apple-videos.saved"
        static let watchlist = "apple-videos.watchlist"
        static let recent = "apple-videos.recent"
        static let progress = "apple-videos.progress"
        static let downloads = "apple-videos.downloads"
        static let legacyPlaylists = "apple-videos.playlists"
        static let legacyPlaylistVideos = "apple-videos.playlist-videos"
    }

    private struct WatchlistEntry: Decodable {
        let video: Video
        let addedAt: Date
    }

    private struct DownloadRecord: Decodable {
        let video: Video
        let path: String
        let downloadedAt: Date
    }

    static func run(defaults: UserDefaults = .standard) {
        let keys = [Keys.saved, Keys.watchlist, Keys.recent, Keys.progress, Keys.downloads]
        guard keys.contains(where: { defaults.object(forKey: $0) != nil }) else { return }
        let now = Date.now

        for (offset, video) in decode([Video].self, Keys.saved, defaults).enumerated() {
            let record = LibraryDatabase.record(for: video)
            record.savedAt = record.savedAt ?? now.addingTimeInterval(-Double(offset))
        }
        for (offset, video) in decode([Video].self, Keys.recent, defaults).prefix(50).enumerated() {
            let record = LibraryDatabase.record(for: video)
            record.watchedAt = record.watchedAt ?? now.addingTimeInterval(-Double(offset))
        }
        for entry in decode([WatchlistEntry].self, Keys.watchlist, defaults) {
            let record = LibraryDatabase.record(for: entry.video)
            record.watchlistAddedAt = record.watchlistAddedAt ?? entry.addedAt
        }
        for entry in decode([DownloadRecord].self, Keys.downloads, defaults) {
            let record = LibraryDatabase.record(for: entry.video)
            record.downloadPath = entry.path
            record.downloadedAt = entry.downloadedAt
        }
        // Positions are kept by video ID, apart from the video records.
        if let data = defaults.data(forKey: Keys.progress),
           let entries = try? JSONDecoder().decode([String: PlaybackProgress].self, from: data) {
            for (id, entry) in entries {
                LibraryDatabase.setProgress(entry, for: id)
            }
        }

        LibraryDatabase.save()
        for key in keys + [Keys.legacyPlaylists, Keys.legacyPlaylistVideos] {
            defaults.removeObject(forKey: key)
        }
    }

    private static func decode<T: Decodable & RangeReplaceableCollection>(
        _ type: T.Type,
        _ key: String,
        _ defaults: UserDefaults
    ) -> T {
        guard let data = defaults.data(forKey: key) else { return T() }
        return (try? JSONDecoder().decode(type, from: data)) ?? T()
    }
}
