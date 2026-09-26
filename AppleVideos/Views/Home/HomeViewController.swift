import UIKit

/// Home as a UIKit screen: one collection view with a compositional layout,
/// the way Apple builds App Store–style pages. The featured video, shelves
/// of UIKit video cards (`VideoCardConfiguration`) as horizontally scrolling
/// sections, and the Spotlight card.
///
/// The shelves come from the observable library, read in
/// `updateProperties()`: UIKit tracks that read and updates Home when the
/// Watchlist changes. The collection view owns the context menus, so a card
/// removed from its menu leaves once the menu has closed.
final class HomeViewController: UIViewController, UICollectionViewDelegate {
    enum Section: Hashable {
        case featured
        case shelf(String)
        case spotlight
    }

    enum Item: Hashable {
        case featured
        case video(shelf: String, id: String)
        case spotlight
    }

    private struct Shelf: Equatable {
        let id: String
        let title: String
        let videos: [Video]
    }

    private static let cardWidth: CGFloat = 272
    private static let spotlightTitle = "Apple Videos Spotlight"

    private let library: LibraryStore
    private let downloads: DownloadManager
    /// Starts the featured video from its Play button.
    private let playback = PlaybackStarter()
    private let navigator: VideoNavigator
    /// The embedded player or the Use Mobile Data alert, while shown.
    private weak var fallbackController: UIViewController?
    private weak var mobileDataAlert: UIAlertController?
    private let featured = Video.curated[0]
    private let picks = Array(Video.curated.dropFirst())

    private var shelves: [Shelf] = []
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private lazy var menus = VideoContextMenus(library: library, downloads: downloads, presenter: self)

    init(library: LibraryStore, downloads: DownloadManager, navigator: VideoNavigator) {
        self.library = library
        self.downloads = downloads
        self.navigator = navigator
        super.init(nibName: nil, bundle: nil)
        title = "Home"
        // The large title sits in the bar at the leading edge, like the TV app.
        navigationItem.largeTitleDisplayMode = .inline
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func loadView() {
        // The collection view is the screen, so the navigation bar follows it
        // for its title and scroll edge effect by itself.
        view = collectionView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        configureDataSource()

        // The featured video has a Play button right on Home.
        let featured = featured
        Task {
            await NativePlayback.prefetch(featured)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The app's tint again after the white of the detail screen.
        navigationController?.navigationBar.tintColor = nil
    }

    /// Leaving Home, for another tab or a detail screen, cancels a start that
    /// is still resolving. The player covering Home does not.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let leftHome = tabBarController?.selectedViewController !== navigationController
            || navigationController?.topViewController !== self
        if leftHome, playback.isPreparing {
            playback.cancel()
        }
    }

    /// Reads the Watchlist and the Play button's outcome; UIKit tracks the
    /// reads and calls this again when they change. Changed cards are
    /// reconfigured in place, added and removed ones animate.
    override func updateProperties() {
        super.updateProperties()
        presentPlaybackOutcome()
        let newShelves = [
            Shelf(id: "continue", title: "Continue Watching", videos: library.watchlist),
            Shelf(id: "picks", title: "Made for Tonight", videos: picks)
        ]
        guard newShelves != shelves || dataSource.snapshot().numberOfItems == 0 else { return }

        var changed: [Item] = []
        for shelf in newShelves {
            let old = shelves.first { $0.id == shelf.id }?.videos ?? []
            for video in shelf.videos where old.contains(where: { $0.id == video.id && $0 != video }) {
                changed.append(.video(shelf: shelf.id, id: video.id))
            }
        }
        let animated = !shelves.isEmpty && view.window != nil
        shelves = newShelves
        applySnapshot(reconfiguring: changed, animated: animated)
    }

    /// Shows what the featured video's Play button reports: the embedded
    /// player when no native stream plays, or the alert when Use Mobile Data
    /// is off. Each is shown once and cleared when it closes.
    private func presentPlaybackOutcome() {
        if let fallback = playback.fallback, fallbackController == nil {
            let controller = EmbeddedPlayerScreen.controller(
                video: fallback.video,
                diagnostic: fallback.diagnostic,
                library: library
            ) { [weak self] in
                self?.playback.fallback = nil
                self?.fallbackController?.presentingViewController?.dismiss(animated: true)
            }
            fallbackController = controller
            (NativePlayback.topViewController() ?? self).present(controller, animated: true)
        }

        if playback.isShowingMobileDataAlert, mobileDataAlert == nil {
            let alert = UIAlertController(
                title: "Mobile Data Is Turned Off",
                message: "Turn on Use Mobile Data in Settings to stream videos over mobile data.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Settings", style: .default) { [weak self] _ in
                self?.playback.isShowingMobileDataAlert = false
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            })
            alert.addAction(UIAlertAction(title: "OK", style: .cancel) { [weak self] _ in
                self?.playback.isShowingMobileDataAlert = false
            })
            mobileDataAlert = alert
            (NativePlayback.topViewController() ?? self).present(alert, animated: true)
        }
    }

