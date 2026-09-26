import UIKit

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
    /// Apple's prominent section header style
    /// (`prominentInsetGroupedHeader`), on one line, with a subtitle
    /// as its secondary text where a section has one (Explore).
    static func headerConfiguration(title: String, subtitle: String? = nil, topSpacing: CGFloat) -> UIListContentConfiguration {
        var configuration = UIListContentConfiguration.prominentInsetGroupedHeader()
        configuration.text = title
        configuration.textProperties.numberOfLines = 1
        configuration.secondaryText = subtitle
        configuration.secondaryTextProperties.numberOfLines = 1
        configuration.directionalLayoutMargins = NSDirectionalEdgeInsets(top: topSpacing, leading: 16, bottom: 0, trailing: 16)
        configuration.axesPreservingSuperviewLayoutMargins = []
        return configuration
    }

    /// A section title as a header of fixed height: Apple's header content
    /// view measured once per text size (`fittingHeight`). Titles and
    /// subtitles have one line, so any text gives the height.
    static func header(
        hasSubtitle: Bool = false,
        topSpacing: CGFloat = 0,
        width: CGFloat,
        traits: UITraitCollection
    ) -> NSCollectionLayoutBoundarySupplementaryItem {
        let height = fittingHeight(key: "header|\(hasSubtitle)|\(topSpacing)", width: width, traits: traits) {
            headerConfiguration(title: "Title", subtitle: hasSubtitle ? "Subtitle" : nil, topSpacing: topSpacing)
        }
        return NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height)),
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
    }

    /// Heights measured by `fittingHeight`, by content, width and text size.
    private static var fittingHeights: [String: CGFloat] = [:]

    /// The height Apple's own content view needs for `configuration` at
    /// `width` and the text size in `traits` (Auto Layout's fitting size).
    /// Measured once per key, width and text size and then reused, so the
    /// layout keeps fixed sizes and nothing is measured while scrolling.
    static func fittingHeight(
        key: String,
        width: CGFloat,
        traits: UITraitCollection,
        configuration: () -> any UIContentConfiguration
    ) -> CGFloat {
        let cacheKey = "\(key)|\(Int(width))|\(traits.preferredContentSizeCategory.rawValue)"
        if let height = fittingHeights[cacheKey] {
            return height
        }
        var height: CGFloat = 0
        // Fonts in the configuration and the view follow these traits.
        traits.performAsCurrent {
            let view = configuration().makeContentView()
            view.traitOverrides.preferredContentSizeCategory = traits.preferredContentSizeCategory
            height = ceil(view.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height)
        }
        fittingHeights[cacheKey] = height
        return height
    }

    /// Apple's plain list, as in Music's library, without the separator
    /// above the first row, which would sit on the bar's own line.
    static func plainListLayout() -> UICollectionViewCompositionalLayout {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.itemSeparatorHandler = { indexPath, separator in
            var separator = separator
            if indexPath.item == 0 {
                separator.topSeparatorVisibility = .hidden
            }
            return separator
        }
        return UICollectionViewCompositionalLayout.list(using: configuration)
    }

    /// A vertical list of full-width video cards between the screen margins,
    /// all of fixed size, like the shelves (see `shelfSection`). Cards show
    /// `.search` artwork, sharp at full width.
    static func listSection(containerWidth: CGFloat, traits: UITraitCollection) -> NSCollectionLayoutSection {
        let cardHeight = VideoCardConfiguration.height(forWidth: containerWidth - 2 * 16, traits: traits)
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(cardHeight))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 22
        section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        section.supplementaryContentInsetsReference = .none
        return section
    }

    /// A horizontal shelf of UIKit video cards (`VideoCardConfiguration`)
    /// with a title header, all of fixed size. Estimated sizes made the
    /// collection view measure cells while it scrolled, which stuttered and,
    /// on iOS 27, ran into a layout loop crash (`_updateVisibleCellsNow`
    /// recursing until an assertion failed).
    ///
    /// Pass the section provider's layout environment: UIKit tracks the text
    /// size read from its traits (automatic trait tracking) and asks for the
    /// section again when it changes.
    static func shelfSection(
        cardWidth: CGFloat,
        headerTopSpacing: CGFloat,
        environment: any NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection {
        let traits = environment.traitCollection
        let cardHeight = VideoCardConfiguration.height(forWidth: cardWidth, traits: traits)
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(cardHeight))
        let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(cardWidth), heightDimension: .absolute(cardHeight))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [NSCollectionLayoutItem(layoutSize: itemSize)])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuousGroupLeadingBoundary
        section.interGroupSpacing = 14
        section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16)
        section.supplementaryContentInsetsReference = .none
        section.boundarySupplementaryItems = [
            header(topSpacing: headerTopSpacing, width: environment.container.effectiveContentSize.width, traits: traits)
        ]
        return section
    }
}
