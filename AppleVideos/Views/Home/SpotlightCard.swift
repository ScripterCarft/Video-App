import UIKit

// MARK: - Spotlight

/// The Spotlight card at the bottom of Home: Apple's list content (symbol,
/// title and text) on a rounded gray surface. Its height is Apple's content
/// view measured once per width and text size (`VideoCells.fittingHeight`).
enum SpotlightCard {
    @MainActor
    static func configuration() -> UIListContentConfiguration {
        var configuration = UIListContentConfiguration.subtitleCell()
        configuration.image = UIImage(systemName: "sparkles.tv.fill")
        configuration.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title1)
        configuration.text = "A calmer way to watch"
        configuration.textProperties.font = .preferredFont(forTextStyle: .headline)
        configuration.secondaryText = "No noisy counters or clutter. Just videos, collections, and your library."
        configuration.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
        return configuration
    }

    /// The card's rounded surface; an opaque system color, cheap to draw.
    @MainActor
    static var background: UIBackgroundConfiguration {
        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = .secondarySystemBackground
        background.cornerRadius = 24
        return background
    }

    @MainActor
    static func height(forWidth width: CGFloat, traits: UITraitCollection) -> CGFloat {
        VideoCells.fittingHeight(key: "spotlight", width: width, traits: traits) {
            configuration()
        }
    }
}