    // MARK: - Layout

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.interSectionSpacing = 30
        return UICollectionViewCompositionalLayout(
            sectionProvider: { [weak self] index, environment in
                guard let section = self?.dataSource?.sectionIdentifier(for: index) else { return nil }
                // Full-width cards sit between the screen margins.
                let cardWidth = environment.container.effectiveContentSize.width - 2 * HomeViewController.sideMargin
                switch section {
                case .featured:
                    return HomeViewController.cardSection(height: FeaturedCardConfiguration.height(forWidth: cardWidth))
                case .shelf:
                    return VideoCells.shelfSection(
                        cardWidth: HomeViewController.cardWidth,
                        headerTopSpacing: 0,
                        environment: environment
                    )
                case .spotlight:
                    let section = HomeViewController.cardSection(
                        height: SpotlightCard.height(forWidth: cardWidth, traits: environment.traitCollection)
                    )
                    section.boundarySupplementaryItems = [VideoCells.header(
                        width: environment.container.effectiveContentSize.width,
                        traits: environment.traitCollection
                    )]
                    section.supplementaryContentInsetsReference = .none
                    section.contentInsets.top = 14
                    return section
                }
            },
            configuration: configuration
        )
    }

    private static let sideMargin: CGFloat = 16

    /// One full-width card of fixed `height` between the screen margins.
    /// Sizes are computed, never estimated (see `VideoCells.shelfSection`).
    private static func cardSection(height: CGFloat) -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: sideMargin, bottom: 0, trailing: sideMargin)
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
        ) { [weak self] header, _, indexPath in
            MainActor.assumeIsolated {
                self?.configure(header, at: indexPath)
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
        // Cells are reused across items, so each sets its own background.
        cell.backgroundConfiguration = item == .spotlight ? SpotlightCard.background : nil
        switch item {
        case .featured:
            cell.contentConfiguration = FeaturedCardConfiguration(video: featured, library: library, playback: playback)

        case let .video(shelf, id):
            guard let video = video(in: shelf, id: id) else { return }
            cell.contentConfiguration = VideoCardConfiguration(video: video)

        case .spotlight:
            cell.contentConfiguration = SpotlightCard.configuration()
        }
    }

    /// Section titles only, like Up Next.
    private func configure(_ header: UICollectionViewCell, at indexPath: IndexPath) {
        let title: String
        switch dataSource.sectionIdentifier(for: indexPath.section) {
        case let .shelf(id):
            guard let shelf = shelves.first(where: { $0.id == id }) else { return }
            title = shelf.title
        case .spotlight:
            title = Self.spotlightTitle
        default:
            return
        }
        header.contentConfiguration = VideoCells.headerConfiguration(title: title, topSpacing: 0)
    }

    private func video(in shelf: String, id: String) -> Video? {
        shelves.first { $0.id == shelf }?.videos.first { $0.id == id }
    }

    private func applySnapshot(reconfiguring changed: [Item], animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.featured])
        snapshot.appendItems([.featured], toSection: .featured)
        for shelf in shelves where !shelf.videos.isEmpty {
            snapshot.appendSections([.shelf(shelf.id)])
            snapshot.appendItems(shelf.videos.map { .video(shelf: shelf.id, id: $0.id) }, toSection: .shelf(shelf.id))
        }
        snapshot.appendSections([.spotlight])
        snapshot.appendItems([.spotlight], toSection: .spotlight)

        let existing = Set(dataSource.snapshot().itemIdentifiers)
        let reconfigure = changed.filter { existing.contains($0) && snapshot.indexOfItem($0) != nil }
        if !reconfigure.isEmpty {
            snapshot.reconfigureItems(reconfigure)
        }
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    // MARK: - Opening videos

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath) != .spotlight
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .featured:
            navigator.open(VideoRoute(video: featured, section: "featured"), zoomSource: zoomSource(for: item))
        case let .video(shelf, id):
            guard let video = video(in: shelf, id: id) else { return }
            navigator.open(VideoRoute(video: video, section: shelf), zoomSource: zoomSource(for: item))
        case .spotlight:
            break
        }
    }

    /// The card's artwork (or the whole featured card), looked up when the
    /// zoom needs it, since cells are reused.
    private func zoomSource(for item: Item) -> @MainActor () -> UIView? {
        { [weak self] in
            guard let self,
                  let indexPath = self.dataSource.indexPath(for: item),
                  let cell = self.collectionView.cellForItem(at: indexPath)
            else { return nil }
            return VideoCells.zoomSource(of: cell)
        }
    }

    // MARK: - Context menus

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first,
              case let .video(shelf, id)? = dataSource.itemIdentifier(for: indexPath),
              let video = video(in: shelf, id: id)
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
