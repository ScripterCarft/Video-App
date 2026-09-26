import Observation

/// The detail screen's state and loading, in one observable object that its
/// collection view cells read directly. This service contains no UIKit or
/// player ownership; the controller owns its task and optional stream prefetch.
///
/// Loading runs in order: the details first, shown in one step; then the
/// related videos for the Up Next shelf. It survives AVKit removing and
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
    private(set) var relatedLoadFinished: Bool
    private(set) var isLoading = false
    private(set) var hasLoadFailure = false
    @ObservationIgnored private var detailsLoaded = false
    @ObservationIgnored private var relatedLoaded = false
    @ObservationIgnored private let loadDetails: @Sendable (String) async throws -> YouTubeService.VideoDetails
    @ObservationIgnored private let loadRelated: @Sendable (String) async throws -> [Video]

    init(
        video: Video,
        loadDetails: @escaping @Sendable (String) async throws -> YouTubeService.VideoDetails = { try await YouTubeService.shared.details(for: $0) },
        loadRelated: @escaping @Sendable (String) async throws -> [Video] = { try await YouTubeService.shared.relatedVideos(for: $0) }
    ) {
        self.video = video
        self.loadDetails = loadDetails
        self.loadRelated = loadRelated
        relatedLoadFinished = video.source != .youtube
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

    /// Loads what is still missing. Called from the screen's load task, which
    /// the screen cancels when it leaves for good; a cancelled step is
    /// retried the next time.
    func load() async {
        guard !isLoading, !Task.isCancelled else { return }
        guard video.source == .youtube else {
            detailsLoadFinished = true
            return
        }
        isLoading = true
        hasLoadFailure = false
        defer { isLoading = false }
        if !detailsLoaded {
            detailsLoadFinished = false
            do {
                let details = try await loadDetails(video.id)
                guard !Task.isCancelled else { return }
                loadedDescription = details.description
                loadedBadges = details.badges.isEmpty ? nil : details.badges
                refreshedVideo = YouTubeService.refresh(video, with: details)
                detailsLoaded = true
            } catch {
                guard !Task.isCancelled else { return }
                hasLoadFailure = true
            }
            detailsLoadFinished = true
        }

        if !relatedLoaded {
            relatedLoadFinished = false
            do {
                let videos = try await loadRelated(video.id)
                guard !Task.isCancelled else { return }
                related = videos
                relatedLoaded = true
            } catch {
                guard !Task.isCancelled else { return }
                hasLoadFailure = true
            }
            relatedLoadFinished = true
        }
    }

    /// A skipped/failed optional prefetch must not count as loaded.
    func setStreamBadges(_ badges: [String]) {
        if badges != streamBadges { streamBadges = badges }
    }
}
