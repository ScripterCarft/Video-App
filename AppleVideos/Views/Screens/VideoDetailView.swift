import AVKit
import CoreMedia
import SwiftUI
import WebKit

struct VideoDetailView: View {
    let video: Video
    let transition: Namespace.ID
    let transitionID: String

    @Environment(LibraryStore.self) private var library
    @State private var showPlayer = false
    @State private var isPreparingPlayback = false
    @State private var feedback = 0
    @State private var showDescription = false
    @State private var loadedDescription: String?
    @State private var loadedBadges: [String]?
    @State private var detailsLoadFinished = false

    init(video: Video, transition: Namespace.ID, transitionID: String? = nil) {
        self.video = video
        self.transition = transition
        self.transitionID = transitionID ?? video.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                detailStage

                VStack(alignment: .leading, spacing: 8) {
                    Text("Up Next")
                        .font(.title2.bold())
                    Text("More recommendations will become personal as the Apple Videos algorithm evolves.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 30)
        }
        .background(.black)
        .foregroundStyle(.white)
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if let url = video.youtubeURL {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Section("Add to Playlist") {
                            ForEach(library.playlists) { playlist in
                                Button(playlist.name) {
                                    library.add(video, to: playlist.id)
                                    feedback += 1
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More options")

                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                }
            }
        }
        .navigationTransition(.zoom(sourceID: transitionID, in: transition))
        .overlay {
            if showPlayer {
                PlayerScreen(
                    video: video,
                    description: visibleDescription,
                    onPreparationFinished: { isPreparingPlayback = false },
                    onDismiss: {
                        isPreparingPlayback = false
                        showPlayer = false
                    }
                )
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showDescription) {
            DescriptionSheet(video: video, description: visibleDescription)
                .presentationDetents([.fraction(0.55), .fraction(0.8)])
                .presentationDragIndicator(.visible)
        }
        .task(id: video.id) {
            loadedDescription = nil
            loadedBadges = nil
            detailsLoadFinished = false

            guard video.source == .youtube else {
                detailsLoadFinished = true
                return
            }
            defer { detailsLoadFinished = true }

            guard let details = try? await YouTubeService.shared.details(for: video.id) else {
                return
            }
            loadedDescription = details.description
            loadedBadges = details.badges.isEmpty ? nil : details.badges
        }
        .sensoryFeedback(.selection, trigger: feedback)
    }

    private var visibleDescription: String? {
        for candidate in [video.descriptionText, loadedDescription].compactMap({ $0 }) {
            let normalized = candidate.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if !normalized.isEmpty { return normalized }
        }
        return nil
    }

    private var visibleBadges: [String] {
        let original = video.badges ?? []
        let verified = loadedBadges ?? []
        let resolutions = Set(["8K", "4K", "HD", "SD"])
        let resolution = verified.first(where: resolutions.contains)
            ?? original.first(where: resolutions.contains)
        let supported = ["HDR", "CC", "SDH", "360°", "LIVE", "PREMIERE", "UPCOMING"]
        let combined = Set(original + verified)
        return [resolution].compactMap { $0 } + supported.filter(combined.contains)
    }

    private var textMetadata: [String] {
        [video.formattedDuration, video.viewCountText, video.publishedText]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
    }

    private var detailStage: some View {
        GeometryReader { geometry in
            let stageHeight = geometry.size.height

            ZStack(alignment: .bottomLeading) {
                VideoHeroArtwork(video: video, stageAspectRatio: 2.0 / 3.0)
                    .frame(width: geometry.size.width, height: stageHeight)

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.38),
                        .init(color: .black.opacity(0.08), location: 0.55),
                        .init(color: .black.opacity(0.3), location: 0.72),
                        .init(color: .black.opacity(0.62), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                detailInformation
            }
            .clipped()
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
    }

    private var detailInformation: some View {
        VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .center, spacing: 5) {
                    Text(video.title)
                        .font(.title.bold())
                        .lineLimit(3)
                    Text(video.channelName)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.62), radius: 9, y: 2)

                HStack(spacing: 10) {
                    Spacer(minLength: 0)

                    Button {
                        if isPreparingPlayback {
                            showPlayer = false
                            isPreparingPlayback = false
                            return
                        }
                        isPreparingPlayback = true
                        showPlayer = true
                        feedback += 1
                    } label: {
                        Group {
                            if isPreparingPlayback {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(.black)
                                    Text("Cancel")
                                }
                            } else {
                                Label("Play", systemImage: "play.fill")
                            }
                        }
                            .font(.headline)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 26)
                            .frame(minWidth: 190, minHeight: 50)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        library.toggleSaved(video)
                        feedback += 1
                    } label: {
                        Image(systemName: library.isSaved(video) ? "checkmark" : "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay {
                                Circle()
                                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(library.isSaved(video) ? "Remove from Saved" : "Add to Saved")

                    Spacer(minLength: 0)
                }

                if let description = visibleDescription {
                    DescriptionPreview(text: description) {
                        showDescription = true
                    }
                } else if video.source == .youtube && !detailsLoadFinished {
                    DescriptionPlaceholder()
                }

                HStack(spacing: 7) {
                    ForEach(Array(textMetadata.enumerated()), id: \.offset) { index, item in
                        if index > 0 {
                            Text("·")
                                .foregroundStyle(.white.opacity(0.42))
                        }
                        Text(item)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }

                    ForEach(visibleBadges, id: \.self) { badge in
                        MetadataBadge(text: badge)
                    }
                }
                .font(.footnote)
                .minimumScaleFactor(0.86)
                .shadow(color: .black.opacity(0.56), radius: 7, y: 2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }
}

private struct DescriptionPlaceholder: View {
    var body: some View {
        Text("Loading video description\nLoading video description")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.72))
            .lineLimit(2)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
    }
}

private struct DescriptionPreview: View {
    let text: String
    let onMore: () -> Void

