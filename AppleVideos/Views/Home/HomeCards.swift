import UIKit

// MARK: - Featured

/// The featured video at the top of Home as a UIKit cell content
/// configuration: the 16:9 artwork centered on a 2:3 gray stage with a
/// gradient, "FEATURED", the title, the Play button and the duration.
/// Tapping anywhere but Play opens its detail screen (the collection view's
/// selection). Its height follows from its width; nothing is measured.
struct FeaturedCardConfiguration: UIContentConfiguration {
    var video: Video
    var library: LibraryStore
    var playback: PlaybackStarter

    func makeContentView() -> any UIView & UIContentView {
        FeaturedCardContentView(configuration: self)
    }

    func updated(for state: any UIConfigurationState) -> FeaturedCardConfiguration {
        self
    }

    static let cornerRadius: CGFloat = 22
    static let padding: CGFloat = 22

    /// The 2:3 stage of `width`.
    static func height(forWidth width: CGFloat) -> CGFloat {
        ceil(width * 3 / 2)
    }
}

final class FeaturedCardContentView: UIView, UIContentView {
    private var appliedConfiguration: FeaturedCardConfiguration

    var configuration: any UIContentConfiguration {
        get { appliedConfiguration }
        set {
            guard let configuration = newValue as? FeaturedCardConfiguration else { return }
            appliedConfiguration = configuration
            setNeedsUpdateProperties()
        }
    }

    private let stage = UIView()
    private let imageView = UIImageView()
    private let placeholderSymbol = UIImageView(image: UIImage(systemName: "play.rectangle.fill"))
    private let gradient = GradientView()
    private let eyebrowLabel = UILabel()
    private let titleLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let durationLabel = CapsuleLabel()

    private var loadedCandidates: [ArtworkCandidate]?
    private var imageTask: Task<Void, Never>?

    init(configuration: FeaturedCardConfiguration) {
        appliedConfiguration = configuration
        super.init(frame: .zero)
        buildViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        imageTask?.cancel()
    }

    private func buildViews() {
        stage.backgroundColor = .systemGray5
        stage.layer.cornerRadius = FeaturedCardConfiguration.cornerRadius
        stage.layer.cornerCurve = .continuous
        stage.layer.borderWidth = 0.5
        // Clips the image and the gradient to the rounded corners.
        stage.clipsToBounds = true
        stage.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stage)

