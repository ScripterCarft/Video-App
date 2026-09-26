import UIKit

/// A vertical list of full-width UIKit video cards: search and topic
/// results and the Library's lists. The same card and context menu as Home,
/// fixed sizes, and Apple's `UIContentUnavailableConfiguration` for loading,
/// empty and error states.
///
/// `state` is read in `updateProperties()`, so UIKit tracks the observable
/// data it reads and updates the list by itself. Cards removed from their
/// context menu leave once the menu has closed.
final class VideoListViewController: UIViewController, UICollectionViewDelegate, RoutedScreen {
    /// What the list shows.
    enum State {
        case videos([Video])
        case loading(String)
        case unavailable(UIContentUnavailableConfiguration)
    }

    let appRoute: AppRoute?
    private let section: String
    private let library: LibraryStore
    private let downloads = DownloadManager.shared
    private let navigator: VideoNavigator
    private let state: @MainActor () -> State
    private let emptyState: UIContentUnavailableConfiguration

    /// Runs each time the list appears, such as refreshing stored metadata.
    var onAppear: (@MainActor () async -> Void)?
    /// Enables pull to refresh.
    var onRefresh: (@MainActor () async -> Void)? {
        didSet { collectionView.refreshControl = onRefresh == nil ? nil : refreshControl }
    }
    /// A bar button shown while the list has videos, such as Remove All.
    var trailingItem: UIBarButtonItem?

    private var shownVideos: [Video] = []
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private lazy var menus = VideoContextMenus(library: library, downloads: downloads, presenter: self)
    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addAction(UIAction { [weak self] _ in
            self?.refresh()
        }, for: .valueChanged)
        return control
    }()

    /// `section` scopes the zoom transition's source to this list;
    /// `emptyState` shows when `state` has no videos.
    init(
        title: String,
        section: String,
        route: AppRoute?,
        library: LibraryStore,
        navigator: VideoNavigator,
        emptyState: UIContentUnavailableConfiguration,
        state: @escaping @MainActor () -> State
    ) {
        appRoute = route
        self.section = section
        self.library = library
        self.navigator = navigator
        self.emptyState = emptyState
        self.state = state
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// The list's scroll view, for a container screen whose navigation bar
    /// should follow it.
    var scrollView: UIScrollView {
        collectionView
    }

    override func loadView() {
        // The collection view is the screen, so the navigation bar follows it
        // for its large title and scroll edge effect by itself.
        view = collectionView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        configureDataSource()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The app's tint again after the white of the detail screen.
        navigationController?.navigationBar.tintColor = nil
        if let onAppear {
            Task { await onAppear() }
        }
    }

    /// Reads the list; UIKit tracks the reads and calls this again when they
    /// change. Changed cards are reconfigured in place, added and removed
    /// ones animate.
    override func updateProperties() {
        super.updateProperties()
        let videos: [Video]
        switch state() {
        case let .videos(list):
            videos = list
            contentUnavailableConfiguration = list.isEmpty ? emptyState : nil
        case let .loading(text):
            videos = []
            var loading = UIContentUnavailableConfiguration.loading()
            loading.text = text
            contentUnavailableConfiguration = loading
        case let .unavailable(configuration):
            videos = []
            contentUnavailableConfiguration = configuration
        }

        let item = videos.isEmpty ? nil : trailingItem
        if navigationItem.rightBarButtonItem !== item {
            navigationItem.rightBarButtonItem = item
        }
        applySnapshot(videos)
    }

    private func refresh() {
        guard let onRefresh else { return }
        Task {
            await onRefresh()
            refreshControl.endRefreshing()
        }
    }

    // MARK: - Layout and cells

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
            VideoCells.listSection(
                containerWidth: environment.container.effectiveContentSize.width,
                traits: environment.traitCollection
            )
        }
    }

    private func configureDataSource() {
        let registration = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, _, id in
            MainActor.assumeIsolated {
                guard let video = self?.video(id: id) else { return }
                cell.contentConfiguration = VideoCardConfiguration(video: video, quality: .search)
            }
        }
        dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
        }
    }

    private func video(id: String) -> Video? {
        shownVideos.first { $0.id == id }
    }

    private func applySnapshot(_ videos: [Video]) {
        // Unique IDs: the data source requires them.
        var seen = Set<String>()
        let unique = videos.filter { seen.insert($0.id).inserted }
        guard unique != shownVideos || dataSource.snapshot().numberOfSections == 0 else { return }

        let changed = unique.filter { video in shownVideos.contains { $0.id == video.id && $0 != video } }.map(\.id)
        let animated = !shownVideos.isEmpty && view.window != nil
        shownVideos = unique

        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(unique.map(\.id), toSection: 0)
        let existing = Set(dataSource.snapshot().itemIdentifiers)
        let reconfigure = changed.filter(existing.contains)
        if !reconfigure.isEmpty {
            snapshot.reconfigureItems(reconfigure)
        }
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    // MARK: - Opening videos

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath), let video = video(id: id) else { return }
        navigator.open(VideoRoute(video: video, section: section)) { [weak self] in
            guard let self,
                  let indexPath = self.dataSource.indexPath(for: id),
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
              let id = dataSource.itemIdentifier(for: indexPath),
              let video = video(id: id)
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
