import SwiftUI
import UIKit

/// The detail screen's page color, dark gray like the TV app's.
enum DetailBackground {
    static var uiColor: UIColor { UIColor(white: 0.09, alpha: 1) }
    static var color: Color { Color(uiColor: uiColor) }
}

/// The detail screen in two layers, like the TV app's: the artwork stands
/// still at the top edge, and a collection view scrolls over it with the
/// title, buttons and description first, then the Up Next shelf of related
/// videos with the shared cell and context menu. Pulling down at the top
/// enlarges the artwork to fill the gap.
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
    /// The artwork stage and the hero cell are 2:3, as tall as 1.5 × the width.
    private static let stageHeightRatio: CGFloat = 1.5
    private static let sectionBackgroundKind = "detail-section-background"

    private var content: DetailCollection
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    /// The artwork layer behind the collection view. Only its transform
    /// changes while scrolling, so SwiftUI never redraws it for that.
    private lazy var artworkHost = UIHostingController(rootView: DetailArtwork(video: content.model.video))
    private lazy var menus = VideoContextMenus(library: content.library, downloads: content.downloads, presenter: self)
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
        view.backgroundColor = DetailBackground.uiColor

        // The artwork reaches the top edge, under the status and navigation bars.
        artworkHost.safeAreaRegions = []
        artworkHost.view.backgroundColor = .clear
        addChild(artworkHost)
        view.addSubview(artworkHost.view)
        artworkHost.didMove(toParent: self)

        collectionView.frame = view.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Clear, so the artwork shows through the hero cell; the Up Next
        // section has its own background.
        collectionView.backgroundColor = .clear
        // The hero starts under the navigation bar; the bottom is inset by hand.
        collectionView.contentInsetAdjustmentBehavior = .never
        // Pulling down at the top always works, even when the page fits.
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        view.addSubview(collectionView)
        configureDataSource()
        applySnapshot(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let height = width * Self.stageHeightRatio
        // Bounds and center, not frame: the view carries a transform.
        artworkHost.view.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        artworkHost.view.center = CGPoint(x: width / 2, y: height / 2)
        updateArtworkStretch()
    }

    /// Pulled down past the top, the artwork grows from its top edge so it
    /// always reaches the hero, which the scroll view moves down. Scrolled
    /// up, the artwork stands still and the page slides over it.
    private func updateArtworkStretch() {
        let height = artworkHost.view.bounds.height
        let pull = max(0, -(collectionView.contentOffset.y + collectionView.adjustedContentInset.top))
        guard height > 0, pull > 0 else {
            artworkHost.view.transform = .identity
            return
        }
        let scale = (height + pull) / height
        // Scaling around the center moves the top up by pull / 2; move it back.
        artworkHost.view.transform = CGAffineTransform(translationX: 0, y: pull / 2)
            .scaledBy(x: scale, y: scale)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        updateArtworkStretch()
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

    // MARK: - Layout

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        // No space between sections: the artwork would show through a gap.
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
        layout.register(DetailSectionBackground.self, forDecorationViewOfKind: Self.sectionBackgroundKind)
        return layout
    }

    /// The hero has a fixed height, exactly over the artwork stage, so it is
    /// never measured again while scrolling or bouncing.
    private static func heroSection() -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .fractionalWidth(stageHeightRatio))
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
        // Opaque, so the artwork does not show behind the shelf once the page
        // has slid over it.
        section.decorationItems = [NSCollectionLayoutDecorationItem.background(elementKind: sectionBackgroundKind)]
        return section
    }

    // MARK: - Cells

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Item> { [weak self] cell, _, item in
            MainActor.assumeIsolated {
                self?.configure(cell, for: item)
            }
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { header, _, _ in
            MainActor.assumeIsolated {
                // The space above the title belongs to the opaque header, so
                // no gap between hero and shelf lets the artwork through.
                header.backgroundColor = DetailBackground.uiColor
                header.contentConfiguration = UIHostingConfiguration {
                    SectionHeader(title: "Up Next")
                        .padding(.horizontal, 16)
                        .padding(.top, 26)
                }
                .margins(.all, 0)
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    private func configure(_ cell: UICollectionViewCell, for item: Item) {
        let library = content.library
        let downloads = content.downloads

        switch item {
        case .hero:
            let model = content.model
            let playback = content.playback
            let onShowDescription = content.onShowDescription
            let onFeedback = content.onFeedback
            cell.contentConfiguration = UIHostingConfiguration {
                DetailHero(
                    model: model,
                    playback: playback,
                    onShowDescription: onShowDescription,
                    onFeedback: onFeedback
                )
                .environment(library)
                .environment(downloads)
                // The cell reaches under the bars; its content must not be
                // pushed down or laid out again as that overlap changes.
                .ignoresSafeArea()
            }
            .margins(.all, 0)

        case let .video(id):
            guard let video = shownRelated.first(where: { $0.id == id }) else { return }
            VideoCells.configure(
                cell,
                video: video,
                compact: true,
                width: Self.cardWidth,
                route: VideoRoute(video: video, section: Self.shelfID),
                transition: content.transition,
                library: library,
                downloads: downloads
            )
        }
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

/// The artwork layer: the 16:9 thumbnail on its dark 2:3 stage.
private struct DetailArtwork: View {
    let video: Video

    var body: some View {
        VideoHeroArtwork(video: video, stageAspectRatio: 2.0 / 3.0)
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea()
    }
}

/// The Up Next section's opaque background, in the page color.
private final class DetailSectionBackground: UICollectionReusableView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DetailBackground.uiColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}
