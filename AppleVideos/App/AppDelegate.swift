import AVKit
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set the playback category once at launch, as Apple recommends for media
        // apps. AVPlayer activates the session itself when playback starts.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        return true
    }

    /// The system relaunches the app when background downloads finish; the
    /// download manager calls the handler once it has processed the events.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        DownloadManager.shared.backgroundCompletionHandlers[identifier] = completionHandler
    }

    /// The app itself is portrait only; only the full-screen player may rotate.
    /// Info.plist still lists landscape because it caps every view controller,
    /// including AVPlayerViewController.
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        if let player = top as? AVPlayerViewController, !player.isBeingDismissed {
            return .allButUpsideDown
        }
        return .portrait
    }
}
