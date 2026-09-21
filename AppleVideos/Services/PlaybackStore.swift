import AVFoundation
import Foundation
import Observation
@preconcurrency import WebKit

@MainActor
@Observable
final class PlaybackStore {
    private(set) var currentVideo: Video?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var isExpanded = false

    @ObservationIgnored private(set) lazy var youtubeSession = YouTubePlaybackSession { [weak self] state in
        guard let self else { return }
        currentTime = state.currentTime
        if state.duration.isFinite, state.duration > 0 {
            duration = state.duration
        }
        isPlaying = state.isPlaying
    }
    @ObservationIgnored private(set) var directPlayer: AVPlayer?

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var remainingText: String? {
        guard duration > 0 else { return nil }
        return "−" + Self.clockString(max(duration - currentTime, 0))
    }

    func play(_ video: Video) {
        let isNewVideo = currentVideo?.id != video.id
        if isNewVideo {
            directPlayer?.pause()
            directPlayer = nil
            currentVideo = video
            currentTime = 0
            duration = Self.seconds(from: video.duration) ?? 0
        }

        switch video.source {
        case .youtube:
            youtubeSession.load(videoID: video.id, startAt: isNewVideo ? 0 : currentTime)
        case .direct:
            if directPlayer == nil, let url = video.playbackURL {
                directPlayer = AVPlayer(url: url)
            }
            directPlayer?.play()
        }

        isPlaying = true
        isExpanded = true
    }

    func expand() {
        guard currentVideo != nil else { return }
        isExpanded = true
    }

    func minimize() {
        isExpanded = false
    }

    func togglePlayback() {
        guard let video = currentVideo else { return }
        isPlaying.toggle()
        switch video.source {
        case .youtube:
            isPlaying ? youtubeSession.play() : youtubeSession.pause()
        case .direct:
            isPlaying ? directPlayer?.play() : directPlayer?.pause()
        }
    }

    func stop() {
        youtubeSession.stop()
        directPlayer?.pause()
        directPlayer = nil
        currentVideo = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        isExpanded = false
    }

    private static func seconds(from duration: String?) -> TimeInterval? {
        guard let duration else { return nil }
        let components = duration.split(separator: ":").compactMap { TimeInterval($0) }
        guard components.count == 2 || components.count == 3 else { return nil }
        return components.reduce(0) { $0 * 60 + $1 }
    }

    private static func clockString(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded()), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

struct YouTubePlaybackState: Sendable {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
}

@MainActor
final class YouTubePlaybackSession {
    private let stateHandler: (YouTubePlaybackState) -> Void
    private var loadedVideoID: String?
    private lazy var messageHandler = WeakPlaybackMessageHandler(target: self)

    lazy var webView: WKWebView = {
        let controller = WKUserContentController()
        controller.add(messageHandler, name: "playbackState")
        controller.addUserScript(WKUserScript(
            source: Self.telemetryScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.scrollView.isScrollEnabled = false
        view.isOpaque = false
        view.backgroundColor = .black
        view.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Mobile/15E148 Safari/604.1"
        return view
    }()

    init(stateHandler: @escaping (YouTubePlaybackState) -> Void) {
        self.stateHandler = stateHandler
    }

    func load(videoID: String, startAt: TimeInterval) {
        if loadedVideoID == videoID {
            play()
            return
        }
        loadedVideoID = videoID

        let referrer = "https://github.com/ScripterCarft/Video-App/"
        var components = URLComponents(string: "https://www.youtube.com/embed/\(videoID)")!
        components.queryItems = [
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "autoplay", value: "1"),
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "enablejsapi", value: "1"),
            URLQueryItem(name: "start", value: String(max(Int(startAt), 0))),
            URLQueryItem(name: "origin", value: "https://github.com"),
            URLQueryItem(name: "widget_referrer", value: referrer)
        ]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.setValue(referrer, forHTTPHeaderField: "Referer")
        request.setValue("https://github.com", forHTTPHeaderField: "Origin")
        webView.load(request)
    }

    func play() {
        evaluate("document.querySelector('video')?.play()")
    }

    func pause() {
        evaluate("document.querySelector('video')?.pause()")
    }

    func stop() {
        loadedVideoID = nil
        evaluate("document.querySelector('video')?.pause()")
        webView.stopLoading()
    }

    fileprivate func receive(_ body: Any) {
        guard
            let dictionary = body as? [String: Any],
            let currentTime = dictionary["currentTime"] as? Double,
            let duration = dictionary["duration"] as? Double,
            let paused = dictionary["paused"] as? Bool
        else { return }
        stateHandler(YouTubePlaybackState(
            currentTime: currentTime,
            duration: duration,
            isPlaying: !paused
        ))
    }

    private func evaluate(_ script: String) {
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private static let telemetryScript = """
    (() => {
      if (window.__appleVideosTelemetry) return;
      window.__appleVideosTelemetry = setInterval(() => {
        const video = document.querySelector('video');
        if (!video || !Number.isFinite(video.duration)) return;
        window.webkit.messageHandlers.playbackState.postMessage({
          currentTime: video.currentTime || 0,
          duration: video.duration || 0,
          paused: video.paused
        });
      }, 1000);
    })();
    """
}

private final class WeakPlaybackMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: YouTubePlaybackSession?

    init(target: YouTubePlaybackSession) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            target?.receive(message.body)
        }
    }
}
