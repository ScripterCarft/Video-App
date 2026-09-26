import UIKit

/// TEMPORARY DEVICE DIAGNOSTIC. Remove after the 5G reproduction is explained.
/// Reads only the streaming toggle and network flags, never account data.
@MainActor
enum PlaybackDiagnostics {
    private static var hasShown = false

    static func showOnce(settings: StreamingSettings, hasDownload: Bool, pathWasReady: Bool) async -> Bool {
        guard !hasShown, let presenter = NativePlayback.topViewController() else { return false }
        hasShown = true
        let network = NetworkConditions.shared
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let persisted = UserDefaults.standard.persistentDomain(forName: bundleID)?["streaming.useMobileData"]
        let message = """
        Streaming Use Mobile Data: \(settings.useMobileData ? "ON" : "OFF")
        Saved setting: \(persisted.map { String(describing: $0) } ?? "not set; using default")
        Cellular path: \(network.usesCellular)
        Expensive path: \(network.isExpensive)
        Low Data Mode: \(network.isConstrained)
        Path ready before Play: \(pathWasReady)
        Offline download: \(hasDownload)
        Would block streaming: \(NativePlayback.isMobileDataBlocked(settings))
        App: \(bundleID)

        Please send a screenshot of this dialog. Then tap OK and Play again to test the decision shown above.
        """
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: "5G Playback Check — Test Build", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in continuation.resume() })
            presenter.present(alert, animated: true)
        }
        return true
    }
}
