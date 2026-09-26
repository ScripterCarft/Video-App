import UIKit

/// The shape of the detail screen's artwork stage: 2:3, with the 16:9
/// thumbnail centered in it.
enum DetailStage {
    /// The stage is this many times as tall as it is wide.
    static let heightRatio: CGFloat = 1.5

    /// The stage's height for a width, on whole pixels, so the page's black
    /// meets it without a half-covered pixel row.
    static func height(forWidth width: CGFloat, scale: CGFloat) -> CGFloat {
        let scale = max(scale, 1)
        return (width * heightRatio * scale).rounded() / scale
    }
}

/// A video's detail screen as a UIKit screen, in two layers. Behind: the
/// artwork stage as the collection view's background view, which UIKit
/// keeps in place. In front: a clear spacer over the stage, then the Up
/// Next shelf on a black page that starts at the stage's lower edge and
/// slides over it. Every size is fixed; nothing is measured while scrolling.
///
/// The bar has Download (with its progress ring) and Share. The screen reads
/// the observable model and download state in `updateProperties()`, which
/// UIKit tracks, so the shelf and the Download button update by themselves.
/// The hero (title, Play, description) comes later.
final class VideoDetailViewController: UIViewController, UICollectionViewDelegate {
    /// Opens a video from Up Next; the view to zoom from is looked up when
    /// the zoom needs it.
    typealias OpenAction = @MainActor (VideoRoute, @escaping @MainActor () -> UIView?) -> Void

    enum Section: Hashable {
        case stage
        case upNext
    }

    enum Item: Hashable {
        case stage
        case video(String)
    }

    private static let cardWidth: CGFloat = 272
    private static let shelfID = "upnext"
    private static let shelfBackgroundKind = "detail-shelf-background"

    let route: VideoRoute
    private let library: LibraryStore
    private let downloads = DownloadManager.shared
    private let onOpen: OpenAction

    private var model: VideoDetailModel?
    private var loadTask: Task<Void, Never>?
    private var shownRelated: [Video] = []
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private lazy var collectionView = DetailCollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private lazy var menus = VideoContextMenus(library: library, downloads: downloads, presenter: self)
    private let artwork = DetailArtworkView()
    private let downloadButton = DownloadBarButton()

    init(route: VideoRoute, library: LibraryStore, onOpen: @escaping OpenAction) {
        self.route = route
        self.library = library
        self.onOpen = onOpen
        super.init(nibName: nil, bundle: nil)
        // The detail screen is always dark, like the TV app's.
        overrideUserInterfaceStyle = .dark
        navigationItem.largeTitleDisplayMode = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        loadTask?.cancel()
    }

    /// Light status bar text on the always dark screen.
    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override func loadView() {
        // The collection view is the screen, so the navigation bar follows it
        // for its scroll edge effect by itself.
        view = collectionView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.backgroundColor = .black
        // The artwork fills the whole screen behind the content, bars
        // included, and stays in place.
        collectionView.backgroundView = artwork
        // UIKit keeps the content clear of the bars (automatic insets), so at
        // rest nothing lies under the navigation bar and its scroll edge
        // effect appears only once the page scrolls.
        collectionView.contentInset.bottom = 30
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        configureDataSource()
        applySnapshot(related: [], animated: false)

        if let video = VideoCatalog.shared.video(id: route.videoID) {
            start(with: video)
        } else {
            // A video the app does not know yet, such as one restored after
            // a relaunch: Apple's loading view until it is loaded.
            contentUnavailableConfiguration = UIContentUnavailableConfiguration.loading()
            let videoID = route.videoID
            loadTask = Task { [weak self] in
                let video = await VideoCatalog.shared.load(id: videoID)
                guard let self, !Task.isCancelled else { return }
                if let video {
                    self.contentUnavailableConfiguration = nil
                    self.start(with: video)
                } else {
                    var unavailable = UIContentUnavailableConfiguration.empty()
                    unavailable.text = "Video Unavailable"
                    unavailable.image = UIImage(systemName: "play.slash")
                    self.contentUnavailableConfiguration = unavailable
                }
            }
        }
    }

