import SwiftUI
import UIKit

/// The shape of the detail screen's hero: 2:3, with the 16:9 thumbnail
/// centered in it.
enum DetailStage {
    /// The hero is this many times as tall as it is wide.
    static let heightRatio: CGFloat = 1.5
    /// Where the centered 16:9 thumbnail ends, as a fraction of the hero height.
    static let thumbnailBottom: CGFloat = 0.5 + (9.0 / 16.0) / heightRatio / 2

    /// The hero's height for a width, on whole pixels, so its lower edge
    /// meets the shelf without a half-covered pixel row.
    static func height(forWidth width: CGFloat, scale: CGFloat) -> CGFloat {
        let scale = max(scale, 1)
        return (width * heightRatio * scale).rounded() / scale
    }
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

    private var content: DetailCollection
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private lazy var menus = VideoContextMenus(library: content.library, downloads: content.downloads, presenter: self)
    private var shownRelated: [Video] = []

    /// The artwork layer, a plain static UIKit view.
    /// TEST: light blue, no image yet, while the base is checked for smooth scrolling.
    private let artworkStage = UIView()

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

        artworkStage.backgroundColor = UIColor(red: 0.72, green: 0.84, blue: 1, alpha: 1)
        view.addSubview(artworkStage)

        collectionView.frame = view.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Clear, so the artwork layer shows through the hero.
        collectionView.backgroundColor = .clear
        // The hero starts under the navigation bar; the bottom is inset by hand.
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.delegate = self
        view.addSubview(collectionView)

        configureDataSource()
        applySnapshot(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Only when the screen's size changes, never per scroll frame.
        let width = view.bounds.width
        let stage = CGRect(
            x: 0,
            y: 0,
            width: width,
            height: DetailStage.height(forWidth: width, scale: traitCollection.displayScale)
        )
        if artworkStage.frame != stage {
            artworkStage.frame = stage
        }
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

    /// Only the shelf needs a snapshot.
    func update(content newContent: DetailCollection) {
        content = newContent
        guard isViewLoaded else { return }
        applySnapshot(animated: view.window != nil)
    }

    // MARK: - Layout

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            switch self?.dataSource?.sectionIdentifier(for: index) {
            case .hero:
                return DetailCollectionController.heroSection(height: DetailStage.height(
                    forWidth: environment.container.effectiveContentSize.width,
                    scale: environment.traitCollection.displayScale
                ))
            case .upNext:
                return DetailCollectionController.shelfSection()
            case nil:
                return nil
            }
        }
        return layout
    }

    /// A fixed height, so the hero is never measured again while scrolling.
    private static func heroSection(height: CGFloat) -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height))
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
        return section
    }

    // MARK: - Cells

    private func configureDataSource() {
        let heroRegistration = UICollectionView.CellRegistration<DetailHeroCell, Item> { _, _, _ in }
        let videoRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Item> { [weak self] cell, _, item in
            MainActor.assumeIsolated {
                self?.configureVideo(cell, for: item)
            }
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { header, _, _ in
            MainActor.assumeIsolated {
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

/// The hero's cell. TEST: a static, empty UIKit cell of the hero's fixed
/// height, while the base is checked for smooth scrolling.
private final class DetailHeroCell: UICollectionViewCell {}
