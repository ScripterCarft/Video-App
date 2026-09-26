import Foundation
import Observation
import SwiftData

/// Saved, History, the Watchlist and watch progress, stored in SwiftData with
/// one `StoredVideo` per video and one `WatchProgress` per started video.
/// The lists published here are read from the store after each change and
/// after every save of the shared context; library screens query the store
/// directly.
///
/// Watch progress is written to the store during playback (it survives a
/// crash) but `progress`, which the UI reads, changes only when a player has
/// closed, so nothing re-renders while AVKit is on screen. Because progress is
/// a separate model, queries over stored videos do not update for it.
@MainActor
@Observable
final class LibraryStore {
    private(set) var savedVideos: [Video] = []
    /// History, shown as "Recently Watched" in menus.
    private(set) var recentlyWatched: [Video] = []
    /// Videos added to the Watchlist by hand, with the date they were added.
    private var manualWatchlist: [(video: Video, addedAt: Date)] = []
    /// Watch progress as last shown in the UI.
    private(set) var progress: [String: PlaybackProgress] = [:]

    /// The freshest copy of every video refreshed since launch.
    @ObservationIgnored private var refreshedThisLaunch: [String: Video] = [:]
    @ObservationIgnored private var refreshingIDs: Set<String> = []
    /// Videos played to the end in the open player; applied on close.
    @ObservationIgnored private var finishedSincePublish: Set<String> = []
    @ObservationIgnored private var saveObserver: NSObjectProtocol?

    private static let historyLimit = 50
    private static let maximumProgressEntries = 200

