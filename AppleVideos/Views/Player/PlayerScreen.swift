import AVKit
import CoreMedia
import SwiftUI

struct PlayerScreen: View {
    let video: Video
    let description: String?
    let onPreparationFinished: () -> Void
    let onDismiss: () -> Void
    @Environment(LibraryStore.self) private var library
    @State private var nativePlayer: AVPlayer?
    @State private var usesEmbeddedFallback = false
    @State private var isResolving = true
    @State private var didMarkWatched = false
    @State private var diagnosticMessage: String?
    @State private var isPictureInPictureActive = false

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            if usesEmbeddedFallback {
                Color.black.ignoresSafeArea()
            }

            Group {
                if let nativePlayer {
                    NativePlayerPresenter(
                        player: nativePlayer,
                        isPictureInPictureActive: $isPictureInPictureActive,
                        onDismiss: { closePlayback() }
                    )
                } else if usesEmbeddedFallback, video.source == .youtube {
                    YouTubePlayerView(videoID: video.id) {
                        markWatchedOnce()
                    }
                }
            }
            .ignoresSafeArea()

            if usesEmbeddedFallback {
                VStack {
                    HStack {
                        Spacer()
                        Button("Close", systemImage: "xmark") { closePlayback() }
                            .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
                .padding()
            }
        }
        .statusBarHidden(usesEmbeddedFallback)
        .allowsHitTesting(usesEmbeddedFallback)
        .task(id: video.id) {
            await preparePlayback()
        }
        .task(id: nativePlayer != nil) {
            guard let player = nativePlayer else { return }
            var previousTime: Double?
            var watchedSeconds = 0.0

            while !Task.isCancelled && !didMarkWatched {
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
                if watchedSeconds >= 10 {
                    markWatchedOnce()
                }
            }
        }
        #if DEBUG
        .alert(
            "Native Playback Debug",
            isPresented: Binding(
                get: { diagnosticMessage != nil },
                set: { if !$0 { diagnosticMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(diagnosticMessage ?? "")
        }
        #endif
    }

    @MainActor
    private func closePlayback() {
        if nativePlayer?.currentItem?.status == .failed {
            // Stream URLs can stop working (for example after a network change).
            // Resolve a fresh source on the next attempt instead of reusing it.
            let videoID = video.id
            Task { await YouTubeInnertubePlaybackResolver.shared.invalidate(videoID: videoID) }
        }
        nativePlayer?.pause()
        onDismiss()
    }

    @MainActor
    private func preparePlayback() async {
        // Presenting AVKit can restart SwiftUI's view task. Keep the same player.
        guard isResolving, nativePlayer == nil, !usesEmbeddedFallback else { return }

        switch video.source {
        case .direct:
            guard let url = video.playbackURL else {
                isResolving = false
                onDismiss()
                return
            }
            let item = AVPlayerItem(url: url)
            let player = makePlayer(item: item)
            nativePlayer = player
            isResolving = false
            onPreparationFinished()
            configurePlaybackAudio()
            await installSupplementalMetadata(on: item)

        case .youtube:
            do {
                let source = try await YouTubeInnertubePlaybackResolver.shared.resolve(
                    PlaybackRequest(videoID: video.id)
                )
                try Task.checkCancellation()
                guard let variant = source.preferredVariant else {
                    showEmbeddedFallback("NO_VARIANT · The resolver returned no preferred source.")
                    return
                }

                let asset = AVURLAsset(url: variant.url)
                let isPlayable = try await asset.load(.isPlayable)
                try Task.checkCancellation()
                guard isPlayable else {
                    showEmbeddedFallback(
                        "AVPLAYER_REJECTED · \(variant.qualityLabel ?? "Unknown quality") · \(variant.mimeType)"
                    )
                    return
                }

                let item = AVPlayerItem(asset: asset)
                if variant.transport == .hls {
                    item.preferredMaximumResolutionForExpensiveNetworks = CGSize(
                        width: 1_280,
                        height: 720
                    )
                }
                let player = makePlayer(item: item)
                nativePlayer = player
                isResolving = false
                onPreparationFinished()
                configurePlaybackAudio()
                await installSupplementalMetadata(on: item)
            } catch is CancellationError {
                return
            } catch {
                let nsError = error as NSError
                showEmbeddedFallback(
                    "\(error.localizedDescription)\nCode: \(nsError.domain)/\(nsError.code)"
                )
            }
        }
    }

    @MainActor
    private func makePlayer(item: AVPlayerItem) -> AVPlayer {
        item.externalMetadata = playerMetadata(description: description?.collapsedWhitespace)
        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        return player
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

    @MainActor
    private func installSupplementalMetadata(on playerItem: AVPlayerItem) async {
        let resolvedDescription = await resolvedPlayerDescription()
        guard !Task.isCancelled else { return }

        playerItem.externalMetadata = playerMetadata(description: resolvedDescription)

        guard let artworkData = await loadArtworkData(),
              !Task.isCancelled
        else {
            return
        }

        playerItem.externalMetadata = playerMetadata(
            description: resolvedDescription,
            artworkData: artworkData
        )
    }

    private func resolvedPlayerDescription() async -> String? {
        if let description = description?.collapsedWhitespace {
            return description
        }
        guard video.source == .youtube,
              let details = try? await YouTubeService.shared.details(for: video.id)
        else {
            return nil
        }
        return details.description?.collapsedWhitespace
    }

    @MainActor
    private func loadArtworkData() async -> Data? {
        guard let image = await ArtworkLoader.firstImage(
            from: video.artworkURLs(for: .hero),
            requiresSixteenByNine: video.source == .youtube
        ) else {
            return nil
        }
        return Self.squareArtworkData(from: image)
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

    @MainActor
    private func configurePlaybackAudio() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .moviePlayback)
        try? audioSession.setActive(true)
    }

    @MainActor
    private func markWatchedOnce() {
        guard !didMarkWatched else { return }
        didMarkWatched = true
        library.markWatched(video)
    }

    @MainActor
    private func showEmbeddedFallback(_ diagnostic: String) {
        nativePlayer?.pause()
        nativePlayer = nil
        isResolving = false
        onPreparationFinished()
        diagnosticMessage = diagnostic
        usesEmbeddedFallback = true
    }
}

private struct NativePlayerPresenter: UIViewControllerRepresentable {
    let player: AVPlayer
    @Binding var isPictureInPictureActive: Bool
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isPictureInPictureActive: $isPictureInPictureActive, onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> PlayerPresentationHostViewController {
        let host = PlayerPresentationHostViewController(player: player, coordinator: context.coordinator)
        context.coordinator.host = host
        return host
    }

    func updateUIViewController(_ host: PlayerPresentationHostViewController, context: Context) {
        context.coordinator.onDismiss = onDismiss
        host.update(player: player)
    }

    static func dismantleUIViewController(
        _ host: PlayerPresentationHostViewController,
        coordinator: Coordinator
    ) {
        host.dismissPresentedPlayer()
    }

    final class Coordinator: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
        private var pictureInPictureBinding: Binding<Bool>
        var isPictureInPictureActive: Bool { pictureInPictureBinding.wrappedValue }
        var onDismiss: () -> Void
        weak var host: PlayerPresentationHostViewController?
        private var hasDismissed = false

        init(isPictureInPictureActive: Binding<Bool>, onDismiss: @escaping () -> Void) {
            pictureInPictureBinding = isPictureInPictureActive
            self.onDismiss = onDismiss
        }

        @MainActor
        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator transition: UIViewControllerTransitionCoordinator
        ) {
            transition.animate(alongsideTransition: nil) { [weak self] context in
                guard !context.isCancelled else { return }
                self?.playerDidDismiss()
            }
        }

        func playerDidDismiss() {
            guard !hasDismissed, !isPictureInPictureActive else { return }
            hasDismissed = true
            onDismiss()
        }

        func playerViewControllerWillStartPictureInPicture(
            _ playerViewController: AVPlayerViewController
        ) {
            pictureInPictureBinding.wrappedValue = true
        }

        func playerViewControllerDidStopPictureInPicture(
            _ playerViewController: AVPlayerViewController
        ) {
            pictureInPictureBinding.wrappedValue = false
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            failedToStartPictureInPictureWithError error: Error
        ) {
            pictureInPictureBinding.wrappedValue = false
            print("Picture in Picture failed: \(error.localizedDescription)")
        }

        @MainActor
        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping @Sendable (Bool) -> Void
        ) {
            guard let host else {
                completionHandler(false)
                return
            }
            host.restorePlayerInterface(completionHandler: completionHandler)
        }
    }
}

