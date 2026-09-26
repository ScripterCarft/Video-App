import Foundation

/// Every video the app knows, by ID: the ones it shows (search results, Home,
/// the library) and the stored ones. Navigation carries only a video's ID;
/// the destination reads the video here.
@MainActor
final class VideoCatalog {
    static let shared = VideoCatalog()

    private var known: [String: Video] = [:]

    /// Remembers `video`, keeping a 1280 thumbnail already known for it: Up
    /// Next lists only a small one for videos Home or the library show large.
    func remember(_ video: Video) {
        guard !Video.isLargeThumbnail(video.thumbnailURL),
              let knownURL = (known[video.id] ?? LibraryDatabase.record(id: video.id)?.video)?.thumbnailURL,
              Video.isLargeThumbnail(knownURL)
        else {
            known[video.id] = video
            return
        }
        known[video.id] = video.withThumbnail(knownURL)
    }

    func video(id: String) -> Video? {
        known[id] ?? LibraryDatabase.record(id: id)?.video
    }

    /// Loads a video that is neither shown nor stored, such as one whose
    /// detail screen is restored after a relaunch.
    func load(id: String) async -> Video? {
        if let video = video(id: id) {
            return video
        }
        guard let details = try? await YouTubeService.shared.details(for: id),
              let title = details.title
        else { return nil }

        let video = Video.youtube(
            id: id,
            title: title,
            channel: details.channelName ?? "",
            duration: details.duration,
            published: details.publishedText,
            publishedAt: details.publishedAt,
            views: details.viewCountText,
            thumbnailURL: details.thumbnailURL,
            description: details.description,
            badges: details.badges.isEmpty ? nil : details.badges
        )
        remember(video)
        return video
    }
}
