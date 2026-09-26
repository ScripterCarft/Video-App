import UIKit

/// Selectable description, scrolling and link detection are owned by UIKit.
final class VideoDescriptionViewController: UIViewController {
    private let text: String

    init(video: Video, description: String) {
        text = description
        super.init(nibName: nil, bundle: nil)
        title = video.title
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let textView = UITextView()
        textView.text = text
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isEditable = false
        textView.dataDetectorTypes = [.link]
        textView.backgroundColor = .systemBackground
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 16, bottom: 20, right: 16)
        view = textView
    }
}
