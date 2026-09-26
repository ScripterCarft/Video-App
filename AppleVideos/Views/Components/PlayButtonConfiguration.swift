import UIKit

extension UIButton.Configuration {
    /// The white Play capsule, like the TV app's: "Play"; while the source
    /// resolves, a spinner and "Cancel"; for a started video, the play symbol
    /// with a short resume bar and the remaining time ("40m").
    ///
    /// `UIButton.Configuration` has no progress bar, so the play symbol and
    /// the bar are drawn once into the button's image.
    @MainActor
    static func play(progress: PlaybackProgress?, isPreparing: Bool, traits: UITraitCollection) -> Self {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .white
        configuration.baseForegroundColor = .black
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.imagePadding = 8

        let font = playFont(compatibleWith: traits)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(font: font)
        func title(_ text: String) -> AttributedString {
            var title = AttributedString(text)
            title.uiKit.font = font
            return title
        }

        if isPreparing {
            configuration.showsActivityIndicator = true
            configuration.attributedTitle = title("Cancel")
        } else if let progress {
            configuration.image = resumeImage(fraction: progress.fraction, font: font, traits: traits)
            configuration.attributedTitle = title(progress.remainingLabel)
        } else {
            configuration.image = UIImage(systemName: "play.fill")
            configuration.attributedTitle = title("Play")
        }
        return configuration
    }

    /// Subheadline, semibold, at the current text size.
    @MainActor
    private static func playFont(compatibleWith traits: UITraitCollection) -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline, compatibleWith: traits)
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]])
        return UIFont(descriptor: descriptor, size: 0)
    }

    /// The play symbol followed by a 52-point capsule track, filled to
    /// `fraction`, in black on the white capsule.
    @MainActor
    private static func resumeImage(fraction: Double, font: UIFont, traits: UITraitCollection) -> UIImage? {
        guard let symbol = UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(font: font))?
            .withTintColor(.black, renderingMode: .alwaysOriginal)
        else { return nil }
        let bar = CGSize(width: 52, height: 8)
        let spacing: CGFloat = 8
        let size = CGSize(width: symbol.size.width + spacing + bar.width, height: max(symbol.size.height, bar.height))

        let renderer = UIGraphicsImageRenderer(size: size, format: UIGraphicsImageRendererFormat(for: traits))
        let image = renderer.image { _ in
            symbol.draw(at: CGPoint(x: 0, y: (size.height - symbol.size.height) / 2))
            let track = CGRect(
                x: symbol.size.width + spacing,
                y: (size.height - bar.height) / 2,
                width: bar.width,
                height: bar.height
            )
            UIBezierPath(roundedRect: track, cornerRadius: bar.height / 2).addClip()
            UIColor.black.withAlphaComponent(0.22).setFill()
            UIRectFill(track)
            UIColor.black.setFill()
            UIRectFill(CGRect(x: track.minX, y: track.minY, width: track.width * min(max(fraction, 0), 1), height: track.height))
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}
