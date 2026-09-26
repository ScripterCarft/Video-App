import UIKit

/// The detail screen's hero as a UIKit cell content configuration: title,
/// channel, Play and Save, the description and the info line, at the bottom
/// of the page's first cell, over the artwork, on a gradient that ends in
/// the page's black at the artwork's lower edge.
///
/// The content view reads the observable model, playback and library in
/// `updateProperties()`; UIKit tracks those reads and updates the hero when
/// they change, so nothing forwards updates by hand.
struct DetailHeroConfiguration: UIContentConfiguration {
    let model: VideoDetailModel
    let playback: PlaybackStarter
    let library: LibraryStore
    let onShowDescription: () -> Void
    let onFeedback: () -> Void

    func makeContentView() -> any UIView & UIContentView {
        DetailHeroContentView(configuration: self)
    }

    func updated(for state: any UIConfigurationState) -> DetailHeroConfiguration {
        self
    }
}

final class DetailHeroContentView: UIView, UIContentView {
    /// How far the gradient reaches above the title, and how long its fade is.
    private static let gradientOverhang: CGFloat = 30
    private static let gradientFade: CGFloat = 70
    /// The gradient's solid bottom band, where it turns into the page's black.
    private static let gradientBand: CGFloat = 16

    private var appliedConfiguration: DetailHeroConfiguration

    var configuration: any UIContentConfiguration {
        get { appliedConfiguration }
        set {
            guard let configuration = newValue as? DetailHeroConfiguration else { return }
            appliedConfiguration = configuration
            setNeedsUpdateProperties()
        }
    }

    private let gradient = GradientView()
    private let titleLabel = UILabel()
    private let channelLabel = UILabel()
    private let playButton = UIButton(configuration: .filled())
    private let saveButton = UIButton(configuration: .filled())
    private let descriptionLabel = UILabel()
    private let moreButton = UIButton(configuration: .plain())
    private let descriptionPlaceholder = PlaceholderLines(widths: [1, 0.7])
    private let metadataRow = UIStackView()
    private let metadataPlaceholder = PlaceholderLines(widths: [0.55])
    private lazy var descriptionBlock = UIStackView(arrangedSubviews: [descriptionLabel, moreButton])
    private lazy var info = UIStackView()

    /// Whether the details were loaded when the hero last updated, to reveal
    /// them in one animation.
    private var showsLoadedDetails: Bool?

