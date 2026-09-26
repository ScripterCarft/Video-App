import UIKit

/// The tab controller supplies the accessory's background, shape and safe-area
/// handling. This view supplies only its content and standard button actions.
final class MiniPlayerView: UIView {
    private let artwork = ArtworkImageView()
    private let open = UIButton(type: .system)
    private let transport = UIButton(type: .system)
    private let close = UIButton(type: .system)
    private var shownVideo: Video?
    private var shownTextSize: UIContentSizeCategory?
    private var shownPlaying: Bool?
    private var shownWaiting: Bool?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Highlighted controls and the loading indicator must not inherit
        // the app's red accent through tintColor.
        tintColor = .label
        [open, transport, close].forEach { $0.tintColor = .label }
        // The same centered aspect-fill crop as NowPlayingArtwork's square
        // AirPlay image; reuse the prepared thumbnail instead of re-encoding it.
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
        // TEST: a long press copies evidence without changing playback.
        transport.menu = UIMenu(children: [
            UIAction(title: "Copy Playback Diagnostics", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = NativePlayback.playbackDiagnostics()
            }
        ])
        close.accessibilityLabel = "Close player"
        var closeStyle = UIButton.Configuration.plain()
        closeStyle.image = UIImage(systemName: "xmark.circle")
        closeStyle.baseForegroundColor = .label
        closeStyle.buttonSize = .medium
        closeStyle.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .title3, scale: .medium)
        close.configuration = closeStyle
        let row = UIStackView(arrangedSubviews: [artwork, open, transport, close])
        row.alignment = .center
        row.spacing = 8
        row.setCustomSpacing(0, after: transport)
        [transport, close].forEach {
            $0.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        }
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            row.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            row.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            artwork.widthAnchor.constraint(equalToConstant: 32),
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
        let textSize = traitCollection.preferredContentSizeCategory
        if shownVideo != video || shownTextSize != textSize {
            shownVideo = video
            shownTextSize = textSize
            var title = UIButton.Configuration.plain()
            title.title = video.title
            title.subtitle = video.channelName
            title.titleAlignment = .leading
            title.titlePadding = 0
            title.subtitleLineBreakMode = .byTruncatingTail
            title.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
            title.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes
                result.font = .preferredFont(forTextStyle: .caption1)
                // Full-contrast white in dark mode, adapting to light mode.
                result.foregroundColor = .label
                return result
            }
            title.titleLineBreakMode = .byTruncatingTail
            title.baseForegroundColor = .label
            title.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes
                let size = UIFont.preferredFont(forTextStyle: .footnote).pointSize
                result.font = .systemFont(ofSize: size, weight: .bold)
                return result
            }
            open.configuration = title
            open.accessibilityLabel = video.title
            open.accessibilityHint = "Opens the full-screen player"
        }
        if shownPlaying != state.isPlaying || shownWaiting != state.isWaiting {
            shownPlaying = state.isPlaying
            shownWaiting = state.isWaiting
            var control = transport.configuration ?? UIButton.Configuration.plain()
            control.baseForegroundColor = .label
            control.buttonSize = .medium
            control.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .title3, scale: .medium)
            control.indicatorColorTransformer = UIConfigurationColorTransformer { _ in .label }
            control.image = UIImage(systemName: state.isPlaying ? "pause.fill" : "play.fill")
            control.showsActivityIndicator = state.isWaiting
            transport.configuration = control
            transport.accessibilityLabel = state.isPlaying ? "Pause" : "Play"
            transport.accessibilityValue = state.isWaiting ? "Loading" : nil
        }
        // UIKit supplies the accessory height. The two-line button's fitting
        // height and 44 pt hit targets provide the content's minimum height.
        // Keep controls reachable at large text sizes; the full title remains
        // available to VoiceOver and in the full-screen player.
        artwork.isHidden = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    }
}
