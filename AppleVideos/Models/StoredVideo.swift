import Foundation
import SwiftData

/// One stored video, kept once: its metadata, the lists it belongs to, its
/// watch progress and its download. Saved, History, the Watchlist and
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

/// The app's one SwiftData store, shared by the library and the downloads.
@MainActor
enum LibraryDatabase {
    static let container: ModelContainer = {
        if let container = try? ModelContainer(for: StoredVideo.self) {
            return container
        }
        // A store that cannot be opened must not stop the app from launching.
        let memory = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: StoredVideo.self, configurations: memory)
    }()

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
