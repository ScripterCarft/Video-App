import Foundation

/// Where a download loads a video's HLS stream from. Like `PlaybackResolving`,
/// the route is exchangeable: today the download service loads YouTube's
/// stream directly; a route through the app can be added beside it.
protocol DownloadURLProviding: Sendable {
    /// The HLS master playlist URL to download, freshly resolved so the
    /// download gets the stream link's full validity.
    func masterPlaylistURL(for video: Video) async throws -> URL
}

enum DownloadError: LocalizedError {
    case notDownloadable
    case noStream
    case noCompatibleVariant

    var errorDescription: String? {
        switch self {
        case .notDownloadable:
            "This video can't be downloaded."
        case .noStream:
            "YouTube offers no downloadable stream for this video."
        case .noCompatibleVariant:
            "YouTube offers no H.264 version of this video."
        }
    }
}

/// The download service loads YouTube's HLS stream directly.
struct DirectDownloadURLProvider: DownloadURLProviding {
    func masterPlaylistURL(for video: Video) async throws -> URL {
        guard video.source == .youtube else { throw DownloadError.notDownloadable }
        // A link prefetched for playback may be close to expiring.
        await YouTubeInnertubePlaybackResolver.shared.invalidate(videoID: video.id)
        let source = try await YouTubeInnertubePlaybackResolver.shared.resolve(
            PlaybackRequest(videoID: video.id)
        )
        guard let url = source.variants.first(where: { $0.transport == .hls })?.url else {
            throw DownloadError.noStream
        }
        return url
    }
}
