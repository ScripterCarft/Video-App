import AVKit
import SwiftUI

// TEMPORARY TEST (do not merge): Explore is replaced by a single button that
// presents Apple's HLS example stream with the minimal AVKit recipe:
// AVPlayer(url:), AVPlayerViewController, present modally, play on completion.
// No delegate, metadata, audio session, navigation stack or app player code.
struct ExploreView: View {
    var body: some View {
        Button("Play Apple Test Stream") {
            PlainPlayerTest.present()
        }
        .buttonStyle(.borderedProminent)
    }
}

@MainActor
private enum PlainPlayerTest {
    static func present() {
        guard let url = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"),
              let presenter = topViewController()
        else { return }

        let player = AVPlayer(url: url)
        let controller = AVPlayerViewController()
        controller.player = player
        presenter.present(controller, animated: true) {
            player.play()
        }
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
