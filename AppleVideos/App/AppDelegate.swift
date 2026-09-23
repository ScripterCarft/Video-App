import AVKit
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
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
