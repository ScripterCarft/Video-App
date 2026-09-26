import AVKit
import CoreMedia
import UIKit

/// Resolves a video into an `AVPlayer` and presents it with
/// `AVPlayerViewController` from the window's top view controller, the way a
/// UIKit app would. No SwiftUI view hosts, observes or updates the player
/// while it is on screen; AVKit owns presentation, controls and dismissal.
@MainActor
final class NativePlayback: NSObject {
    enum Outcome {
        case presented
        case fallback(diagnostic: String)
        case cancelled
        case unavailable
        /// Use Mobile Data is off in Settings and the device is on mobile data.
        case mobileDataOff
    }

    /// How a presented playback ended.
    enum Ending {
        /// The player (or Picture in Picture) was closed.
        case closed(reachedWatchThreshold: Bool)
        /// The stream could not be played; the player was dismissed.
        case failed(diagnostic: String)
    }

    /// Keeps the playback alive while it is presented or in Picture in Picture.
    private static var current: NativePlayback?

    /// Whether a native player (or its Picture in Picture) is open.
    static var isShowingPlayer: Bool {
        current != nil
    }

    private let video: Video
    private let videoDescription: String?
    private let item: AVPlayerItem
    private let player: AVPlayer
    private let playerController = AVPlayerViewController()
    private let onProgress: @MainActor (_ position: Double, _ duration: Double) -> Void
    private let onFinish: @MainActor (Ending) -> Void
    private var statusObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var notificationTokens: [NSObjectProtocol] = []
    private var watchedSeconds = 0.0
    private var lastObservedTime: Double?
    private var hasStartedPlaying = false
    private var wasPlaying = false
    private var lastProgressSave = Date.distantPast
    private var pendingStartTime: Double?
    /// The video continues from a saved position, so it already counts as
    /// started and every new position is saved.
    private let continuesSavedProgress: Bool
    private var isAwaitingResumeSeek = false
    private var isPresented = false
    private var metadataTask: Task<Void, Never>?
    private var isPictureInPictureActive = false
    private var isFinished = false

    /// Resolves a video's stream ahead of time, for example when its detail
    /// screen opens, so Play can present the player without waiting. The
    /// resolver caches the result briefly. Skipped in Low Data Mode, where
    /// prefetching is optional and Play resolves anyway.
    @discardableResult
    static func prefetch(_ video: Video) async -> ResolvedPlaybackSource? {
        guard video.source == .youtube, !NetworkConditions.shared.isConstrained else { return nil }
        return try? await YouTubeInnertubePlaybackResolver.shared.resolve(PlaybackRequest(videoID: video.id))
    }

    /// Resolves and presents native playback, starting at `startTime` when
    /// given. `onProgress` receives the position to save: periodically, on
    /// pause, at the end, on close and when the app goes to the background.
    /// `onFinish` runs once, after the player has been dismissed, Picture in
    /// Picture has been closed, or the stream failed before playback started.
    static func play(
        _ video: Video,
        description: String?,
        startTime: Double?,
        onProgress: @escaping @MainActor (_ position: Double, _ duration: Double) -> Void,
        onFinish: @escaping @MainActor (Ending) -> Void
    ) async -> Outcome {
        let settings = StreamingSettings.current()
        // A downloaded video plays from its package: offline and without data.
        let downloadURL = DownloadManager.shared.localURL(for: video)
        if downloadURL == nil, isMobileDataBlocked(settings) {
            return .mobileDataOff
        }
        // Also stops loading if the network switches to mobile data while playing.
        let assetOptions = [AVURLAssetAllowsCellularAccessKey: settings.useMobileData]

        let item: AVPlayerItem
        switch video.source {
        case .direct:
            guard let url = video.playbackURL else { return .unavailable }
            item = AVPlayerItem(asset: AVURLAsset(url: url, options: assetOptions))

        case .youtube where downloadURL != nil:
            item = AVPlayerItem(asset: AVURLAsset(url: downloadURL!))

        case .youtube:
            do {
                let source = try await YouTubeInnertubePlaybackResolver.shared.resolve(
                    PlaybackRequest(videoID: video.id)
                )
                try Task.checkCancellation()
                guard let variant = source.preferredVariant else {
                    return .fallback(diagnostic: "NO_VARIANT · The resolver returned no preferred source.")
                }

                // The player is presented right away; AVKit shows its own loading
                // state while the stream starts. A stream that cannot play is
                // reported through the item's status after presentation.
                item = AVPlayerItem(asset: AVURLAsset(url: variant.url, options: assetOptions))
                if variant.transport == .hls {
                    applyStreamingOptions(settings, to: item)
                }
            } catch {
                // URLSession reports cancellation as URLError.cancelled.
                if error is CancellationError || Task.isCancelled { return .cancelled }
                let nsError = error as NSError
                return .fallback(
                    diagnostic: "\(error.localizedDescription)\nCode: \(nsError.domain)/\(nsError.code)"
                )
            }
        }

        guard !Task.isCancelled else { return .cancelled }

        // Only one native playback at a time (for example while one is in PiP).
        current?.finish(.closed(reachedWatchThreshold: current?.reachedWatchThreshold ?? false))

        let playback = NativePlayback(
            video: video,
            description: description,
            item: item,
            startTime: startTime,
            onProgress: onProgress,
            onFinish: onFinish
        )
        return playback.present() ? .presented : .unavailable
    }

