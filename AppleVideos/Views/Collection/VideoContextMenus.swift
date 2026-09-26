import SwiftUI
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
    static let previewWidth: CGFloat = 320

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

    /// The menu for `video`. `sourceView` anchors the share sheet on iPad.
    func configuration(for video: Video, sourceView: @escaping () -> UIView?) -> UIContextMenuConfiguration {
        // The preview is the thumbnail alone: a small preview leaves room for
        // the menu below it.
        let preview = {
            let controller = UIHostingController(
                rootView: VideoArtwork(video: video, cornerRadius: 18, quality: .search)
                    .frame(width: Self.previewWidth)
                    .padding()
            )
            controller.preferredContentSize = CGSize(
                width: Self.previewWidth + 32,
                height: Self.previewWidth * 9 / 16 + 32
            )
            return controller
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: preview) { [weak self] _ in
            self?.menu(for: video, sourceView: sourceView)
        }
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
        if let url = video.youtubeURL {
            top.append(UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                self?.share(url, from: sourceView())
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

    private func share(_ url: URL, from sourceView: UIView?) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = sourceView
        presenter?.present(controller, animated: true)
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
