import UIKit

/// The existing artwork spacer, with a short reading background at its bottom.
/// Keeping the gradient in the scrolling cell makes its lower edge meet the
/// black page exactly, independently of the artwork's parallax transform.
final class DetailStageCell: UICollectionViewCell {
    private let readingBackground = CAGradientLayer()
    private var hero: DetailHeroView?

    func configureHero(_ configuration: DetailHeroConfiguration) {
        if let hero {
            hero.configuration = configuration
            return
        }
        let hero = DetailHeroView(configuration: configuration)
        self.hero = hero
        hero.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(hero)
        NSLayoutConstraint.activate([
            hero.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hero.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hero.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            hero.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor)
        ])
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let gray = UIColor(white: 0.16, alpha: 0.7)
        readingBackground.colors = [
            gray.withAlphaComponent(0).cgColor,
            gray.cgColor,
            gray.cgColor
        ]
        readingBackground.locations = [0, 0.8, 1]
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