    /// True when Use Mobile Data is off in Settings and the device is on
    /// mobile data. Also checked before the embedded fallback, which cannot
    /// be kept off mobile data.
    static func isMobileDataBlocked(_ settings: StreamingSettings = .current()) -> Bool {
        !settings.useMobileData && NetworkConditions.shared.usesCellular
    }

    /// Applies the Streaming Options to an HLS item. AVPlayer applies the
    /// resolution limits to whichever network it is on while playing; the
    /// forward buffer is chosen for the network playback starts on.
    ///
    /// Measured on device: AVPlayer plays only H.264 (it skips YouTube's VP9
    /// variants), so 1080p60 is the highest quality; 720p60 averages about
    /// 2.2–2.6 Mbit/s, roughly 1 GB/hour. With the automatic buffer it loaded
    /// 73–109 s ahead, for a low-bitrate video the whole video, which is lost
    /// when a video is closed early.
    private static func applyStreamingOptions(_ settings: StreamingSettings, to item: AVPlayerItem) {
        let network = NetworkConditions.shared
        let hd = CGSize(width: 1_280, height: 720)
        // Low Data Mode asks apps to reduce streaming quality on any network.
        let isLowData = network.isConstrained

        if isLowData || settings.wifiQuality == .dataSaver {
            item.preferredMaximumResolution = hd
        }
        if isLowData || settings.mobileDataQuality == .automatic {
            item.preferredMaximumResolutionForExpensiveNetworks = hd
        }

        // 60 s bounds what an early close throws away while AVPlayer still
        // loads in large bursts, so the radio can sleep in between. Wi-Fi at
        // High Quality keeps the automatic buffer: Wi-Fi data is not limited,
        // and long bursts are the cheapest for the radio.
        if isLowData || network.isExpensive || settings.wifiQuality == .dataSaver {
            item.preferredForwardBufferDuration = 60
        }
    }

