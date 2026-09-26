import UIKit

/// What to search for, as Apple's plain list: the magnifying glass in the
/// app's tint and the suggestion. Search shows it as its search controller's
/// results controller while the field is active and empty.
final class SearchSuggestionsViewController: UIViewController, UICollectionViewDelegate {
    /// Called with the chosen suggestion.
    var onSelect: ((String) -> Void)?

    private let suggestions: [String]
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private lazy var collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: UICollectionViewCompositionalLayout.list(
            using: UICollectionLayoutListConfiguration(appearance: .plain)
        )
    )

    init(suggestions: [String]) {
        self.suggestions = suggestions
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func loadView() {
        view = collectionView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.delegate = self
        collectionView.keyboardDismissMode = .onDrag
        // Compact rows: subheadline text, a matching small symbol and less
        // vertical margin than a standard row.
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, String> { cell, _, suggestion in
            var content = cell.defaultContentConfiguration()
            content.image = UIImage(systemName: "magnifyingglass")
            content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .subheadline)
            content.text = suggestion
            content.textProperties.font = .preferredFont(forTextStyle: .subheadline)
            content.directionalLayoutMargins.top = 8
            content.directionalLayoutMargins.bottom = 8
            cell.contentConfiguration = content
        }
        dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) { collectionView, indexPath, suggestion in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: suggestion)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(suggestions, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        if let suggestion = dataSource.itemIdentifier(for: indexPath) {
            onSelect?(suggestion)
        }
    }
}