    @State private var limitedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var isTruncated: Bool {
        limitedHeight > 0 && fullHeight > limitedHeight + 0.5
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .shadow(color: .black.opacity(0.58), radius: 8, y: 2)
                .background(alignment: .topLeading) {
                    Text(text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            fullHeight = height
                        }
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    limitedHeight = height
                }
                .mask {
                    if isTruncated {
                        VStack(spacing: 0) {
                            Color.white
                            HStack(spacing: 0) {
                                Color.white
                                LinearGradient(
                                    colors: [.white, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 84)
                            }
                        }
                    } else {
                        Color.white
                    }
                }

            if isTruncated {
                Button("MORE", action: onMore)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }
}

private struct DescriptionSheet: View {
    let video: Video
    let description: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(video.title)
                        .font(.title2.bold())
                    Text(video.channelName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(description ?? "No description is available for this video.")
                        .font(.body)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct MetadataBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(0.2)
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
            }
    }
}

private struct PlayerScreen: View {
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
    }

    @MainActor
    private func closePlayback() {
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
        item.externalMetadata = playerMetadata(description: normalizedMetadataText(description))
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

    private func normalizedMetadataText(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
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
        if let description = normalizedMetadataText(description) {
            return description
        }
        guard video.source == .youtube,
              let details = try? await YouTubeService.shared.details(for: video.id)
        else {
            return nil
        }
        return normalizedMetadataText(details.description)
    }

    @MainActor
    private func loadArtworkData() async -> Data? {
        for url in video.artworkURLs(for: .hero) {
            guard !Task.isCancelled else { return nil }

            var request = URLRequest(
                url: url,
                cachePolicy: .returnCacheDataElseLoad,
                timeoutInterval: 20
            )
            request.setValue(
                "image/avif,image/webp,image/*,*/*;q=0.8",
                forHTTPHeaderField: "Accept"
            )

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode,
                  let image = UIImage(data: data),
                  video.source != .youtube || Self.isSixteenByNine(image.size),
                  let artworkData = Self.squareArtworkData(from: image)
            else {
                continue
            }
            return artworkData
        }
        return nil
    }

    private func artworkMetadataItem(data: Data) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierArtwork
        item.value = data as NSData
        item.dataType = kCMMetadataBaseDataType_JPEG as String
        return item
    }

    private static func isSixteenByNine(_ size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        return abs((size.width / size.height) - (16.0 / 9.0)) < 0.04
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
        playerController.modalPresentationStyle = .overFullScreen
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

private struct YouTubePlayerView: UIViewRepresentable {
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
