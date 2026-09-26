import UIKit

/// The context menu of every collection of videos: the same items in the
/// same order, the thumbnail as preview, and changes that can remove a card
/// applied only after the menu has closed, so the collection view's data
/// source animates the card out once the menu is gone (as UIKit intends:
/// `willEndContextMenuInteraction` with the animator's completion).
///
/// A collection view's delegate returns `configuration(for:sourceView:)`
/// and forwards `willDisplayContextMenu` and `willEndContextMenuInteraction`.
@MainActor
final class VideoContextMenus {
    private let library: LibraryStore
    private let downloads: DownloadManager
    private weak var presenter: UIViewController?
    private var pendingAction: (@MainActor () -> Void)?
    private var isShowingMenu = false

    init(library: LibraryStore, downloads: DownloadManager, presenter: UIViewController) {
        self.library = library
        self.downloads = downloads
        self.presenter = presenter
    }

    /// The menu for the video in `cell`. `sourceView` anchors the share sheet
    /// on iPad.
    ///
    /// The preview is the thumbnail alone in a padded bubble, a preview
    /// controller of its own: unlike a preview lifted in place, UIKit moves
    /// it to leave room for the menu below it. It shows the image the card
    /// already has, so nothing loads.
    func configuration(
        for video: Video,
        in cell: UICollectionViewCell?,
        sourceView: @escaping () -> UIView?
    ) -> UIContextMenuConfiguration {
        let image = (cell?.contentView as? VideoCardContentView)?.artworkImage
        return UIContextMenuConfiguration(identifier: nil) {
            ThumbnailPreviewController(image: image)
        } actionProvider: { [weak self] _ in
            self?.menu(for: video, sourceView: sourceView)
        }
    }

    /// The card's artwork, where the preview grows out of and returns to.
    /// The collection view's delegate returns it as the highlight and the
    /// dismissal preview.
    static func targetedPreview(of cell: UICollectionViewCell?) -> UITargetedPreview? {
        guard let card = cell?.contentView as? VideoCardContentView else { return nil }
        let artwork = card.zoomSourceView
        let parameters = UIPreviewParameters()
        parameters.visiblePath = UIBezierPath(
            roundedRect: artwork.bounds,
            cornerRadius: VideoCardConfiguration.cornerRadius
        )
        return UITargetedPreview(view: artwork, parameters: parameters)
    }

    func willDisplay() {
        isShowingMenu = true
    }

    /// Applies a change from the menu after its closing animation.
    func willEnd(animator: (any UIContextMenuInteractionAnimating)?) {
        isShowingMenu = false
        guard let action = pendingAction else { return }
        pendingAction = nil
        if let animator {
            animator.addCompletion {
                MainActor.assumeIsolated {
                    action()
                }
            }
        } else {
            action()
        }
    }

    private func afterMenuCloses(_ action: @escaping @MainActor () -> Void) {
        if isShowingMenu {
            pendingAction = action
        } else {
            action()
        }
    }

    private func menu(for video: Video, sourceView: @escaping () -> UIView?) -> UIMenu {
        let library = library
        let downloads = downloads

        // Download, Save and Share side by side.
        var top: [UIMenuElement] = []
        if downloads.activity(for: video) != nil {
            top.append(UIAction(title: "Stop", image: UIImage(systemName: "stop.circle")) { _ in
                downloads.cancel(video)
            })
        } else if !downloads.isDownloaded(video) {
            top.append(UIAction(
                title: "Download",
                image: UIImage(systemName: "arrow.down"),
                attributes: downloads.canDownload(video) ? [] : .disabled
            ) { _ in
                downloads.download(video)
            })
        }
        let isSaved = library.isSaved(video)
        top.append(UIAction(
            title: isSaved ? "Unsave" : "Save",
            image: UIImage(systemName: isSaved ? "bookmark.slash" : "bookmark")
        ) { [weak self] _ in
            self?.afterMenuCloses { library.toggleSaved(video) }
        })
        if video.youtubeURL != nil {
            top.append(UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                self?.share(video, from: sourceView())
            })
        }

