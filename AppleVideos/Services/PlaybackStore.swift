import AVFoundation
import Foundation
import Observation
@preconcurrency import WebKit

@MainActor
@Observable
final class PlaybackStore {
    enum Engine: Sendable {
        case resolving
        case native
        case youtubeEmbed
    }

    private(set) var currentVideo: Video?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var engine: Engine = .resolving
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
    @ObservationIgnored private var resolutionTask: Task<Void, Never>?
    @ObservationIgnored private var nativeTimeObserver: Any?

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
            resolutionTask?.cancel()
            clearNativePlayer()
            youtubeSession.stop()
            currentVideo = video
            currentTime = 0
            duration = Self.seconds(from: video.duration) ?? 0
        }

        switch video.source {
        case .youtube:
            if !isNewVideo {
                switch engine {
                case .native:
                    directPlayer?.play()
                    isPlaying = true
                case .youtubeEmbed:
                    youtubeSession.load(videoID: video.id, startAt: currentTime)
                    isPlaying = true
                case .resolving:
                    break
                }
            } else {
                beginNativeResolution(for: video)
            }
        case .direct:
            engine = .native
            if directPlayer == nil, let url = video.playbackURL {
                installNativePlayer(url: url)
            }
            directPlayer?.play()
            isPlaying = true
        }

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
        guard currentVideo != nil else { return }
        guard engine != .resolving else { return }
        isPlaying.toggle()
        switch engine {
        case .youtubeEmbed:
            isPlaying ? youtubeSession.play() : youtubeSession.pause()
        case .native:
            isPlaying ? directPlayer?.play() : directPlayer?.pause()
        case .resolving:
            break
        }
    }

    func stop() {
        resolutionTask?.cancel()
        resolutionTask = nil
        youtubeSession.stop()
        clearNativePlayer()
        currentVideo = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        engine = .resolving
        isExpanded = false
    }

    private func beginNativeResolution(for video: Video) {
        engine = .resolving
        isPlaying = false

        resolutionTask = Task { [weak self] in
            guard let self else { return }

            do {
                let source = try await YouTubeInnertubePlaybackResolver.shared.resolve(
                    PlaybackRequest(videoID: video.id)
                )
                try Task.checkCancellation()
                guard currentVideo?.id == video.id,
                      let variant = source.preferredVariant
                else { return }

                let asset = AVURLAsset(url: variant.url)
                let isPlayable = try await asset.load(.isPlayable)
                try Task.checkCancellation()
                guard isPlayable, currentVideo?.id == video.id else {
                    startYouTubeFallback(for: video)
                    return
                }

                installNativePlayer(asset: asset)
                engine = .native
                directPlayer?.play()
                isPlaying = true
            } catch is CancellationError {
                return
            } catch {
                guard currentVideo?.id == video.id else { return }
                startYouTubeFallback(for: video)
            }
        }
    }

    private func startYouTubeFallback(for video: Video) {
        clearNativePlayer()
        engine = .youtubeEmbed
        youtubeSession.load(videoID: video.id, startAt: currentTime)
        isPlaying = true
    }

    private func installNativePlayer(url: URL) {
        installNativePlayer(asset: AVURLAsset(url: url))
    }

    private func installNativePlayer(asset: AVURLAsset) {
        clearNativePlayer()
        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        nativeTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self, weak player] time in
            MainActor.assumeIsolated {
                guard let self, let player else { return }
                currentTime = time.seconds.isFinite ? time.seconds : 0
                if let itemDuration = player.currentItem?.duration.seconds,
                   itemDuration.isFinite,
                   itemDuration > 0 {
                    duration = itemDuration
                }
                isPlaying = player.timeControlStatus == .playing
            }
        }
        directPlayer = player
    }

    private func clearNativePlayer() {
        if let nativeTimeObserver, let directPlayer {
            directPlayer.removeTimeObserver(nativeTimeObserver)
        }
        nativeTimeObserver = nil
        directPlayer?.pause()
        directPlayer = nil
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
