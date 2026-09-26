import UIKit

struct DetailHeroConfiguration: UIContentConfiguration {
    let model: VideoDetailModel
    let library: LibraryStore
    let playback: PlaybackStarter

    func makeContentView() -> any UIView & UIContentView {
        DetailHeroView(configuration: self)
    }

    func updated(for state: any UIConfigurationState) -> Self { self }

    /// Only content that affects height. Playback and Saved don't change it.
    @MainActor var sizingKey: String {
        [model.shown.title, model.shown.channelName, String(model.detailsLoadFinished),
         model.visibleDescription ?? "", model.textMetadata.joined(separator: " · "),
         model.visibleBadges.joined(separator: " · ")].joined(separator: "\n")
    }
}

/// A measured, fixed-height collection cell: text can grow with Dynamic Type
/// without pushing over the thumbnail or invoking collection self-sizing.
private final class DetailHeroView: UIView, UIContentView {
    private var value: DetailHeroConfiguration
    var configuration: any UIContentConfiguration {
        get { value }
        set {
            guard let newValue = newValue as? DetailHeroConfiguration else { return }
            value = newValue
            setNeedsUpdateProperties()
        }
    }

    private let backdrop = DetailHeroBackdrop()
    private let titleLabel = UILabel()
    private let channelLabel = UILabel()
    private let play = UIButton(type: .system)
    private let save = UIButton(type: .system)
    private let buttons = UIStackView()
    private let descriptionLabel = UILabel()
    private let badges = UIStackView()
    private var shownBadges: [String] = []
    private let metadata = UILabel()
    private let placeholders = DetailPlaceholderLines()
    private let details = UIStackView()
    private var showedDetails = false

    init(configuration: DetailHeroConfiguration) {
        value = configuration
        super.init(frame: .zero)
        build()
        // Fitting-size measurement needs populated labels before a render pass.
        updateContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func build() {
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)
        titleLabel.numberOfLines = 3
        titleLabel.textAlignment = .center
        titleLabel.accessibilityTraits.insert(.header)
        channelLabel.numberOfLines = 0
        channelLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 2
        metadata.numberOfLines = 0
        [titleLabel, channelLabel, descriptionLabel, metadata].forEach {
            $0.textColor = .white
            $0.adjustsFontForContentSizeCategory = true
        }
        channelLabel.textColor = .secondaryLabel
        metadata.textColor = .secondaryLabel

        buttons.spacing = 12
        buttons.alignment = .center
        buttons.addArrangedSubview(play)
        buttons.addArrangedSubview(save)
        play.setContentCompressionResistancePriority(.init(751), for: .horizontal)
        play.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if value.playback.isPreparing { value.playback.cancel() }
            else { value.playback.start(value.model.shown, description: value.model.loadedDescription, library: value.library) }
        }, for: .primaryActionTriggered)
        save.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            value.library.toggleSaved(value.model.shown)
        }, for: .primaryActionTriggered)
        save.widthAnchor.constraint(equalTo: save.heightAnchor).isActive = true
        save.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        play.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        details.axis = .vertical
        details.alignment = .fill
        details.spacing = 8
        badges.axis = .horizontal
        badges.spacing = 5
        badges.alignment = .center
        [descriptionLabel, metadata, badges].forEach(details.addArrangedSubview)
        let content = UIStackView(arrangedSubviews: [titleLabel, channelLabel, buttons, placeholders, details])
        content.axis = .vertical
        content.alignment = .fill
        content.spacing = 12
        // A wrapper centers the content-sized buttons without fixing Play's width.
        let row = UIView()
        content.removeArrangedSubview(buttons)
        content.insertArrangedSubview(row, at: 2)
        buttons.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(buttons)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor, constant: DetailHeroBackdrop.fadeHeight + 12),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            buttons.topAnchor.constraint(equalTo: row.topAnchor),
            buttons.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            buttons.centerXAnchor.constraint(equalTo: row.centerXAnchor),
            buttons.leadingAnchor.constraint(greaterThanOrEqualTo: row.leadingAnchor),
            buttons.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor)
        ])
    }

    override func updateProperties() {
        super.updateProperties()
        let reveal = !showedDetails && value.model.detailsLoadFinished && window != nil
        updateContent()
        if reveal, !UIAccessibility.isReduceMotionEnabled {
            details.alpha = 0
            UIView.animate(withDuration: 0.25) { self.details.alpha = 1 }
        }
    }

    private func updateBadges(_ values: [String]) {
        if shownBadges != values {
            shownBadges = values
            badges.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for text in values {
                let label = DetailMetadataBadge()
                label.text = text
                badges.addArrangedSubview(label)
            }
            badges.addArrangedSubview(UIView())
        }
        for case let label as DetailMetadataBadge in badges.arrangedSubviews {
            label.font = .preferredFont(forTextStyle: .caption2, compatibleWith: traitCollection)
        }
        badges.isHidden = values.isEmpty
    }

    private func updateContent() {
        let model = value.model
        titleLabel.text = model.shown.title
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title1, compatibleWith: traitCollection)
        titleLabel.font = UIFont(descriptor: descriptor.withSymbolicTraits(.traitBold) ?? descriptor, size: 0)
        channelLabel.font = .preferredFont(forTextStyle: .headline, compatibleWith: traitCollection)
        channelLabel.text = model.shown.channelName
        descriptionLabel.font = .preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection)
        metadata.font = .preferredFont(forTextStyle: .caption1, compatibleWith: traitCollection)
        descriptionLabel.text = model.visibleDescription
        descriptionLabel.isHidden = model.visibleDescription == nil
        metadata.text = model.textMetadata.joined(separator: " · ")
        updateBadges(model.visibleBadges)
        metadata.isHidden = metadata.text?.isEmpty != false
        placeholders.isHidden = model.detailsLoadFinished
        details.isHidden = !model.detailsLoadFinished
        showedDetails = model.detailsLoadFinished
        buttons.axis = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
        let progress = value.library.progress(for: model.shown)
        play.configuration = .play(progress: progress, isPreparing: value.playback.isPreparing, traits: traitCollection)
        play.accessibilityLabel = value.playback.isPreparing ? "Cancel" : (progress == nil ? "Play" : "Resume")
        var style = UIButton.Configuration.filled()
        style.baseBackgroundColor = .darkGray
        style.baseForegroundColor = .white
        style.cornerStyle = .capsule
        style.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        let saved = value.library.isSaved(model.shown)
        style.image = UIImage(systemName: saved ? "checkmark" : "plus")
        style.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .headline)
        save.configuration = style
        save.accessibilityLabel = saved ? "Remove from Saved" : "Save"
    }
}

