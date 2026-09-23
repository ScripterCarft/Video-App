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
    private let watchProgress = WatchProgress()
    private var watchTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var isPictureInPictureActive = false
    private var isFinished = false
    private var playerWindow: UIWindow?
    private weak var previousKeyWindow: UIWindow?

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
        guard let scene = Self.activeWindowScene() else { return false }

        Self.current = self
        configurePlaybackAudio()
        showPlayerWindow(in: scene) { [weak self] in
            guard let self else { return }
            player.play()
            watchTask = Task { [weak self] in
                guard let self else { return }
                await watchProgress.track(player)
            }
        }
        metadataTask = Task { [weak self] in
            await self?.installSupplementalMetadata()
        }
        return true
    }

    // MARK: - Player window

    /// Presents the player in a separate window whose only content is an empty,
    /// transparent UIKit view controller. The app's own window, with its SwiftUI
    /// hierarchy, is never removed, re-added or updated by the presentation or
    /// by AVKit's interactive dismissal; it only shows through underneath.
    private func showPlayerWindow(in scene: UIWindowScene, onPresented: @escaping () -> Void) {
        let root = PlayerWindowRootViewController()
        root.onFirstAppearance = { [weak self, weak root] in
            guard let self, let root else { return }
            root.present(playerController, animated: true, completion: onPresented)
        }

        previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = PassthroughWindow(windowScene: scene)
        window.backgroundColor = .clear
        window.rootViewController = root
        playerWindow = window
        window.makeKeyAndVisible()
    }

    private func hidePlayerWindow() {
        guard let playerWindow else { return }
        playerWindow.isHidden = true
        self.playerWindow = nil
        previousKeyWindow?.makeKey()
        previousKeyWindow = nil
    }

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    /// Ends this playback exactly once and reports whether it counts as watched.
    private func finish() {
        guard !isFinished else { return }
        isFinished = true

        watchTask?.cancel()
        metadataTask?.cancel()
        if item.status == .failed {
            // Stream URLs can stop working (for example after a network change).
            // Resolve a fresh source on the next attempt instead of reusing it.
            let videoID = video.id
            Task { await YouTubeInnertubePlaybackResolver.shared.invalidate(videoID: videoID) }
        }
        player.pause()
        if playerController.presentingViewController != nil {
            playerController.dismiss(animated: false)
        }
        hidePlayerWindow()
        onFinish(watchProgress.reachedThreshold)
        if Self.current === self {
            Self.current = nil
        }
    }

    private func configurePlaybackAudio() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .moviePlayback)
        try? audioSession.setActive(true)
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
            guard let self, !context.isCancelled else { return }
            if isPictureInPictureActive {
                // Playback continues in PiP; only the empty window goes away.
                hidePlayerWindow()
            } else {
                finish()
            }
        }
    }

    func playerViewControllerWillStartPictureInPicture(
        _ playerViewController: AVPlayerViewController
    ) {
        isPictureInPictureActive = true
    }

    func playerViewControllerDidStartPictureInPicture(
        _ playerViewController: AVPlayerViewController
    ) {
        if playerViewController.presentingViewController == nil {
            hidePlayerWindow()
        }
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
        guard !isFinished, let scene = Self.activeWindowScene() else {
            completionHandler(false)
            return
        }
        showPlayerWindow(in: scene) {
            completionHandler(true)
        }
    }
}

// MARK: - Player window types

/// A window that only receives touches for the player it presents; touches on
/// its empty, transparent root fall through to the app window underneath.
private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self || view === rootViewController?.view ? nil : view
    }
}

/// Empty, transparent root of the player window. It presents the player once
/// it is on screen and does nothing else.
private final class PlayerWindowRootViewController: UIViewController {
    var onFirstAppearance: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let action = onFirstAppearance
        onFirstAppearance = nil
        action?()
    }
}

/// Counts how long native playback actually advanced.
@MainActor
private final class WatchProgress {
    private static let threshold: Double = 10
    private var watchedSeconds = 0.0

    var reachedThreshold: Bool { watchedSeconds >= Self.threshold }

    func track(_ player: AVPlayer) async {
        var previousTime: Double?
        while !Task.isCancelled && !reachedThreshold {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            let currentTime = player.currentTime().seconds
            if player.timeControlStatus == .playing,
               let previousTime,
               currentTime.isFinite {
                let elapsed = currentTime - previousTime
                // Ignore seeks and stalls; only advancing playback counts.
                if elapsed > 0 && elapsed < 2.5 {
                    watchedSeconds += min(elapsed, 1.5)
                }
            }
            previousTime = currentTime.isFinite ? currentTime : nil
        }
    }
}
