import UIKit

/// A screen whose collection view shows video cards: the shared context
/// menu for every card (`VideoContextMenus`), with the card's artwork as
/// the highlight and dismissal preview. Subclasses set themselves as the
/// collection view's delegate and return the video at an index path.
class VideoCollectionViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
    let library: LibraryStore
    let downloads = DownloadManager.shared
    private(set) lazy var menus = VideoContextMenus(library: library, downloads: downloads, presenter: self)
    private weak var artworkCollectionView: UICollectionView?
    private var pendingArtwork: [IndexPath] = []
    private var runningArtwork: [IndexPath: ArtworkLoader.Prefetch] = [:]

    init(library: LibraryStore) {
        self.library = library
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// The video of the card at `indexPath`; nil for other items, which get
    /// no menu.
    func video(at indexPath: IndexPath) -> Video? {
        nil
    }

    // MARK: - Artwork prefetching

    var artworkQuality: ArtworkQuality { .compact }

    func configureArtworkPrefetching(in collectionView: UICollectionView) {
        artworkCollectionView = collectionView
        collectionView.prefetchDataSource = self
    }

    func artworkRequest(at indexPath: IndexPath, in collectionView: UICollectionView) -> ArtworkRequest? {
        guard let video = video(at: indexPath) else { return nil }
        return ArtworkRequest(video: video, quality: artworkQuality,
                              displayScale: collectionView.traitCollection.displayScale,
                              lowData: NetworkConditions.shared.isConstrained)
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard !NetworkConditions.shared.isConstrained else { return }
        for indexPath in indexPaths where !pendingArtwork.contains(indexPath) {
            pendingArtwork.append(indexPath)
        }
        startPendingArtwork()
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let cancelled = Set(indexPaths)
        pendingArtwork.removeAll { cancelled.contains($0) }
        for indexPath in indexPaths {
            if let prefetch = runningArtwork.removeValue(forKey: indexPath) {
                ArtworkLoader.cancelPrefetch(prefetch)
            }
        }
        startPendingArtwork()
    }

    /// Call before replacing a snapshot: an index path may then name another
    /// item. Queued paths must never carry across that change.
    func cancelPendingArtworkPrefetches() {
        pendingArtwork.removeAll()
        for prefetch in runningArtwork.values { ArtworkLoader.cancelPrefetch(prefetch) }
        runningArtwork.removeAll()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cancelPendingArtworkPrefetches()
    }

    private func startPendingArtwork() {
        guard let collectionView = artworkCollectionView,
              !NetworkConditions.shared.isConstrained else {
            cancelPendingArtworkPrefetches()
            return
        }
        // UIKit orders its hints by proximity. Limit speculative work to two
        // requests; visible cells can load immediately and join these tasks.
        while runningArtwork.count < 2, !pendingArtwork.isEmpty {
            let indexPath = pendingArtwork.removeFirst()
            guard runningArtwork[indexPath] == nil,
                  let request = artworkRequest(at: indexPath, in: collectionView),
                  let prefetch = ArtworkLoader.prefetch(request) else { continue }
            runningArtwork[indexPath] = prefetch
            Task(priority: .utility) { [weak self] in
                _ = await prefetch.task.value
                guard let self, self.runningArtwork[indexPath]?.owner == prefetch.owner else { return }
                self.runningArtwork[indexPath] = nil
                self.startPendingArtwork()
            }
        }
    }

    // MARK: - Context menus

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first, let video = video(at: indexPath) else { return nil }
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
