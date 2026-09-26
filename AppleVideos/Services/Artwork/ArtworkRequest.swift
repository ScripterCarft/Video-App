import Foundation

/// The complete identity of a prepared image, shared by views and prefetching.
/// Cropping and pixel width affect the result even when the URLs are identical.
struct ArtworkRequest: Hashable, Sendable {
    let candidates: [ArtworkCandidate]
    let requiresSixteenByNine: Bool
    let maxPixelWidth: CGFloat

    init(video: Video, quality: ArtworkQuality, displayScale: CGFloat, lowData: Bool) {
        self.init(
            candidates: video.artworkCandidates(lowData: lowData),
            requiresSixteenByNine: video.source == .youtube,
            maxPixelWidth: quality.displayWidth * max(displayScale, 1)
        )
    }

    init(candidates: [ArtworkCandidate], requiresSixteenByNine: Bool, maxPixelWidth: CGFloat) {
        self.candidates = candidates
        self.requiresSixteenByNine = requiresSixteenByNine
        self.maxPixelWidth = max(1, maxPixelWidth.rounded(.up))
    }
}
