import SwiftUI
import WebKit

struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    let onWatchThreshold: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onWatchThreshold: onWatchThreshold)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(
            context.coordinator,
            name: "watchThreshold"
        )
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.watchScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.scrollView.isScrollEnabled = false
        view.isOpaque = false
        view.backgroundColor = .black
        view.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Mobile/15E148 Safari/604.1"
        return view
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedVideoID != videoID else { return }
        context.coordinator.loadedVideoID = videoID

        let referrer = "https://github.com/ScripterCarft/Video-App/"
        var components = URLComponents(string: "https://www.youtube.com/embed/\(videoID)")!
        components.queryItems = [
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "autoplay", value: "1"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "origin", value: "https://github.com"),
            URLQueryItem(name: "widget_referrer", value: referrer)
        ]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.setValue(referrer, forHTTPHeaderField: "Referer")
        request.setValue("https://github.com", forHTTPHeaderField: "Origin")
        webView.load(request)
    }

    private static let watchScript = """
        (() => {
          let watchedSeconds = 0;
          let previousTime = null;
          let reported = false;
          setInterval(() => {
            const video = document.querySelector('video');
            if (!video || reported) return;
            const currentTime = video.currentTime;
            if (!video.paused && !video.ended && previousTime !== null) {
              const elapsed = currentTime - previousTime;
              if (elapsed > 0 && elapsed < 2.5) watchedSeconds += Math.min(elapsed, 1.5);
            }
            previousTime = Number.isFinite(currentTime) ? currentTime : null;
            if (watchedSeconds >= 10) {
              reported = true;
              window.webkit.messageHandlers.watchThreshold.postMessage(true);
            }
          }, 1000);
        })();
        """

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, @preconcurrency WKScriptMessageHandler {
        var loadedVideoID: String?
        private let onWatchThreshold: @MainActor () -> Void

        init(onWatchThreshold: @escaping @MainActor () -> Void) {
            self.onWatchThreshold = onWatchThreshold
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "watchThreshold" else { return }
            onWatchThreshold()
        }
    }
}
