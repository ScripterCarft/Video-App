import UIKit

/// Startup recovery stays in the UI layer. No destructive reset action:
/// retry opening the same store and importing the retained source data.
final class LibraryUnavailableViewController: UIViewController {
    var onRetry: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: "externaldrive.badge.exclamationmark")
        configuration.text = "Library Unavailable"
        configuration.secondaryText = "Your library couldn't be opened or updated. Your existing data has been kept. Check available storage and try again."
        var button = UIButton.Configuration.borderedProminent()
        button.title = "Try Again"
        configuration.button = button
        configuration.buttonProperties.primaryAction = UIAction { [weak self] _ in
            self?.onRetry?()
        }
        contentUnavailableConfiguration = configuration
    }
}
