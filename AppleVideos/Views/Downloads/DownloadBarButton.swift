import UIKit

/// The bar's Download button: Download, the progress ring while a download
/// runs (tap to stop), or the downloaded state, whose system menu offers to
/// renew or remove the download right at the button. Always a plain bar
/// button item, so the bar sizes it like its other buttons; the ring is the
/// item's image, drawn again only when the progress changes by a percent.
@MainActor
final class DownloadBarButton {
    private enum State: Equatable {
        case available(Bool)
        case loading
        case downloaded
    }

    let item = UIBarButtonItem()
    var onDownload: () -> Void = {}
    var onStop: () -> Void = {}
    var onRenew: () -> Void = {}
    var onRemove: () -> Void = {}

    private var state: State?
    private var shownPercent: Int?

    func update(activity: DownloadManager.Activity?, isDownloaded: Bool, canDownload: Bool) {
        let newState: State = activity != nil ? .loading : isDownloaded ? .downloaded : .available(canDownload)
        if newState != state {
            state = newState
            shownPercent = nil
            configure(for: newState)
        }
        if newState == .loading {
            let percent = Int(((activity?.progress ?? 0) * 100).rounded())
            if percent != shownPercent {
                shownPercent = percent
                item.image = Self.ring(progress: Double(percent) / 100)
                item.accessibilityValue = "\(percent) %"
            }
        }
    }

    private func configure(for state: State) {
        item.primaryAction = nil
        item.menu = nil
        item.isEnabled = true
        item.accessibilityLabel = nil
        item.accessibilityValue = nil
        switch state {
        case let .available(canDownload):
            item.primaryAction = UIAction(title: "Download", image: UIImage(systemName: "arrow.down")) { [weak self] _ in
                self?.onDownload()
            }
            item.isEnabled = canDownload
        case .loading:
            item.primaryAction = UIAction(title: "Stop Download", image: Self.ring(progress: 0)) { [weak self] _ in
                self?.onStop()
            }
        case .downloaded:
            item.image = UIImage(systemName: "arrow.down.circle.fill")
            item.accessibilityLabel = "Downloaded"
            item.menu = UIMenu(
                title: "Renew to keep this download from Videos or remove it from your iPhone.",
                children: [
                    UIAction(title: "Download Again to Renew", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
                        self?.onRenew()
                    },
                    UIAction(title: "Remove Download", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                        self?.onRemove()
                    }
                ]
            )
        }
    }

    /// A ring the size of a bar symbol, filled to `progress` around a stop
    /// symbol in its middle, as a template image the bar tints like its other
    /// symbols; the unfilled track is drawn at 35 % opacity.
    private static func ring(progress: Double) -> UIImage {
        // As large as a circle symbol in the bar, like the other buttons.
        let circle = UIImage(systemName: "circle", withConfiguration: UIImage.SymbolConfiguration(textStyle: .body, scale: .large))
        let diameter = ceil(circle.map { min($0.size.width, $0.size.height) } ?? 26)
        let size = CGSize(width: diameter, height: diameter)
        let lineWidth: CGFloat = 2.5
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = size.width / 2 - lineWidth / 2
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let track = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            track.lineWidth = lineWidth
            UIColor.black.withAlphaComponent(0.35).setStroke()
            track.stroke()

            if progress > 0 {
                // From the top, clockwise.
                let fill = UIBezierPath(
                    arcCenter: center,
                    radius: radius,
                    startAngle: -.pi / 2,
                    endAngle: -.pi / 2 + .pi * 2 * min(progress, 1),
                    clockwise: true
                )
                fill.lineWidth = lineWidth
                fill.lineCapStyle = .round
                UIColor.black.setStroke()
                fill.stroke()
            }

            let stop = UIImage(systemName: "stop.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: diameter * 0.38, weight: .bold))
            if let stop {
                stop.withTintColor(.black).draw(at: CGPoint(x: center.x - stop.size.width / 2, y: center.y - stop.size.height / 2))
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}
