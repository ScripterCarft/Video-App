import UIKit

/// A video card as a UIKit cell content configuration, Apple's modern cell
/// pattern: a plain `UICollectionViewCell` gets
/// `cell.contentConfiguration = VideoCardConfiguration(video:)`.
///
/// Layout, compact: the 16:9 artwork with the duration badge, then a
/// two-line title, the channel and the info line. Plain UIKit views whose
/// size never depends on where the cell is on screen.
struct VideoCardConfiguration: UIContentConfiguration {
    var video: Video
    /// The width the artwork is prepared for: `.compact` for shelves,
    /// `.search` for full-width cards in lists.
    var quality: ArtworkQuality = .compact

    func makeContentView() -> any UIView & UIContentView {
        VideoCardContentView(configuration: self)
    }

    func updated(for state: any UIConfigurationState) -> VideoCardConfiguration {
        self
    }

    /// Spacing below the artwork and between the text lines.
    static let artworkSpacing: CGFloat = 10
    static let lineSpacing: CGFloat = 4
    static let cornerRadius: CGFloat = 14

    /// The height of the tallest compact card of `width`: artwork, a
    /// two-line title, the channel and the info line, from the text styles'
    /// line heights for the current text size. Shelves use it as their fixed
    /// height, so nothing is measured while scrolling.
    static func height(forWidth width: CGFloat, traits: UITraitCollection) -> CGFloat {
        func line(_ style: UIFont.TextStyle) -> CGFloat {
            ceil(UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).lineHeight)
        }
        return ceil(width * 9 / 16) + artworkSpacing
            + 2 * line(.headline) + lineSpacing
            + line(.subheadline) + lineSpacing
            + line(.caption1)
    }
}

final class VideoCardContentView: UIView, UIContentView {
    private var appliedConfiguration: VideoCardConfiguration

    var configuration: any UIContentConfiguration {
        get { appliedConfiguration }
        set {
            guard let configuration = newValue as? VideoCardConfiguration else { return }
            appliedConfiguration = configuration
            setNeedsUpdateProperties()
        }
    }

    private let artwork = UIView()

    /// The artwork, where the zoom transition to the video's detail screen
    /// starts and returns to.
    var zoomSourceView: UIView { artwork }

    /// The artwork as currently shown, for the context menu's preview.
    var artworkImage: UIImage? { imageView.image }
    private let imageView = ArtworkImageView()
    private let badge = DurationBadge()
    private let titleLabel = UILabel()
    private let channelLabel = UILabel()
    private let infoLabel = UILabel()

    init(configuration: VideoCardConfiguration) {
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
        artwork.backgroundColor = .quaternarySystemFill
        artwork.layer.cornerRadius = VideoCardConfiguration.cornerRadius
        artwork.layer.cornerCurve = .continuous
        artwork.layer.borderWidth = 0.5
        artwork.clipsToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        artwork.addSubview(imageView)

        badge.translatesAutoresizingMaskIntoConstraints = false
        artwork.addSubview(badge)

        configure(titleLabel, style: .headline, color: .label, lines: 2)
        configure(channelLabel, style: .subheadline, color: .secondaryLabel, lines: 1)
        configure(infoLabel, style: .caption1, color: .tertiaryLabel, lines: 1)

        let text = UIStackView(arrangedSubviews: [titleLabel, channelLabel, infoLabel])
        text.axis = .vertical
        text.alignment = .fill
        text.spacing = VideoCardConfiguration.lineSpacing

        let stack = UIStackView(arrangedSubviews: [artwork, text])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = VideoCardConfiguration.artworkSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            // Top-aligned: shorter cards leave space below in a fixed cell.
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),

            artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor, multiplier: 9.0 / 16.0),

            imageView.topAnchor.constraint(equalTo: artwork.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: artwork.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: artwork.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: artwork.bottomAnchor),

            badge.trailingAnchor.constraint(equalTo: artwork.trailingAnchor, constant: -8),
            badge.bottomAnchor.constraint(equalTo: artwork.bottomAnchor, constant: -8)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Opens video details"
    }

    private func configure(_ label: UILabel, style: UIFont.TextStyle, color: UIColor, lines: Int) {
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = lines
        label.lineBreakMode = .byTruncatingTail
    }

    private func updateBorderColor() {
        artwork.layer.borderColor = UIColor.label.withAlphaComponent(0.06).resolvedColor(with: traitCollection).cgColor
    }

    // MARK: - Content

    /// Runs before layout with valid traits. UIKit tracks the observable
    /// download state and the traits read here and calls this again when
    /// they change, such as switching between light and dark.
    override func updateProperties() {
        super.updateProperties()
        let video = appliedConfiguration.video
        updateBorderColor()

        titleLabel.text = video.title
        channelLabel.text = video.channelName
        infoLabel.text = video.metadataLine
        infoLabel.isHidden = video.metadataLine.isEmpty

        let isDownloaded = DownloadManager.shared.isDownloaded(video)
        badge.update(duration: video.duration, isDownloaded: isDownloaded)

        accessibilityLabel = [video.title, video.channelName, video.metadataLine]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        accessibilityValue = isDownloaded ? "Downloaded" : nil

        imageView.load(video, quality: appliedConfiguration.quality)
    }
}

/// The duration and the downloaded symbol on a dark capsule, bottom right
/// on the artwork.
private final class DurationBadge: UIView {
    private let symbol = UIImageView(image: UIImage(systemName: "arrow.down.circle.fill"))
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.76)
        layer.cornerCurve = .continuous

        let font = UIFont.monospacedDigitSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize,
            weight: .semibold
        )
        label.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: font)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white

        symbol.tintColor = .white
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .caption2)
        symbol.adjustsImageSizeForAccessibilityContentSizeCategory = true
        symbol.accessibilityLabel = "Downloaded"

        let stack = UIStackView(arrangedSubviews: [symbol, label])
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7)
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

    func update(duration: String?, isDownloaded: Bool) {
        label.text = duration
        label.isHidden = duration == nil
        symbol.isHidden = !isDownloaded
        isHidden = duration == nil && !isDownloaded
    }
}
