import UIKit

/// The existing artwork spacer, with a short reading background at its bottom.
/// Keeping the gradient in the scrolling cell makes its opaque edge meet the
/// black page exactly, independently of the artwork's parallax transform.
final class DetailStageCell: UICollectionViewCell {
    private let readingBackground = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let gray = UIColor(white: 0.16, alpha: 1)
        readingBackground.colors = [
            gray.withAlphaComponent(0).cgColor,
            gray.cgColor,
            gray.cgColor
        ]
        readingBackground.locations = [0, 0.25, 1]
        readingBackground.startPoint = CGPoint(x: 0.5, y: 0)
        readingBackground.endPoint = CGPoint(x: 0.5, y: 1)
        contentView.layer.addSublayer(readingBackground)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        let height = min(200, bounds.width * 0.5, bounds.height)
        let frame = CGRect(x: bounds.minX, y: bounds.maxY - height,
                           width: bounds.width, height: height)
        guard readingBackground.frame != frame else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        readingBackground.frame = frame
        CATransaction.commit()
    }
}