private final class PlayerPresentationHostViewController: UIViewController {
    private let playerController = AVPlayerViewController()
    private weak var coordinator: NativePlayerPresenter.Coordinator?
    private var hasStartedPresentation = false
    private var isPresentingPlayer = false
    private var isBeingTornDown = false

    init(player: AVPlayer, coordinator: NativePlayerPresenter.Coordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
        playerController.delegate = coordinator
        playerController.player = player
        playerController.allowsPictureInPicturePlayback = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // DIAGNOSTIC (do not merge): color the layers behind AVKit so a
        // screen recording shows which one produces the black edge.
        view.window?.backgroundColor = .magenta
        view.window?.rootViewController?.view.backgroundColor = .orange
        guard !hasStartedPresentation else { return }
        hasStartedPresentation = true
        presentPlayer(animated: true) {
            self.playerController.player?.play()
        }
    }

    func update(player: AVPlayer) {
        if playerController.player !== player {
            playerController.player = player
        }
    }

    func restorePlayerInterface(completionHandler: @escaping (Bool) -> Void) {
        if presentedViewController != nil {
            completionHandler(true)
        } else if isPresentingPlayer || isBeingTornDown {
            completionHandler(false)
        } else {
            presentPlayer(animated: true) {
                completionHandler(true)
            }
        }
    }

    func dismissPresentedPlayer() {
        isBeingTornDown = true
        playerController.dismiss(animated: false)
    }

    private func presentPlayer(animated: Bool, completion: (() -> Void)? = nil) {
        guard !isPresentingPlayer, presentedViewController == nil, !isBeingTornDown else { return }
        isPresentingPlayer = true
        present(playerController, animated: animated) {
            self.isPresentingPlayer = false
            completion?()
        }
    }
}