    private init(
        video: Video,
        description: String?,
        item: AVPlayerItem,
        startTime: Double?,
        onProgress: @escaping @MainActor (Double, Double) -> Void,
        onFinish: @escaping @MainActor (Ending) -> Void
    ) {
        self.video = video
        videoDescription = description?.collapsedWhitespace
        self.item = item
        self.onProgress = onProgress
        self.onFinish = onFinish
        continuesSavedProgress = startTime != nil
        player = AVPlayer(playerItem: item)
        super.init()

        item.externalMetadata = playerMetadata(description: videoDescription)
        playerController.player = player
        playerController.delegate = self
        pendingStartTime = startTime
        isAwaitingResumeSeek = startTime != nil
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            // Handle readiness right away when it arrives on the main thread, so
            // the resume seek is issued before the first frame is shown.
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.itemStatusDidChange()
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.itemStatusDidChange()
                }
            }
        }
    }

    private func present() -> Bool {
        guard let presenter = Self.topViewController() else { return false }

        Self.current = self
        presenter.present(playerController, animated: true) { [weak self] in
            guard let self else { return }
            isPresented = true
            startWatchTracking()
            startPlaybackIfReady()
        }
        metadataTask = Task { [weak self] in
            await self?.installSupplementalMetadata()
        }
        return true
    }

    /// Starts playback once the player is on screen and, when resuming, the
    /// seek to the saved position has finished, so the first frame shown is
    /// the saved position rather than the beginning.
    private func startPlaybackIfReady() {
        guard isPresented, !isAwaitingResumeSeek, !isFinished else { return }
        player.play()
    }

    /// Seeks to the saved position as soon as the item is ready (seeking
    /// requires `readyToPlay`). A stream that fails before any playback falls
    /// back to the embedded player; later failures are left to AVKit, which
    /// shows its own error state.
    private func itemStatusDidChange() {
        guard !isFinished else { return }

        if item.status == .readyToPlay, let pendingStartTime {
            self.pendingStartTime = nil
            // Land on the keyframe up to five seconds before the saved position:
            // faster than an exact seek, and never past where the viewer stopped.
            player.seek(
                to: CMTime(seconds: pendingStartTime, preferredTimescale: 600),
                toleranceBefore: CMTime(seconds: 5, preferredTimescale: 600),
                toleranceAfter: .zero
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    isAwaitingResumeSeek = false
                    startPlaybackIfReady()
                }
            }
            return
        }
        guard item.status == .failed, !hasStartedPlaying else { return }

        let diagnostic = item.error.map { error in
            let nsError = error as NSError
            return "\(error.localizedDescription)\nCode: \(nsError.domain)/\(nsError.code)"
        } ?? "AVPLAYER_FAILED · The stream could not be played."
        finish(.failed(diagnostic: diagnostic))
        if playerController.presentingViewController != nil {
            playerController.dismiss(animated: true)
        }
    }

    /// Ends this playback exactly once.
    private func finish(_ ending: Ending) {
        guard !isFinished else { return }
        isFinished = true

        statusObservation?.invalidate()
        statusObservation = nil
        if case .closed = ending {
            saveProgress()
        }
        stopWatchTracking()
        metadataTask?.cancel()
        if item.status == .failed {
            // Stream URLs can stop working (for example after a network change).
            // Resolve a fresh source on the next attempt instead of reusing it.
            let videoID = video.id
            Task { await YouTubeInnertubePlaybackResolver.shared.invalidate(videoID: videoID) }
        }
        player.pause()
        onFinish(ending)
        if Self.current === self {
            Self.current = nil
        }
    }

    /// The key window's topmost presented view controller.
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first(where: \.isKeyWindow)

        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    // MARK: - Now Playing metadata

    private func installSupplementalMetadata() async {
        let resolvedDescription = await resolvedPlayerDescription()
        guard !Task.isCancelled else { return }

        item.externalMetadata = playerMetadata(description: resolvedDescription)

        guard let artworkData = await loadArtworkData(),
              !Task.isCancelled
        else {
            return
        }

        item.externalMetadata = playerMetadata(
            description: resolvedDescription,
            artworkData: artworkData
        )
    }

    private func resolvedPlayerDescription() async -> String? {
        if let videoDescription {
            return videoDescription
        }
        guard video.source == .youtube,
              let details = try? await YouTubeService.shared.details(for: video.id)
        else {
            return nil
        }
        return details.description?.collapsedWhitespace
    }

    private func loadArtworkData() async -> Data? {
        // 1280 pixels wide gives the 720×720 square artwork its full height.
        let request = ArtworkRequest(
            candidates: video.artworkCandidates(lowData: NetworkConditions.shared.isConstrained),
            requiresSixteenByNine: video.source == .youtube,
            maxPixelWidth: 1280
        )
        guard let image = await ArtworkLoader.firstImage(for: request) else {
            return nil
        }
        guard !Task.isCancelled else { return nil }
        return await NowPlayingArtwork.jpegData(from: image)
    }

    private func playerMetadata(
        description: String?,
        artworkData: Data? = nil
    ) -> [AVMetadataItem] {
        var metadata = [
            metadataItem(identifier: .commonIdentifierTitle, value: video.title),
            metadataItem(identifier: .iTunesMetadataTrackSubTitle, value: video.channelName),
            metadataItem(identifier: .commonIdentifierArtist, value: video.channelName)
        ]
        if let description {
            metadata.append(
                metadataItem(identifier: .commonIdentifierDescription, value: description)
            )
        }
        if let artworkData {
            metadata.append(artworkMetadataItem(data: artworkData))
        }
        return metadata
    }

    private func metadataItem(
        identifier: AVMetadataIdentifier,
        value: String
    ) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item
    }

    private func artworkMetadataItem(data: Data) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierArtwork
        item.value = data as NSData
        item.dataType = kCMMetadataBaseDataType_JPEG as String
        item.extendedLanguageTag = "und"
        return item
    }
}

