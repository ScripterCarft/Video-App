import UIKit

/// Startup recovery stays in the UI layer. No destructive reset action:
/// retry opening the same store and importing the retained source data.
final class LibraryUnavailableViewController: UIViewController {
    var onRetry: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        contentUnavailableConfiguration = UIContentUnavailableConfiguration.retry(
            title: "Library Unavailable",
            message: "Your library couldn't be opened or updated. Your existing data has been kept. Check available storage and try again.",
            symbol: "externaldrive.badge.exclamationmark",
            action: UIAction { [weak self] _ in self?.onRetry?() }
        )
    }
}
