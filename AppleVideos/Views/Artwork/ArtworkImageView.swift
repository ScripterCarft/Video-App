import UIKit

/// Shared card artwork: immediate memory-cache hits, a dissolve on delivery,
/// and request identity checks when UIKit reuses a content view.
final class ArtworkImageView: UIImageView {
    private var request: ArtworkRequest?
    private var videoID: String?
    private var imageTask: Task<Void, Never>?

    deinit { imageTask?.cancel() }

    func load(_ video: Video, quality: ArtworkQuality, placeholder: UIImage? = nil) {
        let next = ArtworkRequest(
            video: video, quality: quality,
            displayScale: traitCollection.displayScale,
            lowData: NetworkConditions.shared.isConstrained
        )
        guard next != request || videoID != video.id else { return }
        let sameVideo = videoID == video.id
        request = next
        videoID = video.id
        imageTask?.cancel()
        layer.removeAllAnimations()

        if let cached = ArtworkLoader.cachedImage(for: next) {
            image = cached
            return
        }
        // Keep the existing image during an upgrade, but never show the
        // previous video's image in a reused card.
        if !sameVideo { image = placeholder }
        imageTask = Task { [weak self] in
            let image = await ArtworkLoader.firstImage(for: next)
            guard !Task.isCancelled, let self, self.request == next else { return }
            self.imageTask = nil
            guard let image else {
                // A later reconfiguration may retry a transient failure.
                self.request = nil
                return
            }
            self.display(image, animated: true)
        }
    }

    func display(_ image: UIImage, animated: Bool) {
        guard animated, window != nil, !UIAccessibility.isReduceMotionEnabled else {
            self.image = image
            return
        }
        UIView.transition(
            with: self, duration: 0.25,
            options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.image = image
        }
    }
}
