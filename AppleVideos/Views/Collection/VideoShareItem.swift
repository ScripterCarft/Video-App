import LinkPresentation
import UIKit

/// What the share sheet shares for a video: its YouTube link, with the
/// video's title known at once for the sheet's header (LinkPresentation
/// metadata). The header's image is YouTube's own preview image, loaded from
/// the page with `LPMetadataProvider` as the sheet would do by itself.
final class VideoShareItem: NSObject, UIActivityItemSource, @unchecked Sendable {
    // Immutable after init; the share sheet may ask from any thread.
    private let url: URL
    private let metadata: LPLinkMetadata

    init?(video: Video) {
        guard let url = video.youtubeURL else { return nil }
        self.url = url
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = video.title

        let image = NSItemProvider()
        image.registerObject(ofClass: UIImage.self, visibility: .all) { completion in
            nonisolated(unsafe) let completion = completion
            let fetcher = LPMetadataProvider()
            fetcher.startFetchingMetadata(for: url) { fetched, error in
                _ = fetcher
                guard let provider = fetched?.imageProvider else {
                    completion(nil, error)
                    return
                }
                provider.loadObject(ofClass: UIImage.self) { image, error in
                    completion(image as? UIImage, error)
                }
            }
            return nil
        }
        metadata.imageProvider = image
        self.metadata = metadata
    }

    /// The standard share sheet for `video`, from the bottom.
    @MainActor
    static func shareSheet(for video: Video) -> UIActivityViewController? {
        guard let item = VideoShareItem(video: video) else { return nil }
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
