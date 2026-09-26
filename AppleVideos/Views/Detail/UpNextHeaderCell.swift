import UIKit

/// The same system header in both states. While loading, UIKit lays out a
/// standard activity indicator as a list-cell accessory beside the title.
final class UpNextHeaderCell: UICollectionViewListCell {
    private let spinner = UIActivityIndicatorView(style: .medium)

    func configure(isLoading: Bool) {
        backgroundConfiguration = .clear()
        contentConfiguration = VideoCells.headerConfiguration(title: "Up Next", topSpacing: 14)
        if isLoading {
            spinner.startAnimating()
            accessories = [.customView(configuration: .init(customView: spinner, placement: .trailing()))]
        } else {
            spinner.stopAnimating()
            accessories = []
        }
        isAccessibilityElement = true
        accessibilityTraits = .header
        accessibilityLabel = "Up Next"
        accessibilityValue = isLoading ? "Loading" : nil
    }
}
