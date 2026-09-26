import UIKit

/// The Library as a UIKit screen: Saved, Downloaded and History in an inset
/// grouped list (Apple's list layout), each with a colored symbol and its
/// count, opening the list of its videos.
final class LibraryViewController: UIViewController, UICollectionViewDelegate {
    private struct Row {
        let list: LibraryList
        let title: String
        let systemImage: String
        let color: UIColor
    }

    private static let rows = [
        Row(list: .saved, title: "Saved", systemImage: "bookmark.fill", color: .systemRed),
        Row(list: .downloaded, title: "Downloaded", systemImage: "arrow.down.circle.fill", color: .systemBlue),
        Row(list: .history, title: "History", systemImage: "clock.fill", color: .systemGray)
    ]

    private let library: LibraryStore
    private let downloads = DownloadManager.shared
    private let navigator: VideoNavigator
    /// The counts shown, to reconfigure only rows whose count changed.
    private var shownSubtitles: [LibraryList: String] = [:]
    private var dataSource: UICollectionViewDiffableDataSource<Int, LibraryList>!
    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: UICollectionViewCompositionalLayout.list(
            using: UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        )
    )

    init(library: LibraryStore, navigator: VideoNavigator) {
        self.library = library
        self.navigator = navigator
        super.init(nibName: nil, bundle: nil)
        title = "Library"
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
        collectionView.delegate = self
        configureDataSource()
        var snapshot = NSDiffableDataSourceSnapshot<Int, LibraryList>()
        snapshot.appendSections([0])
        snapshot.appendItems(Self.rows.map(\.list), toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The app's tint again after the white of the detail screen.
        navigationController?.navigationBar.tintColor = nil
    }

    /// Reads the counts; UIKit tracks the reads and calls this again when
    /// they change, and only rows whose count changed are reconfigured.
    override func updateProperties() {
        super.updateProperties()
        let subtitles = Dictionary(uniqueKeysWithValues: Self.rows.map { ($0.list, subtitle(for: $0.list)) })
        guard subtitles != shownSubtitles else { return }
        let changed = Self.rows.map(\.list).filter { shownSubtitles[$0] != nil && shownSubtitles[$0] != subtitles[$0] }
        shownSubtitles = subtitles
        guard !changed.isEmpty else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(changed)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    /// "1 video", "3 videos" (automatic grammar agreement), or History's
    /// "3 recently watched".
    private func subtitle(for list: LibraryList) -> String {
        switch list {
        case .saved:
            String(AttributedString(localized: "^[\(library.savedVideos.count) video](inflect: true)").characters)
        case .downloaded:
            String(AttributedString(localized: "^[\(downloads.videos.count) video](inflect: true)").characters)
        case .history:
            "\(library.recentlyWatched.count) recently watched"
        }
    }

    private func configureDataSource() {
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, LibraryList> { [weak self] cell, _, list in
            MainActor.assumeIsolated {
                guard let row = LibraryViewController.rows.first(where: { $0.list == list }) else { return }
                let subtitle = self?.shownSubtitles[list] ?? self?.subtitle(for: list)
                cell.accessories = [.disclosureIndicator()]
                // The symbol's tile is drawn for the cell's traits, again
                // when they change (light and dark).
                cell.configurationUpdateHandler = { cell, state in
                    var content = UIListContentConfiguration.subtitleCell()
                    content.image = LibraryViewController.tile(for: row, traits: state.traitCollection)
                    content.imageProperties.reservedLayoutSize = CGSize(width: 38, height: 38)
                    content.imageToTextPadding = 14
                    content.text = row.title
                    content.textProperties.font = LibraryViewController.mediumBodyFont()
                    content.secondaryText = subtitle
                    content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
                    content.secondaryTextProperties.color = .secondaryLabel
                    content.textToSecondaryTextVerticalPadding = 2
                    content.directionalLayoutMargins.top = 9
                    content.directionalLayoutMargins.bottom = 9
                    cell.contentConfiguration = content
                }
            }
        }
        dataSource = UICollectionViewDiffableDataSource<Int, LibraryList>(collectionView: collectionView) { collectionView, indexPath, list in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: list)
        }
    }

    /// Body, medium weight, at the current text size.
    private static func mediumBodyFont() -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.medium]])
        return UIFont(descriptor: descriptor, size: 0)
    }

    /// The row's symbol in white on a 38-point rounded tile of its color,
    /// slightly lighter at the top, like the SwiftUI version's gradient.
    private static func tile(for row: Row, traits: UITraitCollection) -> UIImage {
        let size = CGSize(width: 38, height: 38)
        let color = row.color.resolvedColor(with: traits)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let lighter = UIColor(hue: hue, saturation: saturation * 0.85, brightness: min(brightness * 1.12, 1), alpha: alpha)
        let symbol = UIImage(
            systemName: row.systemImage,
            withConfiguration: UIImage.SymbolConfiguration(textStyle: .title3)
        )?.withTintColor(.white, renderingMode: .alwaysOriginal)

        let renderer = UIGraphicsImageRenderer(size: size, format: UIGraphicsImageRendererFormat(for: traits))
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIBezierPath(roundedRect: rect, cornerRadius: 9).addClip()
            let colors = [lighter.cgColor, color.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            if let symbol {
                symbol.draw(at: CGPoint(x: (size.width - symbol.size.width) / 2, y: (size.height - symbol.size.height) / 2))
            }
        }.withRenderingMode(.alwaysOriginal)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let list = dataSource.itemIdentifier(for: indexPath) else { return }
        navigator.show(.library(list))
    }
}
