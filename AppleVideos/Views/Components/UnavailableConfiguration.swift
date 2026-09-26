import UIKit

extension UIContentUnavailableConfiguration {
    /// Consistent system error presentation for full-screen loading failures.
    static func retry(title: String, message: String, symbol: String = "wifi.exclamationmark", action: UIAction) -> Self {
        var configuration = Self.empty()
        configuration.image = UIImage(systemName: symbol)
        configuration.text = title
        configuration.secondaryText = message
        var button = UIButton.Configuration.borderedProminent()
        button.title = "Try Again"
        configuration.button = button
        configuration.buttonProperties.primaryAction = action
        return configuration
    }
}
