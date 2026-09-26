import UIKit

/// Explore as a UIKit screen: topic tiles in two columns, each opening that
/// topic's search results, and the trending videos as full-width cards.
final class ExploreViewController: UIViewController, UICollectionViewDelegate {
    private enum Section: Hashable {
        case topics
        case trending
    }

    private enum Item: Hashable {
        case topic(String)
        case video(String)
    }

    struct Topic {
        let title: String
        let systemImage: String
        let color: UIColor
    }

    static let topics = [
        Topic(title: "Technology", systemImage: "cpu", color: .systemBlue),
        Topic(title: "Film", systemImage: "film.stack", color: .systemIndigo),
        Topic(title: "Science", systemImage: "atom", color: .systemTeal),
        Topic(title: "Music", systemImage: "music.note", color: .systemPink),
        Topic(title: "Gaming", systemImage: "gamecontroller", color: .systemPurple),
        Topic(title: "Learning", systemImage: "graduationcap", color: .systemOrange)
    ]

    private static let trendingSection = "trending"
    private static let tileHeight: CGFloat = 74

    private let library: LibraryStore
    private let navigator: VideoNavigator
    private let trending = Video.curated
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private lazy var menus = VideoContextMenus(library: library, downloads: DownloadManager.shared, presenter: self)

    init(library: LibraryStore, navigator: VideoNavigator) {
        self.library = library
        self.navigator = navigator
        super.init(nibName: nil, bundle: nil)
        title = "Explore"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func loadView() {
        view = collectionView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        configureDataSource()

        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.topics, .trending])
        snapshot.appendItems(Self.topics.map { .topic($0.title) }, toSection: .topics)
        snapshot.appendItems(trending.map { .video($0.id) }, toSection: .trending)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The app's tint again after the white of the detail screen.
        navigationController?.navigationBar.tintColor = nil
    }

    // MARK: - Layout

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.interSectionSpacing = 12
        return UICollectionViewCompositionalLayout(
            sectionProvider: { [weak self] index, environment in
                guard let section = self?.dataSource?.sectionIdentifier(for: index) else { return nil }
                switch section {
                case .topics:
                    return ExploreViewController.topicSection(traits: environment.traitCollection)
                case .trending:
                    let section = VideoCells.listSection(
                        containerWidth: environment.container.effectiveContentSize.width,
                        traits: environment.traitCollection
                    )
                    section.boundarySupplementaryItems = [
                        VideoCells.header(hasSubtitle: true, topSpacing: 16, traits: environment.traitCollection)
                    ]
                    section.contentInsets.top = 14
                    section.interGroupSpacing = 14
                    return section
                }
            },
            configuration: configuration
        )
    }

    /// Two columns of tiles of fixed height, 12 points apart.
    private static func topicSection(traits: UITraitCollection) -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(0.5),
            heightDimension: .fractionalHeight(1)
        ))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(tileHeight)),
            repeatingSubitem: item,
            count: 2
        )
        group.interItemSpacing = .fixed(12)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 12
        section.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 0, trailing: 16)
        section.supplementaryContentInsetsReference = .none
        section.boundarySupplementaryItems = [VideoCells.header(hasSubtitle: true, topSpacing: 16, traits: traits)]
        return section
    }

    // MARK: - Cells

    private func configureDataSource() {
        let topicRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> { cell, _, title in
            MainActor.assumeIsolated {
                guard let topic = ExploreViewController.topics.first(where: { $0.title == title }) else { return }
                cell.contentConfiguration = ExploreViewController.tileConfiguration(for: topic)
                cell.backgroundConfiguration = ExploreViewController.tileBackground(for: topic)
            }
        }
        let videoRegistration = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, _, id in
            MainActor.assumeIsolated {
                guard let video = self?.trending.first(where: { $0.id == id }) else { return }
                cell.contentConfiguration = VideoCardConfiguration(video: video, quality: .search)
            }
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            MainActor.assumeIsolated {
                switch self?.dataSource.sectionIdentifier(for: indexPath.section) {
                case .topics:
                    header.contentConfiguration = VideoCells.headerConfiguration(
                        title: "Browse Topics",
                        subtitle: "Find something worth watching",
                        topSpacing: 16
                    )
                case .trending:
                    header.contentConfiguration = VideoCells.headerConfiguration(
                        title: "Trending Now",
                        subtitle: "A first editorial selection",
                        topSpacing: 16
                    )
                case nil:
                    break
                }
            }
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case let .topic(title):
                collectionView.dequeueConfiguredReusableCell(using: topicRegistration, for: indexPath, item: title)
            case let .video(id):
                collectionView.dequeueConfiguredReusableCell(using: videoRegistration, for: indexPath, item: id)
            }
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    /// The topic's symbol and title in white, headline.
    private static func tileConfiguration(for topic: Topic) -> UIListContentConfiguration {
        var configuration = UIListContentConfiguration.cell()
        configuration.image = UIImage(systemName: topic.systemImage)
        configuration.imageProperties.tintColor = .white
        configuration.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .headline)
        configuration.text = topic.title
        configuration.textProperties.font = .preferredFont(forTextStyle: .headline)
        configuration.textProperties.color = .white
        configuration.textProperties.numberOfLines = 1
        configuration.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        return configuration
    }

    /// The topic's color as a rounded gradient, lighter at the top, like
    /// SwiftUI's `Color.gradient`.
    private static func tileBackground(for topic: Topic) -> UIBackgroundConfiguration {
        var background = UIBackgroundConfiguration.clear()
        background.customView = TileGradientView(color: topic.color)
        background.cornerRadius = 18
        return background
    }

    // MARK: - Selection

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        switch dataSource.itemIdentifier(for: indexPath) {
        case let .topic(title):
            navigator.show(.topic(title))
        case let .video(id):
            guard let video = trending.first(where: { $0.id == id }) else { return }
            navigator.open(VideoRoute(video: video, section: Self.trendingSection)) { [weak self] in
                guard let self,
                      let indexPath = self.dataSource.indexPath(for: .video(id)),
                      let cell = self.collectionView.cellForItem(at: indexPath)
                else { return nil }
                return VideoCells.zoomSource(of: cell)
            }
        case nil:
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
              case let .video(id)? = dataSource.itemIdentifier(for: indexPath),
              let video = trending.first(where: { $0.id == id })
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

/// A topic tile's gradient: the color, slightly lighter at the top.
private final class TileGradientView: UIView {
    private let color: UIColor

    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    init(color: UIColor) {
        self.color = color
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// System colors differ between light and dark; UIKit tracks the traits
    /// read here and calls this again when they change.
    override func updateProperties() {
        super.updateProperties()
        let resolved = color.resolvedColor(with: traitCollection)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        resolved.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let lighter = UIColor(hue: hue, saturation: saturation * 0.85, brightness: min(brightness * 1.12, 1), alpha: alpha)
        (layer as? CAGradientLayer)?.colors = [lighter.cgColor, resolved.cgColor]
    }
}
