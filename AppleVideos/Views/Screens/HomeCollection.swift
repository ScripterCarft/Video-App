import SwiftUI
import UIKit

/// Home as one collection view with a compositional layout, the way Apple
/// builds App Store–style pages: the featured video, shelves as horizontally
/// scrolling (orthogonal) sections and the Spotlight card. Cells show the
/// SwiftUI cards through `UIHostingConfiguration`; a diffable data source
/// animates changes. The collection view owns the context menus, so a card
/// removed from its menu leaves once the menu has closed, as in the TV app.
struct HomeCollection: UIViewControllerRepresentable {
    struct Shelf {
        let id: String
        let title: String
        let subtitle: String
        let videos: [Video]
    }

    let featured: Video
    let shelves: [Shelf]
    let transition: Namespace.ID
    let library: LibraryStore
    let downloads: DownloadManager
    let playback: PlaybackStarter
    let onOpen: (VideoRoute) -> Void

    func makeUIViewController(context: Context) -> HomeCollectionController {
        HomeCollectionController(content: self)
    }

    func updateUIViewController(_ controller: HomeCollectionController, context: Context) {
        controller.update(content: self)
    }
}

final class HomeCollectionController: UIViewController, UICollectionViewDelegate {
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

    private static let cardWidth: CGFloat = 272
    private static let spotlightTitle = "Apple Videos Spotlight"
    private static let spotlightSubtitle = "Beautiful stories, selected by hand"

    private var content: HomeCollection
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private lazy var menus = VideoContextMenus(library: content.library, downloads: content.downloads, presenter: self)

    init(content: HomeCollection) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.frame = view.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        view.addSubview(collectionView)
        configureDataSource()
        applySnapshot(reconfiguring: [], animated: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The navigation bar follows this scroll view for its title and its
        // scroll edge effect.
        var host: UIViewController = self
        while let parent = host.parent, !(parent is UINavigationController) {
            host = parent
        }
        host.setContentScrollView(collectionView, for: .top)
    }

    /// Takes new data from SwiftUI; changed cards are reconfigured in place,
    /// added and removed ones animate.
    func update(content newContent: HomeCollection) {
        var changed: [Item] = []
        for shelf in newContent.shelves {
            let old = content.shelves.first { $0.id == shelf.id }?.videos ?? []
            for video in shelf.videos where old.contains(where: { $0.id == video.id && $0 != video }) {
                changed.append(.video(shelf: shelf.id, id: video.id))
            }
        }
        content = newContent
        guard isViewLoaded else { return }
        applySnapshot(reconfiguring: changed, animated: view.window != nil)
    }