    init(configuration: DetailHeroConfiguration) {
        appliedConfiguration = configuration
        super.init(frame: .zero)
        buildViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // MARK: - Views

    private func buildViews() {
        gradient.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gradient)

        configure(titleLabel, font: Self.boldFont(.title1), color: .white, lines: 3)
        titleLabel.textAlignment = .center
        configure(channelLabel, font: .preferredFont(forTextStyle: .headline), color: UIColor.white.withAlphaComponent(0.72), lines: 1)
        channelLabel.textAlignment = .center
        let titleBlock = UIStackView(arrangedSubviews: [titleLabel, channelLabel])
        titleBlock.axis = .vertical
        titleBlock.spacing = 5

        playButton.addAction(UIAction { [weak self] _ in self?.playTapped() }, for: .primaryActionTriggered)
        saveButton.addAction(UIAction { [weak self] _ in self?.saveTapped() }, for: .primaryActionTriggered)
        let buttons = UIStackView(arrangedSubviews: [playButton, saveButton])
        buttons.axis = .horizontal
        buttons.spacing = 10
        let buttonRow = UIStackView(arrangedSubviews: [buttons])
        buttonRow.axis = .vertical
        buttonRow.alignment = .center

        configure(descriptionLabel, font: .preferredFont(forTextStyle: .subheadline), color: UIColor.white.withAlphaComponent(0.88), lines: 2)
        var more = UIButton.Configuration.plain()
        more.contentInsets = .zero
        more.baseForegroundColor = .white
        more.attributedTitle = AttributedString("MORE", attributes: AttributeContainer([.font: Self.semiboldFont(.caption1)]))
        moreButton.configuration = more
        moreButton.addAction(UIAction { [weak self] _ in self?.appliedConfiguration.onShowDescription() }, for: .primaryActionTriggered)
        descriptionBlock.axis = .vertical
        descriptionBlock.alignment = .leading
        descriptionBlock.spacing = 4

        metadataRow.axis = .horizontal
        metadataRow.alignment = .center
        metadataRow.spacing = 7

        for view in [titleBlock, buttonRow, descriptionPlaceholder, descriptionBlock, metadataPlaceholder, metadataRow] {
            info.addArrangedSubview(view)
        }
        info.axis = .vertical
        info.spacing = 14
        info.translatesAutoresizingMaskIntoConstraints = false
        addSubview(info)

        NSLayoutConstraint.activate([
            info.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            info.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            info.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            info.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),

            gradient.topAnchor.constraint(equalTo: info.topAnchor, constant: -Self.gradientOverhang),
            gradient.leadingAnchor.constraint(equalTo: leadingAnchor),
            gradient.trailingAnchor.constraint(equalTo: trailingAnchor),
            gradient.bottomAnchor.constraint(equalTo: bottomAnchor),

            playButton.heightAnchor.constraint(equalToConstant: 50),
            playButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 190),
            saveButton.widthAnchor.constraint(equalToConstant: 50),
            saveButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func configure(_ label: UILabel, font: UIFont, color: UIColor, lines: Int) {
        label.font = font
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = lines
        label.lineBreakMode = .byTruncatingTail
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = gradient.bounds.height
        guard height > 0 else { return }
        gradient.setStops(
            fadeEnd: min(Self.gradientFade / height, 1),
            bandStart: max(1 - Self.gradientBand / height, 0)
        )
    }

    // MARK: - Content

    /// Runs before layout. UIKit tracks the observable reads here (details,
    /// playback, saved state, progress) and calls it again when they change.
    override func updateProperties() {
        super.updateProperties()
        let model = appliedConfiguration.model
        let library = appliedConfiguration.library

        titleLabel.text = model.shown.title
        channelLabel.text = model.shown.channelName
        updatePlayButton(
            progress: library.progress(for: model.video),
            isPreparing: appliedConfiguration.playback.isPreparing
        )
        updateSaveButton(isSaved: library.isSaved(model.video))

        let loaded = model.detailsLoadFinished
        let description = model.visibleDescription
        let metadata = model.textMetadata
        let badges = model.visibleBadges
        let reveal = { [self] in
            descriptionPlaceholder.isHidden = loaded
            metadataPlaceholder.isHidden = loaded
            descriptionLabel.text = description
            descriptionBlock.isHidden = !loaded || description == nil
            metadataRow.isHidden = !loaded
            updateMetadata(metadata, badges: badges)
        }
        // Everything that loaded appears at once, in one short animation.
        if let shown = showsLoadedDetails, shown != loaded, window != nil {
            UIView.transition(with: info, duration: 0.25, options: [.transitionCrossDissolve, .allowUserInteraction], animations: reveal)
        } else {
            reveal()
        }
        showsLoadedDetails = loaded
    }

    private func updatePlayButton(progress: PlaybackProgress?, isPreparing: Bool) {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .white
        configuration.baseForegroundColor = .black
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 26, bottom: 0, trailing: 26)
        configuration.imagePadding = 8
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .headline)
        let font = UIFont.preferredFont(forTextStyle: .headline)

