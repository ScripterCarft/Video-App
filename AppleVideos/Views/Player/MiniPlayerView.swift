import UIKit

/// The tab controller supplies the accessory's background, shape and safe-area
/// handling. This view supplies only its content and standard button actions.
final class MiniPlayerView: UIView {
    private let artwork = ArtworkImageView()
    private let open = UIButton(type: .system)
    private let transport = UIButton(type: .system)
    private let close = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = 5
        artwork.isAccessibilityElement = false
        artwork.translatesAutoresizingMaskIntoConstraints = false
        open.contentHorizontalAlignment = .leading
        open.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        open.addAction(UIAction { _ in NativePlayback.restoreFromMiniPlayer() }, for: .primaryActionTriggered)
        transport.addAction(UIAction { _ in NativePlayback.toggleMiniPlayerPlayback() }, for: .primaryActionTriggered)
        close.addAction(UIAction { _ in NativePlayback.closeMiniPlayer() }, for: .primaryActionTriggered)
        close.accessibilityLabel = "Close player"
        var closeStyle = UIButton.Configuration.plain()
        closeStyle.image = UIImage(systemName: "xmark")
        closeStyle.baseForegroundColor = .label
        close.configuration = closeStyle
        let row = UIStackView(arrangedSubviews: [artwork, open, transport, close])
        row.alignment = .center
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            artwork.widthAnchor.constraint(equalToConstant: 56),
            artwork.heightAnchor.constraint(equalToConstant: 32),
            transport.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            transport.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            close.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            close.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func updateProperties() {
        super.updateProperties()
        let state = NativePlayback.displayState
        guard let video = state.video else { return }
        artwork.load(video, quality: .compact)
        var title = UIButton.Configuration.plain()
        title.title = video.title
        title.titleLineBreakMode = .byTruncatingTail
        title.baseForegroundColor = .label
        title.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes
            result.font = .preferredFont(forTextStyle: .subheadline)
            return result
        }
        open.configuration = title
        open.accessibilityLabel = video.title
        open.accessibilityHint = "Opens the full-screen player"
        var control = UIButton.Configuration.plain()
        control.baseForegroundColor = .label
        control.image = UIImage(systemName: state.isPlaying ? "pause.fill" : "play.fill")
        control.showsActivityIndicator = state.isWaiting
        transport.configuration = control
        transport.accessibilityLabel = state.isPlaying ? "Pause" : "Play"
        transport.accessibilityValue = state.isWaiting ? "Loading" : nil
        // Keep controls reachable at large text sizes; the full title remains
        // available to VoiceOver and in the full-screen player.
        artwork.isHidden = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    }
}
