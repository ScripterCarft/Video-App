import SwiftUI

/// The detail screen's state and loading, in one observable object that its
/// collection view cells read directly.
///
/// Loading runs in order: the details first, shown in one step; then the
/// related videos for the Up Next shelf; then, while the screen stays, the
/// stream so Play starts without waiting. It survives AVKit removing and
/// re-adding the screen, so nothing reloads under the player.
@MainActor
@Observable
final class VideoDetailModel {
    let video: Video
    private(set) var refreshedVideo: Video?
    private(set) var loadedDescription: String?
    private(set) var loadedBadges: [String]?
    private(set) var streamBadges: [String] = []
    private(set) var detailsLoadFinished = false
    private(set) var related: [Video] = []
    @ObservationIgnored private var relatedLoaded = false
    @ObservationIgnored private var streamLoaded = false

    init(video: Video) {
        self.video = video
    }

    /// The video with the freshest metadata available.
    var shown: Video {
        refreshedVideo ?? video
    }

    /// Prefers the full description from the details request over the short
    /// snippet that search results carry.
    var visibleDescription: String? {
        [loadedDescription, video.descriptionText]
            .lazy
            .compactMap { $0?.collapsedWhitespace }
            .first
    }

    var visibleBadges: [String] {
        let original = video.badges ?? []
        // Technical badges come from the resolved stream; the details request
        // (WEB client) is refused playback data and only supplies live status.
        let verified = streamBadges + (loadedBadges ?? [])
        let resolutions = Set(["8K", "4K", "HD", "SD"])
        let resolution = verified.first(where: resolutions.contains)
            ?? original.first(where: resolutions.contains)
        let supported = ["HDR", "CC", "SDH", "360°", "LIVE", "PREMIERE", "UPCOMING"]
        let combined = Set(original + verified)
        return [resolution].compactMap { $0 } + supported.filter(combined.contains)
    }

    var textMetadata: [String] {
        [shown.formattedDuration, shown.viewCountText, shown.publishedLabel]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
    }

    /// Loads what is still missing. Called from the screen's task, which
    /// SwiftUI cancels when the screen goes away; a cancelled step is
    /// retried the next time.
    func load(library: LibraryStore) async {
        if !detailsLoadFinished {
            if video.source == .youtube {
                let details = try? await YouTubeService.shared.details(for: video.id)
                guard !Task.isCancelled else { return }
                // Current title, views and publish date, from the details above.
                let refreshed = details == nil ? nil : try? await YouTubeService.shared.refreshedVideo(video)
                guard !Task.isCancelled else { return }

                // Everything that loaded appears at once, not piece by piece.
                withAnimation(.easeOut(duration: 0.25)) {
                    loadedDescription = details?.description
                    loadedBadges = details.flatMap { $0.badges.isEmpty ? nil : $0.badges }
                    refreshedVideo = refreshed
                    detailsLoadFinished = true
                }
                if let refreshed {
                    // Stored when the screen leaves; see the screen's onDisappear.
                    library.rememberFresh(refreshed)
                }
            } else {
                detailsLoadFinished = true
            }
        }

        if !relatedLoaded, video.source == .youtube {
            let videos = (try? await YouTubeService.shared.relatedVideos(for: video.id)) ?? []
            guard !Task.isCancelled else { return }
            related = videos
            relatedLoaded = true
        }

        if !streamLoaded {
            // While the screen stays, resolve the stream so Play starts without
            // waiting; its formats and captions also give the badges.
            let badges = await NativePlayback.prefetch(video)?.technicalBadges ?? []
            guard !Task.isCancelled else { return }
            streamLoaded = true
            if badges != streamBadges {
                streamBadges = badges
            }
        }
    }
}
