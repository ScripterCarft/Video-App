import SwiftUI
import UIKit

/// The shape of the detail screen's artwork stage: 2:3, with the 16:9
/// thumbnail centered in it.
enum DetailStage {
    /// The stage is this many times as tall as it is wide.
    static let heightRatio: CGFloat = 1.5
    /// Where the centered 16:9 thumbnail ends, as a fraction of the stage height.
    static let thumbnailBottom: CGFloat = 0.5 + (9.0 / 16.0) / heightRatio / 2

    /// The stage's height for a width, on whole pixels, so the page's black
    /// meets it without a half-covered pixel row.
    static func height(forWidth width: CGFloat, scale: CGFloat) -> CGFloat {
        let scale = max(scale, 1)
        return (width * heightRatio * scale).rounded() / scale
    }
}

/// The detail screen in two layers. Behind: the artwork stage as the
/// collection view's `backgroundView`, which UIKit keeps in place while the
/// content scrolls. In front: an empty spacer as tall as the stage, then the
/// Up Next shelf on black, starting exactly at the stage's lower edge and
/// sliding over it. Every size is fixed; nothing is measured while scrolling.
struct DetailCollection: UIViewControllerRepresentable {
    let model: VideoDetailModel
    /// The Up Next videos, passed as a value so SwiftUI updates the shelf when they arrive.
    let related: [Video]
    let playback: PlaybackStarter
    let transition: Namespace.ID
    let library: LibraryStore
    let downloads: DownloadManager
    let onShowDescription: () -> Void
    let onFeedback: () -> Void
    let onOpen: (VideoRoute) -> Void

    func makeUIViewController(context: Context) -> DetailCollectionController {
        DetailCollectionController(content: self)
    }

    func updateUIViewController(_ controller: DetailCollectionController, context: Context) {
        controller.update(content: self)
    }
}

final class DetailCollectionController: UIViewController, UICollectionViewDelegate {
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

    private var content: DetailCollection
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private lazy var menus = VideoContextMenus(library: content.library, downloads: content.downloads, presenter: self)
    private let artwork = DetailArtworkView()
    private var shownRelated: [Video] = []

    init(content: DetailCollection) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // The detail screen is always dark, like the TV app's.
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black

        collectionView.frame = view.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .black
        collectionView.backgroundView = artwork
        // The stage starts under the navigation bar; the bottom is inset by hand.
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        view.addSubview(collectionView)

        // Fixed sizes follow the text size; recompute them when it changes.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.collectionView.collectionViewLayout.invalidateLayout()
        }

        artwork.load(content.model.video)
        configureDataSource()
        applySnapshot(animated: false)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        collectionView.contentInset.bottom = view.safeAreaInsets.bottom + 30
        collectionView.verticalScrollIndicatorInsets.top = view.safeAreaInsets.top
        collectionView.verticalScrollIndicatorInsets.bottom = view.safeAreaInsets.bottom
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The navigation bar follows this scroll view for its scroll edge effect.
        var host: UIViewController = self
        while let parent = host.parent, !(parent is UINavigationController) {
            host = parent
        }
        host.setContentScrollView(collectionView, for: .top)
    }

    /// Only the shelf changes after loading.
    func update(content newContent: DetailCollection) {
        content = newContent
        guard isViewLoaded else { return }
        applySnapshot(animated: view.window != nil)
    }

    // MARK: - Layout

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            switch self?.dataSource?.sectionIdentifier(for: index) {
            case .stage:
                return DetailCollectionController.stageSection(height: DetailStage.height(
                    forWidth: environment.container.effectiveContentSize.width,
                    scale: environment.traitCollection.displayScale
                ))
            case .upNext:
                let section = VideoCells.shelfSection(
                    cardWidth: DetailCollectionController.cardWidth,
                    headerTopSpacing: 22,
                    traits: environment.traitCollection
                )
                // The black the page slides over the artwork with.
                section.decorationItems = [
                    NSCollectionLayoutDecorationItem.background(elementKind: DetailCollectionController.shelfBackgroundKind)
                ]
                return section
            case nil:
                return nil
            }
        }
        layout.register(DetailShelfBackground.self, forDecorationViewOfKind: Self.shelfBackgroundKind)
        return layout
    }

    /// A clear spacer exactly over the artwork stage.
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
                self?.configureVideo(cell, for: item)
            }
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { header, _, _ in
            MainActor.assumeIsolated {
                // Opaque: the header slides over the artwork too.
                header.backgroundColor = .black
                header.contentConfiguration = UIHostingConfiguration {
                    SectionHeader(title: "Up Next")
                        .padding(.horizontal, 16)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .margins(.all, 0)
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

    private func configureVideo(_ cell: UICollectionViewCell, for item: Item) {
        guard case let .video(id) = item,
              let video = shownRelated.first(where: { $0.id == id })
        else { return }
        VideoCells.configure(
            cell,
            video: video,
            compact: true,
            width: Self.cardWidth,
            route: VideoRoute(video: video, section: Self.shelfID),
            transition: content.transition,
            library: content.library,
            downloads: content.downloads,
            fixedHeight: true
        )
    }

    private func applySnapshot(animated: Bool) {
        let related = content.related
        let changed = related != shownRelated
        shownRelated = related
        guard changed || dataSource.snapshot().numberOfItems == 0 else { return }

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
        // The shelf arriving is the screen's content loading, not a change
        // to animate (with the animated insertion, the header lay over the
        // cards until the next scroll). Apple's API for loading data in place.
        let shelfArrives = dataSource.snapshot().indexOfSection(.upNext) == nil
        if shelfArrives || !animated {
            dataSource.applySnapshotUsingReloadData(snapshot)
        } else {
            dataSource.apply(snapshot, animatingDifferences: true)
        }
    }

    // MARK: - Selection and menus

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath) != .stage
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard case let .video(id)? = dataSource.itemIdentifier(for: indexPath),
              let video = shownRelated.first(where: { $0.id == id })
        else { return }
        content.onOpen(VideoRoute(video: video, section: Self.shelfID))
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
        return menus.configuration(for: video) { [weak collectionView] in
            collectionView?.cellForItem(at: indexPath)
        }
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
        stage.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let thumbnailHeight = width * 9 / 16
        imageView.frame = CGRect(x: 0, y: (height - thumbnailHeight) / 2, width: width, height: thumbnailHeight)
    }

    private var pendingVideo: Video?

    /// Loads the artwork once, from the shared loader and its cache, as soon
    /// as the view is on screen and knows its display scale.
    func load(_ video: Video) {
        pendingVideo = video
        loadIfPossible()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        loadIfPossible()
    }

    private func loadIfPossible() {
        guard window != nil, let video = pendingVideo else { return }
        pendingVideo = nil
        let candidates = video.artworkCandidates(lowData: NetworkConditions.shared.isConstrained)
        let maxPixelWidth = ArtworkQuality.hero.displayWidth * traitCollection.displayScale
        if let cached = ArtworkLoader.cachedImage(for: candidates, maxPixelWidth: maxPixelWidth) {
            imageView.image = cached
            return
        }
        Task { [weak self] in
            let image = await ArtworkLoader.firstImage(
                from: candidates,
                requiresSixteenByNine: video.source == .youtube,
                maxPixelWidth: maxPixelWidth
            )
            self?.imageView.image = image
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
