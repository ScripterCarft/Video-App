import SwiftUI
import UIKit

/// The shape of the detail screen's artwork stage: 2:3, with the 16:9
/// thumbnail centered in it.
enum DetailStage {
    /// The stage is this many times as tall as it is wide.
    static let heightRatio: CGFloat = 1.5
    /// Where the centered 16:9 thumbnail ends, as a fraction of the stage height.
    static let thumbnailBottom: CGFloat = 0.5 + (9.0 / 16.0) / heightRatio / 2
}

/// The detail screen in two layers, like the TV app's. Behind: the artwork
/// stage, plain UIKit, standing still at the top edge. In front: a clear
/// collection view that scrolls over it, first the hero (the video's info at
/// the bottom of the stage), then the Up Next shelf on black, which starts
/// at the stage's lower edge.
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
        case hero
        case upNext
    }

    enum Item: Hashable {
        case hero
        case video(String)
    }

    private static let cardWidth: CGFloat = 272
    private static let shelfID = "upnext"
    private static let shelfBackgroundKind = "detail-shelf-background"

    private var content: DetailCollection
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private lazy var menus = VideoContextMenus(library: content.library, downloads: content.downloads, presenter: self)
    private var shownRelated: [Video] = []

    /// The artwork layer. UIKit views only, so scrolling over it redraws nothing.
    private let artworkStage = UIView()
    private let artworkView = UIImageView()

    /// The hero's SwiftUI content. A hosting controller rather than a
    /// hosting configuration, so it can opt out of the safe area: a cell
    /// passes on how far it lies under the bars, and SwiftUI laid the hero
    /// out again on every scroll frame.
    private lazy var heroHost: UIHostingController<DetailHeroContent> = {
        let host = UIHostingController(rootView: DetailHeroContent(
            model: content.model,
            playback: content.playback,
            library: content.library,
            downloads: content.downloads,
            onShowDescription: content.onShowDescription,
            onFeedback: content.onFeedback
        ))
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        return host
    }()

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

        // TEST: light blue shows the artwork layer's extent while we tune it.
        artworkStage.backgroundColor = UIColor(red: 0.72, green: 0.84, blue: 1, alpha: 1)
        artworkStage.clipsToBounds = true
        artworkView.contentMode = .scaleAspectFit
        artworkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        artworkStage.addSubview(artworkView)
        view.addSubview(artworkStage)
        loadArtwork()

        collectionView.frame = view.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Clear, so the artwork shows through the hero; the shelf has its own black.
        collectionView.backgroundColor = .clear
        // The hero starts under the navigation bar; the bottom is inset by hand.
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.delegate = self
        view.addSubview(collectionView)

        addChild(heroHost)
        heroHost.didMove(toParent: self)

        configureDataSource()
        applySnapshot(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let stage = CGRect(x: 0, y: 0, width: width, height: width * DetailStage.heightRatio)
        if artworkStage.frame != stage {
            artworkStage.frame = stage
            artworkView.frame = artworkStage.bounds
        }
        updateArtworkVisibility()
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

    /// The hero observes the model itself; only the shelf needs a snapshot.
    func update(content newContent: DetailCollection) {
        content = newContent
        guard isViewLoaded else { return }
        applySnapshot(animated: view.window != nil)
    }

    // MARK: - Artwork

    /// The same candidates, width and cache as the SwiftUI artwork views.
    private func loadArtwork() {
        let video = content.model.video
        let candidates = video.artworkCandidates(lowData: NetworkConditions.shared.isConstrained)
        let maxPixelWidth = ArtworkQuality.hero.displayWidth * traitCollection.displayScale
        if let cached = ArtworkLoader.cachedImage(for: candidates, maxPixelWidth: maxPixelWidth) {
            artworkView.image = cached
            return
        }
        Task { [weak self] in
            let image = await ArtworkLoader.firstImage(
                from: candidates,
                requiresSixteenByNine: video.source == .youtube,
                maxPixelWidth: maxPixelWidth
            )
            self?.artworkView.image = image
        }
    }

    /// Once the page covers the stage completely, it is hidden, so it is not
    /// composited under the black.
    private func updateArtworkVisibility() {
        let covered = collectionView.contentOffset.y >= artworkStage.bounds.height
        if artworkStage.isHidden != covered {
            artworkStage.isHidden = covered
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        updateArtworkVisibility()
    }

    // MARK: - Layout

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        // No space between the sections: the artwork would show through it.
        let layout = UICollectionViewCompositionalLayout { [weak self] index, _ in
            switch self?.dataSource?.sectionIdentifier(for: index) {
            case .hero:
                return DetailCollectionController.heroSection()
            case .upNext:
                return DetailCollectionController.shelfSection()
            case nil:
                return nil
            }
        }
        layout.register(DetailShelfBackground.self, forDecorationViewOfKind: Self.shelfBackgroundKind)
        return layout
    }

    /// Exactly as tall as the artwork stage, fixed, so it is never measured
    /// again while scrolling.
    private static func heroSection() -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .fractionalWidth(DetailStage.heightRatio)
        )
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
        return NSCollectionLayoutSection(group: group)
    }

    private static func shelfSection() -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(260))
        let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(cardWidth), heightDimension: .estimated(260))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [NSCollectionLayoutItem(layoutSize: itemSize)])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
        section.interGroupSpacing = 14
        section.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 0, trailing: 16)
        section.supplementaryContentInsetsReference = .none
        section.boundarySupplementaryItems = [
            NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(40)),
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
        ]
        // The black layer: opaque, so the artwork does not show behind the
        // shelf once the page slides over it.
        section.decorationItems = [NSCollectionLayoutDecorationItem.background(elementKind: shelfBackgroundKind)]
        return section
    }

    // MARK: - Cells

    private func configureDataSource() {
        let heroRegistration = UICollectionView.CellRegistration<DetailHeroCell, Item> { [weak self] cell, _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                cell.embed(self.heroHost.view)
            }
        }
        let videoRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Item> { [weak self] cell, _, item in
            MainActor.assumeIsolated {
                self?.configureVideo(cell, for: item)
            }
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { header, _, _ in
            MainActor.assumeIsolated {
                // Opaque, and the space above the title is part of it, so no
                // gap between hero and shelf lets the artwork through.
                header.backgroundColor = .black
                header.contentConfiguration = UIHostingConfiguration {
                    SectionHeader(title: "Up Next")
                        .padding(.horizontal, 16)
                        .padding(.top, 26)
                }
                .margins(.all, 0)
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            if item == .hero {
                return collectionView.dequeueConfiguredReusableCell(using: heroRegistration, for: indexPath, item: item)
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
            downloads: content.downloads
        )
    }

    private func applySnapshot(animated: Bool) {
        let related = content.related
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.hero])
        snapshot.appendItems([.hero], toSection: .hero)
        if !related.isEmpty {
            snapshot.appendSections([.upNext])
            snapshot.appendItems(related.map { .video($0.id) }, toSection: .upNext)
        }
        let changed = related != shownRelated
        shownRelated = related
        guard changed || dataSource.snapshot().numberOfItems == 0 else { return }
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    // MARK: - Selection and menus

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath) != .hero
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

/// The hero's cell: holds the controller's one hero hosting view.
private final class DetailHeroCell: UICollectionViewCell {
    func embed(_ hostView: UIView) {
        guard hostView.superview !== contentView else { return }
        hostView.removeFromSuperview()
        hostView.frame = contentView.bounds
        hostView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(hostView)
    }
}

/// The hero with the environment it reads, as a hosting controller's root.
struct DetailHeroContent: View {
    let model: VideoDetailModel
    let playback: PlaybackStarter
    let library: LibraryStore
    let downloads: DownloadManager
    let onShowDescription: () -> Void
    let onFeedback: () -> Void

    var body: some View {
        DetailHero(
            model: model,
            playback: playback,
            onShowDescription: onShowDescription,
            onFeedback: onFeedback
        )
        .environment(library)
        .environment(downloads)
    }
}

/// The shelf's black background.
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
