import UIKit

/// A system button for retrying only the missing detail requests.
final class DetailRetryCell: UICollectionViewListCell {
    private let retryButton = UIButton(type: .system)

    func configure(retry: @escaping @MainActor () -> Void) {
        backgroundConfiguration = .clear()
        var button = UIButton.Configuration.bordered()
        button.title = "Try Again"
        button.image = UIImage(systemName: "arrow.clockwise")
        button.imagePadding = 8
        retryButton.configuration = button
        retryButton.accessibilityHint = "Reloads missing video information"
        retryButton.removeAction(identifiedBy: .init("retry"), for: .primaryActionTriggered)
        retryButton.addAction(UIAction(identifier: .init("retry")) { _ in retry() }, for: .primaryActionTriggered)
        accessories = [.customView(configuration: .init(customView: retryButton, placement: .trailing()))]
        var content = UIListContentConfiguration.cell()
        content.text = "Couldn't Load"
        contentConfiguration = content
    }
}