    /// Shows `video` and loads, in order, its details, Up Next and the stream.
    private func start(with video: Video) {
        let model = VideoDetailModel(video: video)
        self.model = model
        artwork.load(video)
        configureBarButtons(for: video)
        setNeedsUpdateProperties()
        // The model keeps what has loaded, so nothing reloads when the player
        // covers the screen and uncovers it again.
        let library = library
        loadTask = Task {
            await model.load(library: library)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // White bar buttons on the dark screen, like the TV app. Only when
        // this screen is on a UIKit stack itself, not inside a SwiftUI one.
        if navigationController?.topViewController === self {
            navigationController?.navigationBar.tintColor = .white
        }
        // Inside a SwiftUI screen, the bar follows the scroll view through
        // the hosting screen.
        var host: UIViewController = self
        while let parent = host.parent, !(parent is UINavigationController) {
            host = parent
        }
        host.setContentScrollView(collectionView, for: .top)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Store the refreshed metadata once the screen has left, so nothing on
        // the screen behind changes during the zoom back. The player covering
        // this screen is not leaving it.
        if !NativePlayback.isShowingPlayer, let refreshed = model?.refreshedVideo {
            library.updateMetadata(of: refreshed)
        }
        // Leaving for good stops what is still loading.
        if isMovingFromParent || navigationController == nil {
            loadTask?.cancel()
        }
    }

    /// Reads Up Next and the download state; UIKit tracks both and calls this
    /// again when they change.
    override func updateProperties() {
        super.updateProperties()
        guard let model else { return }
        if let refreshed = model.refreshedVideo {
            artwork.upgrade(to: refreshed)
        }
        let related = model.related
        if related != shownRelated {
            applySnapshot(related: related, animated: view.window != nil)
        }
        downloadButton.update(
            activity: downloads.activity(for: model.video),
            isDownloaded: downloads.isDownloaded(model.video),
            canDownload: downloads.canDownload(model.video)
        )
    }

    /// The spacer depends on the top inset (see `stageSection`).
    func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        collectionView.collectionViewLayout.invalidateLayout()
        followScroll()
    }