        // Watchlist and History.
        var middle: [UIMenuElement] = []
        if library.isInWatchlist(video) {
            middle.append(UIAction(title: "Remove from Watchlist", image: UIImage(systemName: "minus.circle")) { [weak self] _ in
                self?.afterMenuCloses { library.removeFromWatchlist(video) }
            })
            middle.append(UIAction(title: "Mark as Watched", image: UIImage(systemName: "rectangle.badge.checkmark")) { [weak self] _ in
                self?.afterMenuCloses { library.markAsWatched(video) }
            })
        } else {
            middle.append(UIAction(title: "Add to Watchlist", image: UIImage(systemName: "plus.circle")) { [weak self] _ in
                self?.afterMenuCloses { library.addToWatchlist(video) }
            })
        }
        // While downloaded, the menu's only trash action is Remove Download.
        if library.isInRecentlyWatched(video), !downloads.isDownloaded(video) {
            middle.append(UIAction(title: "Remove from Recently Watched", image: UIImage(systemName: "trash")) { [weak self] _ in
                self?.afterMenuCloses { library.removeFromRecentlyWatched(video) }
            })
        }

        var children: [UIMenuElement] = [
            UIMenu(options: .displayInline, preferredElementSize: .medium, children: top),
            UIMenu(options: .displayInline, children: middle)
        ]
        if downloads.isDownloaded(video) {
            children.append(UIMenu(options: .displayInline, children: [
                UIAction(title: "Remove Download", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    self?.afterMenuCloses { downloads.remove(video) }
                }
            ]))
        }
        return UIMenu(children: children)
    }

    private func share(_ video: Video, from sourceView: UIView?) {
        guard let controller = VideoShareItem.shareSheet(for: video) else { return }
        controller.popoverPresentationController?.sourceView = sourceView
        presenter?.present(controller, animated: true)
    }
}

/// The context menu's preview: the thumbnail alone, rounded, on a padded
/// bubble of the system background, 320 points wide.
private final class ThumbnailPreviewController: UIViewController {
    private static let width: CGFloat = 320
    private static let padding: CGFloat = 16
    private let image: UIImage?

    init(image: UIImage?) {
        self.image = image
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = CGSize(
            width: Self.width + 2 * Self.padding,
            height: Self.width * 9 / 16 + 2 * Self.padding
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let imageView = UIImageView(image: image)
        imageView.backgroundColor = .quaternarySystemFill
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 18
        imageView.layer.cornerCurve = .continuous
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.padding),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.padding),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.padding),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Self.padding)
        ])
    }
}

/// The shared building blocks of every collection of videos: the shelf
/// section and the section title. Cells show `VideoCardConfiguration`.
@MainActor
enum VideoCells {
    /// Where the zoom to a video's detail screen starts: a card's artwork,
    /// or the whole cell for other content.
    static func zoomSource(of cell: UICollectionViewCell) -> UIView {
        (cell.contentView as? VideoCardContentView)?.zoomSourceView ?? cell.contentView
    }
    /// A section title in plain UIKit text, title 2 bold, with only its own
    /// margins (not the cell's, which follow the screen edges). `topSpacing`
    /// is part of the header's fixed height (see `shelfSection`).
    static func headerConfiguration(title: String, topSpacing: CGFloat) -> UIListContentConfiguration {
        var configuration = UIListContentConfiguration.cell()
        configuration.text = title
        configuration.textProperties.font = headerFont()
        configuration.textProperties.color = .label
        configuration.textProperties.numberOfLines = 1
        configuration.directionalLayoutMargins = NSDirectionalEdgeInsets(top: topSpacing, leading: 16, bottom: 0, trailing: 16)
        configuration.axesPreservingSuperviewLayoutMargins = []
        return configuration
    }

    private static func headerFont() -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title2)
        return UIFont(descriptor: descriptor.withSymbolicTraits(.traitBold) ?? descriptor, size: 0)
    }

    /// A horizontal shelf of UIKit video cards (`VideoCardConfiguration`)
    /// with a title header, all of fixed size. Estimated sizes made the
    /// collection view measure cells while it scrolled, which stuttered and,
    /// on iOS 27, ran into a layout loop crash (`_updateVisibleCellsNow`
    /// recursing until an assertion failed).
    static func shelfSection(
        cardWidth: CGFloat,
        headerTopSpacing: CGFloat,
        traits: UITraitCollection
    ) -> NSCollectionLayoutSection {
        let cardHeight = VideoCardConfiguration.height(forWidth: cardWidth, traits: traits)
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(cardHeight))
        let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(cardWidth), heightDimension: .absolute(cardHeight))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [NSCollectionLayoutItem(layoutSize: itemSize)])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
        section.interGroupSpacing = 14
        section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16)
        section.supplementaryContentInsetsReference = .none

        let titleHeight = ceil(UIFont.preferredFont(forTextStyle: .title2, compatibleWith: traits).lineHeight)
        section.boundarySupplementaryItems = [
            NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(headerTopSpacing + titleHeight)
                ),
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
        ]
        return section
    }
}