    init() throws {
        let records = try LibraryDatabase.allRecords()
        let entries = try LibraryDatabase.allProgress()
        applyRecords(records)
        progress = Dictionary(entries.map { ($0.videoID, $0.progress) }, uniquingKeysWith: { first, _ in first })

        // Downloads share the store; reload when anything is saved. Unchanged
        // lists are not reassigned, so progress saves during playback do not
        // re-render anything.
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: LibraryDatabase.context,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadLists()
            }
        }
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
        write {
            let record = try LibraryDatabase.record(for: freshest(video))
            record.savedAt = record.savedAt == nil ? .now : nil
            try LibraryDatabase.deleteIfUnused(record)
        }
    }

    // MARK: - History

    func markWatched(_ video: Video) {
        write {
            let record = try LibraryDatabase.record(for: freshest(video))
            record.update(from: freshest(video))
            record.watchedAt = .now
            try trimHistory()
        }
    }

    func isInRecentlyWatched(_ video: Video) -> Bool {
        recentlyWatched.contains { $0.id == video.id }
    }

    /// Removes `video` from History. Its saved position goes too, so it also
    /// leaves the Watchlist unless it was added there by hand.
    func removeFromRecentlyWatched(_ video: Video) {
        if write({
            guard let record = try LibraryDatabase.record(id: video.id) else { return }
            record.watchedAt = nil
            try LibraryDatabase.setProgress(nil, for: record.id)
            try LibraryDatabase.deleteIfUnused(record)
        }) { reloadProgress() }
    }

    /// Empties History except the videos `keeping` returns true for, such as
    /// downloads. Like removing one video, it forgets the removed videos'
    /// saved positions, so they leave the Watchlist unless added by hand.
    func removeAllFromRecentlyWatched(keeping: (Video) -> Bool) {
        if write({
            for record in try LibraryDatabase.allRecords() where record.watchedAt != nil && !keeping(record.video) {
                record.watchedAt = nil
                try LibraryDatabase.setProgress(nil, for: record.id)
                try LibraryDatabase.deleteIfUnused(record)
            }
        }) { reloadProgress() }
    }

    /// Keeps the most recent videos in History; older ones leave it.
    private func trimHistory() throws {
        let watched = try LibraryDatabase.allRecords()
            .filter { $0.watchedAt != nil }
            .sorted { $0.watchedAt! > $1.watchedAt! }
        for record in watched.dropFirst(Self.historyLimit) {
            record.watchedAt = nil
            try LibraryDatabase.deleteIfUnused(record)
        }
    }

    // MARK: - Watchlist

    /// Videos added by hand and videos from History that were started and not
    /// finished, most recent activity first. Finishing a video removes it.
    var watchlist: [Video] {
        var latest: [String: (video: Video, date: Date)] = [:]
        for entry in manualWatchlist {
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
        manualWatchlist.contains { $0.video.id == video.id }
            || (progress(for: video) != nil && isInRecentlyWatched(video))
    }

    func addToWatchlist(_ video: Video) {
        write {
            let record = try LibraryDatabase.record(for: freshest(video))
            guard record.watchlistAddedAt == nil else { return }
            record.watchlistAddedAt = .now
        }
    }

    /// Removes the entry added by hand and forgets the saved position; the
    /// video stays in History.
    func removeFromWatchlist(_ video: Video) {
        if write({
            guard let record = try LibraryDatabase.record(id: video.id) else { return }
            record.watchlistAddedAt = nil
            try LibraryDatabase.setProgress(nil, for: record.id)
            try LibraryDatabase.deleteIfUnused(record)
        }) { reloadProgress() }
    }

    /// Takes `video` off the Watchlist and records it in History as watched.
    func markAsWatched(_ video: Video) {
        if write({
            let record = try LibraryDatabase.record(for: freshest(video))
            record.watchlistAddedAt = nil
            try LibraryDatabase.setProgress(nil, for: video.id)
            record.update(from: freshest(video))
            record.watchedAt = .now
            try trimHistory()
        }) { reloadProgress() }
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
        write {
            guard let record = try LibraryDatabase.record(id: video.id) else { return }
            record.update(from: video)
        }
    }

    // MARK: - Watch progress

    /// Where to resume `video`, if it was started and not finished.
    func resumePosition(for video: Video) -> Double? {
        do {
            guard let entry = try LibraryDatabase.progress(id: video.id)?.progress, entry.isResumable else { return nil }
            return entry.position
        } catch {
            LibraryStorageStatus.shared.report(error, operation: "read your saved position")
            return progress(for: video)?.position
        }
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
        if write({
            try LibraryDatabase.setProgress(entry.isResumable ? entry : nil, for: video.id)
            if entry.isResumable { try trimProgress() }
        }), entry.fraction >= PlaybackProgress.finishedFraction {
            finishedSincePublish.insert(video.id)
        }
    }

    /// Shows the saved progress in the UI and takes finished videos off the
    /// Watchlist. Called once a player has closed.
    func publishProgress() {
        let finished = finishedSincePublish
        if write({
            for id in finished {
                guard let record = try LibraryDatabase.record(id: id), record.watchlistAddedAt != nil else { continue }
                record.watchlistAddedAt = nil
                try LibraryDatabase.deleteIfUnused(record)
            }
        }) {
            finishedSincePublish.subtract(finished)
        }
        reloadProgress()
    }

    /// Keeps the most recent saved positions.
    private func trimProgress() throws {
        let entries = try LibraryDatabase.allProgress().sorted { $0.updatedAt > $1.updatedAt }
        for entry in entries.dropFirst(Self.maximumProgressEntries) {
            try LibraryDatabase.deleteProgress(entry)
        }
    }

    private func reloadProgress() {
        do {
            let stored = Dictionary(
                try LibraryDatabase.allProgress().map { ($0.videoID, $0.progress) },
                uniquingKeysWith: { first, _ in first }
            )
            if progress != stored { progress = stored }
        } catch {
            LibraryStorageStatus.shared.report(error, operation: "read your saved positions")
        }
    }

    // MARK: - Storage

    @discardableResult
    private func write(_ changes: () throws -> Void) -> Bool {
        do {
            try LibraryDatabase.transaction(changes)
            LibraryStorageStatus.shared.didSave()
            return true
        } catch {
            LibraryStorageStatus.shared.report(error, operation: "save your library changes")
            return false
        }
    }

    /// Reads the lists from the store. A list is only reassigned when it
    /// changed, so observers re-render only for real changes.
    private func reloadLists() {
        let records: [StoredVideo]
        do {
            records = try LibraryDatabase.allRecords()
        } catch {
            LibraryStorageStatus.shared.report(error, operation: "read your library")
            return
        }
        applyRecords(records)
    }

    private func applyRecords(_ records: [StoredVideo]) {
        let saved = records
            .filter { $0.savedAt != nil }
            .sorted { $0.savedAt! > $1.savedAt! }
            .map(\.video)
        if saved != savedVideos {
            savedVideos = saved
        }

        let watched = records
            .filter { $0.watchedAt != nil }
            .sorted { $0.watchedAt! > $1.watchedAt! }
            .map(\.video)
        if watched != recentlyWatched {
            recentlyWatched = watched
        }

        let manual = records
            .compactMap { record in record.watchlistAddedAt.map { (video: record.video, addedAt: $0) } }
            .sorted { $0.addedAt > $1.addedAt }
        if manual.map(\.video) != manualWatchlist.map(\.video)
            || manual.map(\.addedAt) != manualWatchlist.map(\.addedAt) {
            manualWatchlist = manual
        }
    }
}
