import Foundation
import SwiftData

/// One stored video, kept once: its metadata, the lists it belongs to and
/// its download. (Its watch progress is a separate `WatchProgress`.) Saved, History, the Watchlist and
/// Downloaded are queries over these records, so refreshing a video updates
/// it everywhere at once.
@Model
final class StoredVideo {
    @Attribute(.unique) var id: String
    var title: String
    var channelName: String
    var thumbnailURL: URL?
    var duration: String?
    var publishedText: String?
    var publishedAt: Date?
    var viewCountText: String?
    var descriptionText: String?
    var badges: [String]?
    var sourceRawValue: String
    var playbackURL: URL?

    /// When the video was saved; nil when it is not in Saved.
    var savedAt: Date?
    /// When the video was last watched; nil when it is not in History.
    var watchedAt: Date?
    /// When the video was added to the Watchlist by hand.
    var watchlistAddedAt: Date?

    /// Legacy: watch progress moved to `WatchProgress`. Read once by
    /// `LibraryDatabase.migrateProgress()`, then cleared.
    var progressPosition: Double?
    var progressDuration: Double?
    var progressUpdatedAt: Date?

    /// The download package, relative to the home directory.
    var downloadPath: String?
    var downloadedAt: Date?

    init(video: Video) {
        id = video.id
        title = video.title
        channelName = video.channelName
        thumbnailURL = video.thumbnailURL
        duration = video.duration
        publishedText = video.publishedText
        publishedAt = video.publishedAt
        viewCountText = video.viewCountText
        descriptionText = video.descriptionText
        badges = video.badges
        sourceRawValue = video.source.rawValue
        playbackURL = video.playbackURL
    }

    var video: Video {
        Video(
            id: id,
            title: title,
            channelName: channelName,
            thumbnailURL: thumbnailURL,
            duration: duration,
            publishedText: publishedText,
            publishedAt: publishedAt,
            viewCountText: viewCountText,
            descriptionText: descriptionText,
            badges: badges,
            source: Video.Source(rawValue: sourceRawValue) ?? .youtube,
            playbackURL: playbackURL
        )
    }

    /// Copies newer metadata. Returns whether anything changed.
    @discardableResult
    func update(from video: Video) -> Bool {
        guard self.video != video else { return false }
        title = video.title
        channelName = video.channelName
        thumbnailURL = video.thumbnailURL
        duration = video.duration
        publishedText = video.publishedText
        publishedAt = video.publishedAt
        viewCountText = video.viewCountText
        descriptionText = video.descriptionText
        badges = video.badges
        sourceRawValue = video.source.rawValue
        playbackURL = video.playbackURL
        return true
    }

    var progress: PlaybackProgress? {
        guard let progressPosition, let progressDuration, let progressUpdatedAt else { return nil }
        return PlaybackProgress(position: progressPosition, duration: progressDuration, updatedAt: progressUpdatedAt)
    }

    func setProgress(_ progress: PlaybackProgress?) {
        progressPosition = progress?.position
        progressDuration = progress?.duration
        progressUpdatedAt = progress?.updatedAt
    }

    /// Belongs to no list, has no progress and no download: nothing needs it.
    var isUnused: Bool {
        savedAt == nil && watchedAt == nil && watchlistAddedAt == nil
            && progressPosition == nil && downloadPath == nil
    }
}

/// Where playback of a video stopped. Kept apart from `StoredVideo`: it is
/// written every few seconds while a video plays, and views that query the
/// stored videos must not update for that.
@Model
final class WatchProgress {
    @Attribute(.unique) var videoID: String
    var position: Double
    var duration: Double
    var updatedAt: Date

    init(videoID: String, progress: PlaybackProgress) {
        self.videoID = videoID
        position = progress.position
        duration = progress.duration
        updatedAt = progress.updatedAt
    }

    var progress: PlaybackProgress {
        PlaybackProgress(position: position, duration: duration, updatedAt: updatedAt)
    }
}

/// The app's one SwiftData store, shared by the library and the downloads.
@MainActor
enum LibraryDatabase {
    static let container: ModelContainer = {
        if let container = try? ModelContainer(for: StoredVideo.self, WatchProgress.self) {
            return container
        }
        // A store that cannot be opened must not stop the app from launching.
        let memory = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: StoredVideo.self, WatchProgress.self, configurations: memory)
    }()

    // MARK: Watch progress

    static func progress(id: String) -> WatchProgress? {
        var descriptor = FetchDescriptor<WatchProgress>(predicate: #Predicate { $0.videoID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func allProgress() -> [WatchProgress] {
        (try? context.fetch(FetchDescriptor<WatchProgress>())) ?? []
    }

    /// Stores or, with nil, deletes the position of a video.
    static func setProgress(_ progress: PlaybackProgress?, for id: String) {
        let existing = self.progress(id: id)
        guard let progress else {
            if let existing {
                context.delete(existing)
            }
            return
        }
        if let existing {
            existing.position = progress.position
            existing.duration = progress.duration
            existing.updatedAt = progress.updatedAt
        } else {
            context.insert(WatchProgress(videoID: id, progress: progress))
        }
    }

    /// Moves positions kept on video records by an earlier version into
    /// `WatchProgress`, once.
    static func migrateProgress() {
        let records = allRecords().filter { $0.progressPosition != nil }
        guard !records.isEmpty else { return }
        for record in records {
            if let legacy = record.progress, progress(id: record.id) == nil {
                context.insert(WatchProgress(videoID: record.id, progress: legacy))
            }
            record.setProgress(nil)
            deleteIfUnused(record)
        }
        save()
    }

    static var context: ModelContext {
        container.mainContext
    }

    /// The record for `id`, if the video is stored.
    static func record(id: String) -> StoredVideo? {
        var descriptor = FetchDescriptor<StoredVideo>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// The record for `video`, created when the video is not stored yet.
    static func record(for video: Video) -> StoredVideo {
        if let existing = record(id: video.id) {
            return existing
        }
        let record = StoredVideo(video: video)
        context.insert(record)
        return record
    }

    static func allRecords() -> [StoredVideo] {
        (try? context.fetch(FetchDescriptor<StoredVideo>())) ?? []
    }

    /// The stored videos matching `filter`, kept current by SwiftData
    /// (`ResultsObserver`, observable). Measured on iOS 27 (see
    /// `ResultsObserverTests`): the results update about 15–30 ms after a save
    /// that touches stored videos, not for saving changed watch progress.
    /// Nil only if the first fetch fails; the list is then empty.
    static func observe(
        _ filter: Predicate<StoredVideo>,
        sortedBy sort: SortDescriptor<StoredVideo>
    ) -> ResultsObserver<StoredVideo, Never>? {
        try? ResultsObserver(filterBy: filter, sortBy: [sort], modelContext: context)
    }

    /// Deletes `record` when nothing needs it any more.
    static func deleteIfUnused(_ record: StoredVideo) {
        if record.isUnused {
            context.delete(record)
        }
    }

    static func save() {
        try? context.save()
    }
}