        if isPreparing {
            configuration.showsActivityIndicator = true
            configuration.attributedTitle = AttributedString("Cancel", attributes: AttributeContainer([.font: font]))
            playButton.accessibilityLabel = "Cancel"
            playButton.accessibilityValue = nil
        } else if let progress {
            // Play symbol with a short resume bar, then the remaining time, like the TV app.
            configuration.image = Self.resumeImage(progress.fraction, font: font)
            let digits = UIFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .semibold)
            configuration.attributedTitle = AttributedString(progress.remainingLabel, attributes: AttributeContainer([.font: digits]))
            playButton.accessibilityLabel = "Resume"
            playButton.accessibilityValue = "\(progress.remainingLabel) remaining"
        } else {
            configuration.image = UIImage(systemName: "play.fill")
            configuration.attributedTitle = AttributedString("Play", attributes: AttributeContainer([.font: font]))
            playButton.accessibilityLabel = "Play"
            playButton.accessibilityValue = nil
        }
        playButton.configuration = configuration
    }

    private func updateSaveButton(isSaved: Bool) {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = UIColor(white: 0.24, alpha: 1)
        configuration.baseForegroundColor = .white
        configuration.background.strokeColor = UIColor.white.withAlphaComponent(0.16)
        configuration.background.strokeWidth = 0.5
        configuration.contentInsets = .zero
        configuration.image = UIImage(systemName: isSaved ? "checkmark" : "plus")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .headline)
        saveButton.configuration = configuration
        saveButton.accessibilityLabel = isSaved ? "Remove from Saved" : "Add to Saved"
    }

    private func updateMetadata(_ items: [String], badges: [String]) {
        metadataRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let font = UIFont.preferredFont(forTextStyle: .footnote)
        for (index, item) in items.enumerated() {
            if index > 0 {
                metadataRow.addArrangedSubview(Self.label("·", font: font, color: UIColor.white.withAlphaComponent(0.42)))
            }
            metadataRow.addArrangedSubview(Self.label(item, font: font, color: UIColor.white.withAlphaComponent(0.7)))
        }
        for badge in badges {
            metadataRow.addArrangedSubview(MetadataBadge(text: badge))
        }
        // Keeps the row leading-aligned; the spacer takes the rest of the width.
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        metadataRow.addArrangedSubview(spacer)
    }

    // MARK: - Actions

    private func playTapped() {
        let configuration = appliedConfiguration
        if configuration.playback.isPreparing {
            configuration.playback.cancel()
        } else {
            configuration.playback.start(
                configuration.model.video,
                description: configuration.model.visibleDescription,
                library: configuration.library
            )
            configuration.onFeedback()
        }
    }

    private func saveTapped() {
        appliedConfiguration.library.toggleSaved(appliedConfiguration.model.video)
        appliedConfiguration.onFeedback()
    }

    // MARK: - Helpers

    private static func boldFont(_ style: UIFont.TextStyle) -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
        return UIFont(descriptor: descriptor.withSymbolicTraits(.traitBold) ?? descriptor, size: 0)
    }

    private static func semiboldFont(_ style: UIFont.TextStyle) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: style).pointSize
        return UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size, weight: .semibold))
    }

    private static func label(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.86
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    /// The play symbol and a 52 × 8 resume bar filled to `fraction`, as the
    /// button's image, drawn once per progress change.
    private static func resumeImage(_ fraction: Double, font: UIFont) -> UIImage? {
        guard let symbol = UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(font: font))?
            .withTintColor(.black, renderingMode: .alwaysOriginal)
        else { return nil }
        let bar = CGSize(width: 52, height: 8)
        let gap: CGFloat = 8
        let size = CGSize(width: symbol.size.width + gap + bar.width, height: max(symbol.size.height, bar.height))
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            symbol.draw(at: CGPoint(x: 0, y: (size.height - symbol.size.height) / 2))
            let track = CGRect(x: symbol.size.width + gap, y: (size.height - bar.height) / 2, width: bar.width, height: bar.height)
            UIColor.black.withAlphaComponent(0.22).setFill()
            UIBezierPath(roundedRect: track, cornerRadius: bar.height / 2).fill()
            UIColor.black.setFill()
            var filled = track
            filled.size.width = bar.width * fraction
            UIBezierPath(roundedRect: filled, cornerRadius: bar.height / 2).fill()
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}

/// The dark gradient behind the hero's text: clear at the top, a short
/// fade, then a steady dark area that turns solid black at the bottom, where
/// the page's black begins. A Core Animation gradient, drawn once.
private final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        let layer = layer as! CAGradientLayer
        layer.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(0.72).cgColor,
            UIColor.black.withAlphaComponent(0.72).cgColor,
            UIColor.black.cgColor
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func setStops(fadeEnd: CGFloat, bandStart: CGFloat) {
        let stops = [0, fadeEnd, max(bandStart, fadeEnd), 1].map { NSNumber(value: Double($0)) }
        let layer = layer as! CAGradientLayer
        guard layer.locations != stops else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.locations = stops
        CATransaction.commit()
    }
}

/// Rounded gray bars standing in for text lines until the details load.
private final class PlaceholderLines: UIStackView {
    init(widths: [CGFloat]) {
        super.init(frame: .zero)
        axis = .vertical
        alignment = .leading
        spacing = 6
        for width in widths {
            let bar = UIView()
            bar.backgroundColor = UIColor.white.withAlphaComponent(0.16)
            bar.layer.cornerRadius = 4
            bar.translatesAutoresizingMaskIntoConstraints = false
            addArrangedSubview(bar)
            NSLayoutConstraint.activate([
                bar.heightAnchor.constraint(equalToConstant: 12),
                bar.widthAnchor.constraint(equalTo: widthAnchor, multiplier: width)
            ])
        }
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}

/// A small outlined badge in the info line, such as HD or CC.
private final class MetadataBadge: UILabel {
    init(text: String) {
        super.init(frame: .zero)
        let size = UIFont.preferredFont(forTextStyle: .caption2).pointSize
        let font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: size, weight: .bold))
        attributedText = NSAttributedString(string: text, attributes: [.font: font, .kern: 0.2])
        textColor = UIColor.white.withAlphaComponent(0.82)
        backgroundColor = UIColor.white.withAlphaComponent(0.12)
        layer.cornerRadius = 4
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
        clipsToBounds = true
        setContentHuggingPriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + 12, height: size.height + 6)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: 6, dy: 3))
    }
}