        imageView.contentMode = .scaleAspectFit
        placeholderSymbol.tintColor = .tertiaryLabel
        placeholderSymbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .largeTitle)

        eyebrowLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        playButton.addAction(UIAction { [weak self] _ in
            self?.playTapped()
        }, for: .primaryActionTriggered)
        playButton.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [playButton, UIView(), durationLabel])
        row.axis = .horizontal
        row.alignment = .center

        let text = UIStackView(arrangedSubviews: [eyebrowLabel, titleLabel, row])
        text.axis = .vertical
        text.alignment = .fill
        text.spacing = 10

        for view in [imageView, placeholderSymbol, gradient, text] {
            view.translatesAutoresizingMaskIntoConstraints = false
            stage.addSubview(view)
        }

        let padding = FeaturedCardConfiguration.padding
        NSLayoutConstraint.activate([
            stage.topAnchor.constraint(equalTo: topAnchor),
            stage.leadingAnchor.constraint(equalTo: leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: trailingAnchor),
            stage.bottomAnchor.constraint(equalTo: bottomAnchor),

            imageView.topAnchor.constraint(equalTo: stage.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: stage.bottomAnchor),

            gradient.topAnchor.constraint(equalTo: stage.topAnchor),
            gradient.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            gradient.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            gradient.bottomAnchor.constraint(equalTo: stage.bottomAnchor),

            placeholderSymbol.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            placeholderSymbol.centerYAnchor.constraint(equalTo: stage.centerYAnchor),

            text.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: padding),
            text.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -padding),
            text.bottomAnchor.constraint(equalTo: stage.bottomAnchor, constant: -padding),
            text.topAnchor.constraint(greaterThanOrEqualTo: stage.topAnchor, constant: padding)
        ])
    }

    /// Runs before layout with valid traits. UIKit tracks what is read here,
    /// the observable playback state and saved progress as well as the text
    /// size and appearance, and calls this again when it changes.
    override func updateProperties() {
        super.updateProperties()
        let configuration = appliedConfiguration
        let video = configuration.video

        stage.layer.borderColor = UIColor.label.withAlphaComponent(0.06).resolvedColor(with: traitCollection).cgColor

        eyebrowLabel.attributedText = NSAttributedString(string: "FEATURED", attributes: [
            .font: Self.font(.caption1, bold: true, traits: traitCollection),
            .kern: 1.1
        ])
        titleLabel.font = Self.font(.title2, bold: true, traits: traitCollection)
        titleLabel.text = video.title

        durationLabel.text = video.duration
        durationLabel.isHidden = video.duration == nil
        durationLabel.font = UIFont.monospacedDigitSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traitCollection).pointSize,
            weight: .semibold
        )

        let progress = configuration.library.progress(for: video)
        let isPreparing = configuration.playback.isPreparing
        playButton.configuration = .play(progress: progress, isPreparing: isPreparing, traits: traitCollection)
        if isPreparing {
            playButton.accessibilityLabel = "Cancel"
            playButton.accessibilityValue = nil
        } else if let progress {
            playButton.accessibilityLabel = "Resume"
            playButton.accessibilityValue = "\(progress.remainingLabel) remaining"
        } else {
            playButton.accessibilityLabel = "Play"
            playButton.accessibilityValue = nil
        }

        loadArtwork(for: video)
    }

    private func playTapped() {
        let configuration = appliedConfiguration
        if configuration.playback.isPreparing {
            configuration.playback.cancel()
        } else {
            configuration.playback.start(
                configuration.video,
                description: configuration.video.descriptionText,
                library: configuration.library
            )
        }
    }

    /// Loads the artwork once per candidate list, from the shared loader and
    /// its cache.
    private func loadArtwork(for video: Video) {
        let candidates = video.artworkCandidates(lowData: NetworkConditions.shared.isConstrained)
        guard candidates != loadedCandidates else { return }
        loadedCandidates = candidates
        imageTask?.cancel()

        let maxPixelWidth = ArtworkQuality.hero.displayWidth * max(traitCollection.displayScale, 1)
        if let cached = ArtworkLoader.cachedImage(for: candidates, maxPixelWidth: maxPixelWidth) {
            show(cached)
            return
        }
        show(nil)
        imageTask = Task { [weak self] in
            let image = await ArtworkLoader.firstImage(
                from: candidates,
                requiresSixteenByNine: video.source == .youtube,
                maxPixelWidth: maxPixelWidth
            )
            guard !Task.isCancelled, let self, self.loadedCandidates == candidates else { return }
            self.show(image)
        }
    }

    private func show(_ image: UIImage?) {
        imageView.image = image
        placeholderSymbol.isHidden = image != nil
    }

    /// A text style's font at the current text size, bold if asked.
    nonisolated fileprivate static func font(_ style: UIFont.TextStyle, bold: Bool, traits: UITraitCollection) -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style, compatibleWith: traits)
        let styled = bold ? descriptor.withSymbolicTraits(.traitBold) ?? descriptor : descriptor
        return UIFont(descriptor: styled, size: 0)
    }
}

/// The featured card's gradient for the text: clear at the top, darkening
/// toward the bottom. One gradient layer, cheap to draw.
private final class GradientView: UIView {
    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        (layer as? CAGradientLayer)?.colors = [
            UIColor.black.withAlphaComponent(0),
            UIColor.black.withAlphaComponent(0.15),
            UIColor.black.withAlphaComponent(0.88)
        ].map(\.cgColor)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}

/// White text on a dark capsule, for the featured card's duration.
private final class CapsuleLabel: UIView {
    private let label = UILabel()

    var text: String? {
        get { label.text }
        set { label.text = newValue }
    }

    var font: UIFont {
        get { label.font }
        set { label.font = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.68)
        layer.cornerCurve = .continuous
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

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
