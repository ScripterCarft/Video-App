import UIKit

/// The Library as a UIKit screen: Saved, Downloaded and History in Apple's
/// plain list, like Music's library: the symbol in the app's tint on the
/// leading side, the count in gray and a disclosure indicator on the
/// trailing side.
final class LibraryViewController: UIViewController, UICollectionViewDelegate {
    private struct Row {
        let list: LibraryList
        let title: String
        let systemImage: String
    }

    private static let rows = [
        Row(list: .saved, title: "Saved", systemImage: "bookmark"),
        Row(list: .downloaded, title: "Downloaded", systemImage: "arrow.down.circle"),
        Row(list: .history, title: "History", systemImage: "clock")
    ]

    private let library: LibraryStore
    private let downloads = DownloadManager.shared
    private let navigator: VideoNavigator
    /// The counts shown, to reconfigure only rows whose count changed.
    private var shownCounts: [LibraryList: Int] = [:]
    private var dataSource: UICollectionViewDiffableDataSource<Int, LibraryList>!
    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: UICollectionViewCompositionalLayout.list(
            using: UICollectionLayoutListConfiguration(appearance: .plain)
        )
    )

    init(library: LibraryStore, navigator: VideoNavigator) {
        self.library = library
        self.navigator = navigator
        super.init(nibName: nil, bundle: nil)
        title = "Library"
        // The large title sits in the bar at the leading edge, like Home.
        navigationItem.largeTitleDisplayMode = .inline
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
        let counts = Dictionary(uniqueKeysWithValues: Self.rows.map { ($0.list, count(of: $0.list)) })
        guard counts != shownCounts else { return }
        let changed = Self.rows.map(\.list).filter { shownCounts[$0] != nil && shownCounts[$0] != counts[$0] }
        shownCounts = counts
        guard !changed.isEmpty else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(changed)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func count(of list: LibraryList) -> Int {
        switch list {
        case .saved: library.savedVideos.count
        case .downloaded: downloads.videos.count
        case .history: library.recentlyWatched.count
        }
    }

    private func configureDataSource() {
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, LibraryList> { [weak self] cell, _, list in
            MainActor.assumeIsolated {
                guard let self, let row = LibraryViewController.rows.first(where: { $0.list == list }) else { return }
                var content = cell.defaultContentConfiguration()
                content.image = UIImage(systemName: row.systemImage)
                content.text = row.title
                cell.contentConfiguration = content
                let count = self.shownCounts[list] ?? self.count(of: list)
                cell.accessories = [.label(text: "\(count)"), .disclosureIndicator()]
            }
        }
        dataSource = UICollectionViewDiffableDataSource<Int, LibraryList>(collectionView: collectionView) { collectionView, indexPath, list in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: list)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let list = dataSource.itemIdentifier(for: indexPath) else { return }
        navigator.show(.library(list))
    }
}