    // MARK: - Layout

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.interSectionSpacing = 30
        return UICollectionViewCompositionalLayout(
            sectionProvider: { [weak self] index, _ in
                guard let section = self?.dataSource?.sectionIdentifier(for: index) else { return nil }
                switch section {
                case .featured:
                    return HomeCollectionController.fullWidthSection(withHeader: false)
                case .shelf:
                    return HomeCollectionController.shelfSection()
                case .spotlight:
                    return HomeCollectionController.fullWidthSection(withHeader: true)
                }
            },
            configuration: configuration
        )
    }

    private static func header() -> NSCollectionLayoutBoundarySupplementaryItem {
        NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(52)),
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
    }

    private static func fullWidthSection(withHeader: Bool) -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(400))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
        let section = NSCollectionLayoutSection(group: group)
        if withHeader {
            section.boundarySupplementaryItems = [header()]
            section.interGroupSpacing = 14
            section.contentInsets.top = 14
        }
        return section
    }

    /// A shelf scrolls sideways and stops at a card's leading edge, like the
    /// App Store and the TV app.
    private static func shelfSection() -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(260))
        let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(cardWidth), heightDimension: .estimated(260))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [NSCollectionLayoutItem(layoutSize: itemSize)])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
        section.interGroupSpacing = 14
        section.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 0, trailing: 16)
        // The header spans the full width; its SwiftUI content has its own margins.
        section.supplementaryContentInsetsReference = .none
        section.boundarySupplementaryItems = [header()]
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
        let library = content.library
        let downloads = content.downloads
        let transition = content.transition

        switch item {
        case .featured:
            let featured = content.featured
            let playback = content.playback
            cell.contentConfiguration = UIHostingConfiguration {
                HomeFeaturedCard(video: featured, playback: playback)
                    .matchedTransitionSource(id: VideoRoute(video: featured, section: "featured").transitionID, in: transition)
                    .environment(library)
                    .environment(downloads)
            }
            .margins(.all, 0)

        case let .video(shelf, id):
            guard let video = video(in: shelf, id: id) else { return }
            VideoCells.configure(
                cell,
                video: video,
                compact: true,
                width: Self.cardWidth,
                route: VideoRoute(video: video, section: shelf),
                transition: transition,
                library: library,
                downloads: downloads
            )

        case .spotlight:
            cell.contentConfiguration = UIHostingConfiguration {
                HomeSpotlightCard()
            }
            .margins(.all, 0)
        }
    }

    private func configure(_ header: UICollectionViewCell, at indexPath: IndexPath) {
        let title: String
        let subtitle: String
        switch dataSource.sectionIdentifier(for: indexPath.section) {
        case let .shelf(id):
            guard let shelf = content.shelves.first(where: { $0.id == id }) else { return }
            title = shelf.title
            subtitle = shelf.subtitle
        case .spotlight:
            title = Self.spotlightTitle
            subtitle = Self.spotlightSubtitle
        default:
            return
        }
        header.contentConfiguration = UIHostingConfiguration {
            SectionHeader(title: title, subtitle: subtitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
        }
        .margins(.all, 0)
    }

    private func video(in shelf: String, id: String) -> Video? {
        content.shelves.first { $0.id == shelf }?.videos.first { $0.id == id }
    }

    private func applySnapshot(reconfiguring changed: [Item], animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.featured])
        snapshot.appendItems([.featured], toSection: .featured)
        for shelf in content.shelves where !shelf.videos.isEmpty {
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

    // MARK: - Selection

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath) != .spotlight
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        switch dataSource.itemIdentifier(for: indexPath) {
        case .featured:
            content.onOpen(VideoRoute(video: content.featured, section: "featured"))
        case let .video(shelf, id):
            guard let video = video(in: shelf, id: id) else { return }
            content.onOpen(VideoRoute(video: video, section: shelf))
        default:
            break
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

/// The featured video at the top of Home: artwork, title and a Play button.
/// Tapping anywhere else opens its detail screen (the collection view's
/// selection).
struct HomeFeaturedCard: View {
    let video: Video
    let playback: PlaybackStarter

    @Environment(LibraryStore.self) private var library

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VideoHeroArtwork(video: video, cornerRadius: 22, stageAspectRatio: 2.0 / 3.0)
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.15), .black.opacity(0.88)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            VStack(alignment: .leading, spacing: 10) {
                Text("FEATURED")
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.72))
                Text(video.title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                HStack(alignment: .center) {
                    Button {
                        if playback.isPreparing {
                            playback.cancel()
                        } else {
                            playback.start(video, description: video.descriptionText, library: library)
                        }
                    } label: {
                        PlayButtonContent(
                            progress: library.progress(for: video),
                            isPreparing: playback.isPreparing
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 9)
                        .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if let duration = video.duration {
                        Text(duration)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.68), in: Capsule())
                    }
                }
            }
            .padding(22)
        }
        .padding(.horizontal, 16)
    }
}

/// The Spotlight card at the bottom of Home.
struct HomeSpotlightCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles.tv.fill")
                .font(.system(size: 40))
                .symbolRenderingMode(.hierarchical)
            Text("A calmer way to watch")
                .font(.title2.bold())
            Text("No noisy counters or clutter. Just videos, collections, and your library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        // An opaque system color looks like the material here and costs nothing to draw.
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
    }
}
