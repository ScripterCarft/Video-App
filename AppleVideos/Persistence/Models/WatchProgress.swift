import Foundation
import SwiftData

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
