import UIKit

/// The artwork layer: the stage at the top edge with the 16:9 thumbnail
/// centered in it, on black below. As the collection view's background view
/// it stays in place; it lays out only when its size changes.
final class DetailArtworkView: UIView {
    private let stage = UIView()
    private let imageView = ArtworkImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        // TEST: light blue shows the stage's extent while we build the screen.
        stage.backgroundColor = UIColor(red: 0.72, green: 0.84, blue: 1, alpha: 1)
        stage.clipsToBounds = true
        imageView.contentMode = .scaleAspectFit
        stage.addSubview(imageView)
        addSubview(stage)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let height = DetailStage.height(forWidth: width, scale: traitCollection.displayScale)
        // Bounds and center, not frame: the stage carries the scroll transform.
        stage.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        stage.center = CGPoint(x: width / 2, y: height / 2)
        let thumbnailHeight = width * 9 / 16
        imageView.frame = CGRect(x: 0, y: (height - thumbnailHeight) / 2, width: width, height: thumbnailHeight)
    }

    /// Follows the page, like the TV app: scrolled up by `offset`, the stage
    /// moves up at half the speed while the page slides over it; pulled down
    /// past the top, it grows from its top edge, evenly in both directions,
    /// and fills the gap above the page. One transform on one layer, so
    /// nothing is drawn or laid out again.
    func follow(offset: CGFloat) {
        let height = stage.bounds.height
        guard height > 0 else { return }
        if offset >= 0 {
            stage.transform = CGAffineTransform(translationX: 0, y: -offset / 2)
        } else {
            let scale = (height - offset) / height
            // Scaling around the center moves the top up by half the growth;
            // moving back down by that keeps the top edge in place.
            stage.transform = CGAffineTransform(translationX: 0, y: (scale - 1) * height / 2)
                .scaledBy(x: scale, y: scale)
        }
    }

    private var pendingVideo: Video?
    private var shownThumbnail: URL?
    private var loadTask: Task<Void, Never>?

    deinit { loadTask?.cancel() }

    /// Loads the artwork once, from the shared loader and its cache, as soon
    /// as the view is on screen and knows its display scale.
    func load(_ video: Video) {
        pendingVideo = video
        loadIfPossible()
    }

    /// Loads the 1280 thumbnail the details list for a video that was opened
    /// with a smaller one (Up Next lists only `hqdefault`). Not in Low Data
    /// Mode, where 1280 artwork is left out.
    func upgrade(to video: Video) {
        guard Video.isLargeThumbnail(video.thumbnailURL),
              !Video.isLargeThumbnail(shownThumbnail),
              !NetworkConditions.shared.isConstrained
        else { return }
        load(video)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        loadIfPossible()
    }

    private func loadIfPossible() {
        guard window != nil, let video = pendingVideo else { return }
        pendingVideo = nil
        shownThumbnail = video.thumbnailURL
        // A smaller image still loading must not replace the upgrade.
        loadTask?.cancel()
        let candidates = video.artworkCandidates(lowData: NetworkConditions.shared.isConstrained)
        let request = ArtworkRequest(candidates: candidates, requiresSixteenByNine: video.source == .youtube,
                                     maxPixelWidth: ArtworkQuality.hero.displayWidth * max(traitCollection.displayScale, 1))
        if let cached = ArtworkLoader.cachedImage(for: request) {
            show(cached)
            return
        }
        loadTask = Task { [weak self] in
            let image = await ArtworkLoader.firstImage(for: request)
            guard !Task.isCancelled, let self else { return }
            // An upgrade that fails keeps the image already shown.
            if image != nil || self.imageView.image == nil {
                self.show(image)
            }
        }
    }

    /// Keep the existing image if an upgrade fails.
    private func show(_ image: UIImage?) {
        guard let image else { return }
        imageView.display(image, animated: imageView.image != nil)
    }

}