/// Opaque gray behind every control. Only the first 32 pt blend over the
/// artwork. The bottom stays opaque gray, with a hard edge to the black shelf.
final class DetailHeroBackdrop: UIView {
    static let color = UIColor(white: 0.12, alpha: 1)
    static let fadeHeight: CGFloat = 32
    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        let gradient = layer as! CAGradientLayer
        gradient.colors = [Self.color.withAlphaComponent(0).cgColor, Self.color.cgColor,
                           Self.color.cgColor]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.height > Self.fadeHeight else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        (layer as! CAGradientLayer).locations = [0, NSNumber(value: Double(Self.fadeHeight / bounds.height)),
                                                1]
        CATransaction.commit()
    }
}

private final class DetailPlaceholderLines: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityLabel = "Loading video details"
        var previous: UIView?
        for fraction in [CGFloat(1), 0.72, 0.55] {
            let bar = UIView()
            bar.backgroundColor = .white.withAlphaComponent(0.12)
            bar.layer.cornerRadius = 4
            bar.translatesAutoresizingMaskIntoConstraints = false
            addSubview(bar)
            NSLayoutConstraint.activate([
                bar.topAnchor.constraint(equalTo: previous?.bottomAnchor ?? topAnchor, constant: previous == nil ? 0 : 10),
                bar.leadingAnchor.constraint(equalTo: leadingAnchor),
                bar.widthAnchor.constraint(equalTo: widthAnchor, multiplier: fraction),
                bar.heightAnchor.constraint(equalToConstant: 12)
            ])
            previous = bar
        }
        previous?.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Text badges aren't buttons. Insets and a subtle border keep HD/CC legible.
private final class DetailMetadataBadge: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        textColor = .lightGray
        textAlignment = .center
        adjustsFontForContentSizeCategory = true
        backgroundColor = UIColor.white.withAlphaComponent(0.06)
        layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        layer.borderWidth = 0.5
        layer.cornerRadius = 3
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + 8, height: size.height + 4)
    }
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: 4, dy: 2))
    }
}