// MARK: - AVPlayerViewControllerDelegate

extension NativePlayback: @preconcurrency AVPlayerViewControllerDelegate {
    func playerViewController(
        _ playerViewController: AVPlayerViewController,
        willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
    ) {
        coordinator.animate(alongsideTransition: nil) { [weak self] context in
            guard let self, !context.isCancelled, !isPictureInPictureActive else { return }
            finish(.closed(reachedWatchThreshold: reachedWatchThreshold))
        }
    }

    func playerViewControllerWillStartPictureInPicture(
        _ playerViewController: AVPlayerViewController
    ) {
        isPictureInPictureActive = true
    }

    func playerViewControllerDidStopPictureInPicture(
        _ playerViewController: AVPlayerViewController
    ) {
        isPictureInPictureActive = false
        // Closing PiP without restoring the full-screen player ends playback.
        if playerViewController.presentingViewController == nil {
            finish(.closed(reachedWatchThreshold: reachedWatchThreshold))
        }
    }

    func playerViewController(
        _ playerViewController: AVPlayerViewController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        isPictureInPictureActive = false
    }

    func playerViewController(
        _ playerViewController: AVPlayerViewController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping @Sendable (Bool) -> Void
    ) {
        if playerViewController.presentingViewController != nil {
            completionHandler(true)
            return
        }
        guard !isFinished, let presenter = Self.topViewController() else {
            completionHandler(false)
            return
        }
        presenter.present(playerViewController, animated: true) {
            completionHandler(true)
        }
    }
}

// MARK: - Watch history and progress

private extension NativePlayback {
    static let watchThreshold: Double = 10
    /// How often the position is saved while playing. Pausing, reaching the
    /// end, closing the player and backgrounding the app save immediately.
    static let progressSaveInterval: TimeInterval = 5

    var reachedWatchThreshold: Bool { watchedSeconds >= Self.watchThreshold }

    /// AVPlayer reports playback time through its periodic time observer, which
    /// also fires when time jumps and when playback starts or stops.
    func startWatchTracking() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.recordPlayback(at: time.seconds)
            }
        }

        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: item,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.saveProgress(reachedEnd: true)
                }
            },
            // iOS may terminate a backgrounded app without further notice.
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.saveProgress()
                }
            }
        ]
    }

    func stopWatchTracking() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens = []
    }

    func recordPlayback(at seconds: Double) {
        defer { self.lastObservedTime = seconds.isFinite ? seconds : nil }

        let isPlaying = player.timeControlStatus == .playing
        if isPlaying {
            hasStartedPlaying = true
        }
        if isPlaying != wasPlaying {
            wasPlaying = isPlaying
            if !isPlaying {
                saveProgress()
            }
        } else if isPlaying, Date.now.timeIntervalSince(lastProgressSave) >= Self.progressSaveInterval {
            saveProgress()
        }

        guard isPlaying,
              let previous = lastObservedTime,
              seconds.isFinite
        else { return }

        let elapsed = seconds - previous
        // Ignore seeks and stalls.
        if elapsed > 0 && elapsed < 2.5 {
            watchedSeconds += min(elapsed, 1.5)
        }
    }

    /// Reports the current position once the video counts as started, the
    /// same rule that adds it to History: after 10 s of actual playback
    /// (seeking does not count), or at once when it continues from a saved
    /// position. Opening a video briefly, or a stream that fails, never saves
    /// or overwrites progress.
    func saveProgress(reachedEnd: Bool = false) {
        let countsAsStarted = reachedWatchThreshold || (continuesSavedProgress && hasStartedPlaying)
        guard countsAsStarted || reachedEnd else { return }
        let duration = item.duration.seconds
        let position = reachedEnd ? duration : player.currentTime().seconds
        onProgress(position, duration)
        lastProgressSave = .now
    }
}
