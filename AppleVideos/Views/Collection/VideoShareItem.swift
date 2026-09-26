import LinkPresentation
import UIKit

/// What the share sheet shares for a video: its YouTube link, with the
/// video's title and the thumbnail already on screen as the sheet's header
/// (LinkPresentation metadata), so the sheet shows them at once instead of
/// fetching the page first.
final class VideoShareItem: NSObject, UIActivityItemSource, @unchecked Sendable {
    // Immutable after init; the share sheet may ask from any thread.
    private let url: URL
    private let metadata: LPLinkMetadata

    init?(video: Video, image: UIImage?) {
        guard let url = video.youtubeURL else { return nil }
        self.url = url
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = video.title
        if let image {
            metadata.imageProvider = NSItemProvider(object: image)
        }
        self.metadata = metadata
    }

    /// The standard share sheet for `video`, from the bottom.
    @MainActor
    static func shareSheet(for video: Video, image: UIImage?) -> UIActivityViewController? {
        guard let item = VideoShareItem(video: video, image: image) else { return nil }
        return UIActivityViewController(activityItems: [item], applicationActivities: nil)
    }

    nonisolated func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    nonisolated func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    nonisolated func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        metadata
    }
}
