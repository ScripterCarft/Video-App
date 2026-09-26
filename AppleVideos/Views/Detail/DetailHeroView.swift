import UIKit

struct DetailHeroConfiguration: UIContentConfiguration {
    let model: VideoDetailModel
    let library: LibraryStore
    let playback: PlaybackStarter
    var showDescription: @MainActor () -> Void = {}

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
    private let more = UIButton(type: .system)
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
        more.addAction(UIAction { [weak self] _ in self?.value.showDescription() }, for: .primaryActionTriggered)
        var moreStyle = UIButton.Configuration.plain()
        moreStyle.title = "MORE"
        moreStyle.baseForegroundColor = .secondaryLabel
        moreStyle.contentInsets = .zero
        more.configuration = moreStyle
        more.contentHorizontalAlignment = .leading
        more.accessibilityLabel = "Full description"
        more.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        save.widthAnchor.constraint(equalTo: save.heightAnchor).isActive = true
        save.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        play.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        details.axis = .vertical
        details.alignment = .fill
        details.spacing = 2
        [descriptionLabel, more, metadata].forEach(details.addArrangedSubview)
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
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -40),
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
        more.isHidden = descriptionLabel.isHidden
        metadata.text = (model.textMetadata + model.visibleBadges).joined(separator: " · ")
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
/// artwork; the final 24 pt meet the black page. No blur or shadow layers.
final class DetailHeroBackdrop: UIView {
    static let color = UIColor(white: 0.12, alpha: 1)
    static let fadeHeight: CGFloat = 32
    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        let gradient = layer as! CAGradientLayer
        gradient.colors = [Self.color.withAlphaComponent(0).cgColor, Self.color.cgColor,
                           Self.color.cgColor, UIColor.black.cgColor]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.height > Self.fadeHeight + 24 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        (layer as! CAGradientLayer).locations = [0, NSNumber(value: Double(Self.fadeHeight / bounds.height)),
                                                NSNumber(value: Double(1 - 24 / bounds.height)), 1]
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
