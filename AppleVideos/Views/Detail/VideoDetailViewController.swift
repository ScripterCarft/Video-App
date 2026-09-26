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
final class VideoDetailViewController: VideoCollectionViewController, RoutedScreen {
    /// Opens a video from Up Next; the view to zoom from is looked up when
    /// the zoom needs it.
    typealias OpenAction = @MainActor (VideoRoute, @escaping @MainActor () -> UIView?) -> Void

    enum Section: Hashable {
        case stage
        case upNext
    }

    enum Item: Hashable {
        case stage
        case loadingRelated
        case video(String)
    }

    private static let cardWidth: CGFloat = 272
    private static let shelfBackgroundKind = "detail-shelf-background"

    let route: VideoRoute
    var appRoute: AppRoute? { .video(route) }
    private let onOpen: OpenAction

    private var model: VideoDetailModel?
    private var loadTask: Task<Void, Never>?
    private var shownRelated: [Video] = []
    private var shownRelatedLoading = false
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private lazy var collectionView = DetailCollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private let artwork = DetailArtworkView()
    private let downloadButton = DownloadBarButton()

    init(route: VideoRoute, library: LibraryStore, onOpen: @escaping OpenAction) {
        self.route = route
        self.onOpen = onOpen
        super.init(library: library)
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
        configureArtworkPrefetching(in: collectionView)
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
        // The bar's scroll edge effect follows the page. (Its white buttons
        // come from VideoNavigationController.)
        setContentScrollView(collectionView, for: .top)
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
        let isLoading = !model.relatedLoadFinished
        if related != shownRelated || isLoading != shownRelatedLoading {
            applySnapshot(related: related, isLoading: isLoading,
                          animated: view.window != nil && !UIAccessibility.isReduceMotionEnabled)
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
                let section: NSCollectionLayoutSection
                if self?.shownRelatedLoading == true {
                    // Just a header while loading: no fake cards or reserved
                    // shelf-sized gap. Fixed height avoids self-sizing loops.
                    let height = VideoCells.fittingHeight(
                        key: "up-next-loading", width: environment.container.effectiveContentSize.width,
                        traits: environment.traitCollection
                    ) { VideoCells.headerConfiguration(title: "Up Next", topSpacing: 14) }
                    section = VideoDetailViewController.stageSection(height: height)
                } else {
                    section = VideoCells.shelfSection(
                        cardWidth: VideoDetailViewController.cardWidth,
                        headerTopSpacing: 14,
                        environment: environment
                    )
                }
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
        let loadingRegistration = UICollectionView.CellRegistration<UpNextHeaderCell, Item> { cell, _, _ in
            cell.configure(isLoading: true)
        }
        let videoRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Item> { [weak self] cell, _, item in
            MainActor.assumeIsolated {
                guard case let .video(id) = item,
                      let video = self?.shownRelated.first(where: { $0.id == id })
                else { return }
                cell.contentConfiguration = VideoCardConfiguration(video: video)
            }
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<UpNextHeaderCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { header, _, _ in
            MainActor.assumeIsolated {
                header.configure(isLoading: false)
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            if item == .stage {
                return collectionView.dequeueConfiguredReusableCell(using: stageRegistration, for: indexPath, item: item)
            }
            if item == .loadingRelated {
                return collectionView.dequeueConfiguredReusableCell(using: loadingRegistration, for: indexPath, item: item)
            }
            return collectionView.dequeueConfiguredReusableCell(using: videoRegistration, for: indexPath, item: item)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    private func applySnapshot(related: [Video], isLoading: Bool = false, animated: Bool) {
        shownRelated = related
        shownRelatedLoading = isLoading
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.stage])
        snapshot.appendItems([.stage], toSection: .stage)
        if isLoading {
            snapshot.appendSections([.upNext])
            snapshot.appendItems([.loadingRelated], toSection: .upNext)
        } else if !related.isEmpty {
            snapshot.appendSections([.upNext])
            // Unique IDs: the data source requires them.
            var seen = Set<String>()
            let ids = related.map(\.id).filter { seen.insert($0).inserted }
            snapshot.appendItems(ids.map { .video($0) }, toSection: .upNext)
        }
        cancelPendingArtworkPrefetches()
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    // MARK: - Selection and menus

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        if case .video? = dataSource.itemIdentifier(for: indexPath) { return true }
        return false
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case let .video(id) = item,
              let video = shownRelated.first(where: { $0.id == id })
        else { return }
        onOpen(VideoRoute(video: video)) { [weak self] in
            guard let self,
                  let indexPath = self.dataSource.indexPath(for: item),
                  let cell = self.collectionView.cellForItem(at: indexPath)
            else { return nil }
            return VideoCells.zoomSource(of: cell)
        }
    }

    /// Up Next's cards have the context menu; the stage has none.
    override func video(at indexPath: IndexPath) -> Video? {
        guard case let .video(id)? = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return shownRelated.first { $0.id == id }
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