    /// The artwork follows the page (see `DetailArtworkView.follow`).
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        followScroll()
    }

    /// How far the page has scrolled from its resting position.
    private func followScroll() {
        artwork.follow(offset: collectionView.contentOffset.y + collectionView.adjustedContentInset.top)
    }

    // MARK: - Bar buttons

    private func configureBarButtons(for video: Video) {
        guard video.youtubeURL != nil else { return }
        let share = UIBarButtonItem(
            title: "Share",
            image: UIImage(systemName: "square.and.arrow.up"),
            primaryAction: UIAction { [weak self] _ in
                // The standard share sheet from the bottom, the title known at once.
                guard let self, let controller = VideoShareItem.shareSheet(for: video) else { return }
                self.present(controller, animated: true)
            }
        )
        downloadButton.onDownload = { [downloads] in downloads.download(video) }
        downloadButton.onStop = { [downloads] in downloads.cancel(video) }
        downloadButton.onRenew = { [downloads] in downloads.renew(video) }
        downloadButton.onRemove = { [downloads] in downloads.remove(video) }
        // The rightmost item comes first.
        navigationItem.rightBarButtonItems = [share, downloadButton.item]
    }

    // MARK: - Layout

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            switch self?.dataSource?.sectionIdentifier(for: index) {
            case .stage:
                // The content starts below the bars; the spacer ends where the
                // artwork does, so the black page begins at its lower edge.
                let stage = DetailStage.height(
                    forWidth: environment.container.effectiveContentSize.width,
                    scale: environment.traitCollection.displayScale
                )
                let topInset = self?.collectionView.adjustedContentInset.top ?? 0
                return VideoDetailViewController.stageSection(height: max(1, stage - topInset))
            case .upNext:
                let section = VideoCells.shelfSection(
                    cardWidth: VideoDetailViewController.cardWidth,
                    headerTopSpacing: 14,
                    traits: environment.traitCollection
                )
                // The black page, from the artwork's lower edge down. It
                // reaches two screen heights past the shelf, so the page never
                // ends on screen, even when pulled beyond its end.
                let page = NSCollectionLayoutDecorationItem.background(elementKind: VideoDetailViewController.shelfBackgroundKind)
                page.contentInsets.bottom = -2 * environment.container.effectiveContentSize.height
                section.decorationItems = [page]
                return section
            case nil:
                return nil
            }
        }
        layout.register(DetailShelfBackground.self, forDecorationViewOfKind: Self.shelfBackgroundKind)
        return layout
    }

    /// A clear spacer over the artwork stage, below the bars.
    private static func stageSection(height: CGFloat) -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
        return NSCollectionLayoutSection(group: group)
    }

    // MARK: - Cells

    private func configureDataSource() {
        let stageRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Item> { _, _, _ in }
        let videoRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Item> { [weak self] cell, _, item in
            MainActor.assumeIsolated {
                guard case let .video(id) = item,
                      let video = self?.shownRelated.first(where: { $0.id == id })
                else { return }
                cell.contentConfiguration = VideoCardConfiguration(video: video)
            }
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { header, _, _ in
            MainActor.assumeIsolated {
                header.contentConfiguration = VideoCells.headerConfiguration(title: "Up Next", topSpacing: 14)
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            if item == .stage {
                return collectionView.dequeueConfiguredReusableCell(using: stageRegistration, for: indexPath, item: item)
            }
            return collectionView.dequeueConfiguredReusableCell(using: videoRegistration, for: indexPath, item: item)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    private func applySnapshot(related: [Video], animated: Bool) {
        shownRelated = related
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.stage])
        snapshot.appendItems([.stage], toSection: .stage)
        if !related.isEmpty {
            snapshot.appendSections([.upNext])
            // Unique IDs: the data source requires them.
            var seen = Set<String>()
            let ids = related.map(\.id).filter { seen.insert($0).inserted }
            snapshot.appendItems(ids.map { .video($0) }, toSection: .upNext)
        }
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    // MARK: - Selection and menus

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath) != .stage
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case let .video(id) = item,
              let video = shownRelated.first(where: { $0.id == id })
        else { return }
        onOpen(VideoRoute(video: video, section: Self.shelfID)) { [weak self] in
            guard let self,
                  let indexPath = self.dataSource.indexPath(for: item),
                  let cell = self.collectionView.cellForItem(at: indexPath)
            else { return nil }
            return VideoCells.zoomSource(of: cell)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first,
              case let .video(id)? = dataSource.itemIdentifier(for: indexPath),
              let video = shownRelated.first(where: { $0.id == id })
        else { return nil }
        return menus.configuration(for: video, in: collectionView.cellForItem(at: indexPath)) { [weak collectionView] in
            collectionView?.cellForItem(at: indexPath)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfiguration configuration: UIContextMenuConfiguration,
        highlightPreviewForItemAt indexPath: IndexPath
    ) -> UITargetedPreview? {
        VideoContextMenus.targetedPreview(of: collectionView.cellForItem(at: indexPath))
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfiguration configuration: UIContextMenuConfiguration,
        dismissalPreviewForItemAt indexPath: IndexPath
    ) -> UITargetedPreview? {
        VideoContextMenus.targetedPreview(of: collectionView.cellForItem(at: indexPath))
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplayContextMenu configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        menus.willDisplay()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willEndContextMenuInteraction configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        menus.willEnd(animator: animator)
    }
}

/// The bar's Download button: Download, the progress ring while a download
/// runs (tap to stop), or the downloaded state, whose system menu offers to
/// renew or remove the download right at the button. Always a plain bar
/// button item, so the bar sizes it like its other buttons; the ring is the
/// item's image, drawn again only when the progress changes by a percent.
@MainActor
private final class DownloadBarButton {
    private enum State: Equatable {
        case available(Bool)
        case loading
        case downloaded
    }

    let item = UIBarButtonItem()
    var onDownload: () -> Void = {}
    var onStop: () -> Void = {}
    var onRenew: () -> Void = {}
    var onRemove: () -> Void = {}

    private var state: State?
    private var shownPercent: Int?

    func update(activity: DownloadManager.Activity?, isDownloaded: Bool, canDownload: Bool) {
        let newState: State = activity != nil ? .loading : isDownloaded ? .downloaded : .available(canDownload)
        if newState != state {
            state = newState
            shownPercent = nil
            configure(for: newState)
        }
        if newState == .loading {
            let percent = Int(((activity?.progress ?? 0) * 100).rounded())
            if percent != shownPercent {
                shownPercent = percent
                item.image = Self.ring(progress: Double(percent) / 100)
                item.accessibilityValue = "\(percent) %"
            }
        }
    }

    private func configure(for state: State) {
        item.primaryAction = nil
        item.menu = nil
        item.isEnabled = true
        item.accessibilityLabel = nil
        item.accessibilityValue = nil
        switch state {
        case let .available(canDownload):
            item.primaryAction = UIAction(title: "Download", image: UIImage(systemName: "arrow.down")) { [weak self] _ in
                self?.onDownload()
            }
            item.isEnabled = canDownload
        case .loading:
            item.primaryAction = UIAction(title: "Stop Download", image: Self.ring(progress: 0)) { [weak self] _ in
                self?.onStop()
            }
        case .downloaded:
            item.image = UIImage(systemName: "arrow.down.circle.fill")
            item.accessibilityLabel = "Downloaded"
            item.menu = UIMenu(
                title: "Renew to keep this download from Videos or remove it from your iPhone.",
                children: [
                    UIAction(title: "Download Again to Renew", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
                        self?.onRenew()
                    },
                    UIAction(title: "Remove Download", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                        self?.onRemove()
                    }
                ]
            )
        }
    }

    /// A ring the size of a bar symbol, filled to `progress` around a stop
    /// symbol in its middle, as a template image the bar tints like its other
    /// symbols; the unfilled track is drawn at 35 % opacity.
    private static func ring(progress: Double) -> UIImage {
        // As large as a circle symbol in the bar, like the other buttons.
        let circle = UIImage(systemName: "circle", withConfiguration: UIImage.SymbolConfiguration(textStyle: .body, scale: .large))
        let diameter = ceil(circle.map { min($0.size.width, $0.size.height) } ?? 26)
        let size = CGSize(width: diameter, height: diameter)
        let lineWidth: CGFloat = 2.5
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = size.width / 2 - lineWidth / 2
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let track = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            track.lineWidth = lineWidth
            UIColor.black.withAlphaComponent(0.35).setStroke()
            track.stroke()

            if progress > 0 {
                // From the top, clockwise.
                let fill = UIBezierPath(
                    arcCenter: center,
                    radius: radius,
                    startAngle: -.pi / 2,
                    endAngle: -.pi / 2 + .pi * 2 * min(progress, 1),
                    clockwise: true
                )
                fill.lineWidth = lineWidth
                fill.lineCapStyle = .round
                UIColor.black.setStroke()
                fill.stroke()
            }

            let stop = UIImage(systemName: "stop.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: diameter * 0.38, weight: .bold))
            if let stop {
                stop.withTintColor(.black).draw(at: CGPoint(x: center.x - stop.size.width / 2, y: center.y - stop.size.height / 2))
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}

/// The detail screen's collection view. At the top, a downward drag does not
/// scroll: the scroll view's pan does not begin, so the zoom transition's
/// swipe takes the touch and dismisses the screen, like the TV app. Scrolling
/// up from the top, and the bounce when the page arrives at the top with
/// momentum, work as usual.
private final class DetailCollectionView: UICollectionView {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            let atTop = contentOffset.y <= -adjustedContentInset.top + 0.5
            let velocity = panGestureRecognizer.velocity(in: self)
            if atTop, velocity.y > 0, velocity.y > abs(velocity.x) {
                return false
            }
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

/// The artwork layer: the stage at the top edge with the 16:9 thumbnail
/// centered in it, on black below. As the collection view's background view
/// it stays in place; it lays out only when its size changes.
private final class DetailArtworkView: UIView {
    private let stage = UIView()
    private let imageView = UIImageView()

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
        let maxPixelWidth = ArtworkQuality.hero.displayWidth * traitCollection.displayScale
        if let cached = ArtworkLoader.cachedImage(for: candidates, maxPixelWidth: maxPixelWidth) {
            show(cached)
            return
        }
        loadTask = Task { [weak self] in
            let image = await ArtworkLoader.firstImage(
                from: candidates,
                requiresSixteenByNine: video.source == .youtube,
                maxPixelWidth: maxPixelWidth
            )
            guard !Task.isCancelled, let self else { return }
            // An upgrade that fails keeps the image already shown.
            if image != nil || self.imageView.image == nil {
                self.show(image)
            }
        }
    }

    /// Shows `image`, cross-dissolving when it replaces one already shown.
    private func show(_ image: UIImage?) {
        guard imageView.image != nil, image != nil else {
            imageView.image = image
            return
        }
        UIView.transition(with: imageView, duration: 0.25, options: .transitionCrossDissolve) {
            self.imageView.image = image
        }
    }
}

/// The Up Next shelf's black background.
private final class DetailShelfBackground: UICollectionReusableView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}
