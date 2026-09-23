import AVKit
import CoreMedia
import UIKit

/// Resolves a video into an `AVPlayer` and presents it with
/// `AVPlayerViewController` from the window's top view controller, the way a
/// UIKit app would. No SwiftUI view hosts, observes or updates the player
/// while it is on screen; AVKit owns presentation, controls and dismissal.
@MainActor
final class NativePlayback: NSObject {
    enum Result {
        case presented
        case fallback(diagnostic: String)
        case cancelled
        case unavailable
    }

    /// Keeps the playback alive while it is presented or in Picture in Picture.
    private static var current: NativePlayback?

    private let video: Video
    private let videoDescription: String?
    private let item: AVPlayerItem
    private let player: AVPlayer
    private let playerController = AVPlayerViewController()
    private let onFinish: @MainActor (_ reachedWatchThreshold: Bool) -> Void
    private var timeObserver: Any?
    private var watchedSeconds = 0.0
    private var lastObservedTime: Double?
    private var metadataTask: Task<Void, Never>?
    private var isPictureInPictureActive = false
    private var isFinished = false

    /// Resolves and presents native playback. `onFinish` runs once, after the
    /// player has been dismissed (or Picture in Picture has been closed).
    static func play(
        _ video: Video,
        description: String?,
        onFinish: @escaping @MainActor (_ reachedWatchThreshold: Bool) -> Void
    ) async -> Result {
        let item: AVPlayerItem
        switch video.source {
        case .direct:
            guard let url = video.playbackURL else { return .unavailable }
            item = AVPlayerItem(url: url)

        case .youtube:
            do {
                let source = try await YouTubeInnertubePlaybackResolver.shared.resolve(
                    PlaybackRequest(videoID: video.id)
                )
                try Task.checkCancellation()
                guard let variant = source.preferredVariant else {
                    return .fallback(diagnostic: "NO_VARIANT · The resolver returned no preferred source.")
                }

                let asset = AVURLAsset(url: variant.url)
                let isPlayable = try await asset.load(.isPlayable)
                try Task.checkCancellation()
                guard isPlayable else {
                    return .fallback(
                        diagnostic: "AVPLAYER_REJECTED · \(variant.qualityLabel ?? "Unknown quality") · \(variant.mimeType)"
                    )
                }

                item = AVPlayerItem(asset: asset)
                if variant.transport == .hls {
                    item.preferredMaximumResolutionForExpensiveNetworks = CGSize(
                        width: 1_280,
                        height: 720
                    )
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
        current?.finish()

        let playback = NativePlayback(video: video, description: description, item: item, onFinish: onFinish)
        return playback.present() ? .presented : .unavailable
    }

    private init(
        video: Video,
        description: String?,
        item: AVPlayerItem,
        onFinish: @escaping @MainActor (Bool) -> Void
    ) {
        self.video = video
        videoDescription = description?.collapsedWhitespace
        self.item = item
        self.onFinish = onFinish
        player = AVPlayer(playerItem: item)
        super.init()

        item.externalMetadata = playerMetadata(description: videoDescription)
        player.allowsExternalPlayback = true
        playerController.player = player
        playerController.allowsPictureInPicturePlayback = true
        playerController.delegate = self
    }

    private func present() -> Bool {
        guard let presenter = Self.topViewController() else { return false }

        Self.current = self
        presenter.present(playerController, animated: true) { [weak self] in
            guard let self else { return }
            player.play()
            startWatchTracking()
        }
        metadataTask = Task { [weak self] in
            await self?.installSupplementalMetadata()
        }
        return true
    }

    /// Ends this playback exactly once and reports whether it counts as watched.
    private func finish() {
        guard !isFinished else { return }
        isFinished = true

        stopWatchTracking()
        metadataTask?.cancel()
        if item.status == .failed {
            // Stream URLs can stop working (for example after a network change).
            // Resolve a fresh source on the next attempt instead of reusing it.
            let videoID = video.id
            Task { await YouTubeInnertubePlaybackResolver.shared.invalidate(videoID: videoID) }
        }
        player.pause()
        onFinish(reachedWatchThreshold)
        if Self.current === self {
            Self.current = nil
        }
    }

    private static func topViewController() -> UIViewController? {
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
        guard let image = await ArtworkLoader.firstImage(
            from: video.artworkURLs(for: .hero),
            requiresSixteenByNine: video.source == .youtube
        ) else {
            return nil
        }
        return Self.squareArtworkData(from: image)
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
        return item
    }

    private static func squareArtworkData(
        from image: UIImage,
        pixelSize: CGFloat = 720
    ) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }

        let targetSize = CGSize(width: pixelSize, height: pixelSize)
        let scale = max(
            targetSize.width / image.size.width,
            targetSize.height / image.size.height
        )
        let drawSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let drawRect = CGRect(
            x: (targetSize.width - drawSize.width) / 2,
            y: (targetSize.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let squareImage = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: drawRect)
        }
        return squareImage.jpegData(compressionQuality: 0.9)
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
            finish()
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
            finish()
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

// MARK: - Watch history

private extension NativePlayback {
    static let watchThreshold: Double = 10

    var reachedWatchThreshold: Bool { watchedSeconds >= Self.watchThreshold }

    /// AVPlayer reports playback time through its periodic time observer, which
    /// also fires on seeks and rate changes; only advancing playback counts.
    func startWatchTracking() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.recordPlayback(at: time.seconds)
            }
        }
    }

    func stopWatchTracking() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    func recordPlayback(at seconds: Double) {
        defer { self.lastObservedTime = seconds.isFinite ? seconds : nil }
        guard player.timeControlStatus == .playing,
              let previous = lastObservedTime,
              seconds.isFinite
        else { return }

        let elapsed = seconds - previous
        // Ignore seeks and stalls.
        if elapsed > 0 && elapsed < 2.5 {
            watchedSeconds += min(elapsed, 1.5)
        }
    }
}
