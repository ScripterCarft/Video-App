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
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerScreen(video: video, description: visibleDescription)
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
                        showPlayer = true
                        feedback += 1
                    } label: {
                        Label("Play", systemImage: "play.fill")
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
    @Environment(LibraryStore.self) private var library
    @State private var nativePlayer: AVPlayer?
    @State private var usesEmbeddedFallback = false
    @State private var isResolving = true
    @State private var playbackStarted = false
    @State private var diagnosticMessage: String?
    @State private var isPictureInPictureActive = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if let nativePlayer {
                    NativePlayerView(
                        player: nativePlayer,
                        isPictureInPictureActive: $isPictureInPictureActive
                    )
                } else if usesEmbeddedFallback, video.source == .youtube {
                    YouTubePlayerView(videoID: video.id)
                } else if isResolving {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                }
            }
            .ignoresSafeArea()
        }
        .statusBarHidden()
        .task(id: video.id) {
            await preparePlayback()
        }
        .task(id: playbackStarted) {
            guard playbackStarted else { return }
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            library.markWatched(video)
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
        .onDisappear {
            guard !isPictureInPictureActive else { return }
            nativePlayer?.pause()
        }
    }

    @MainActor
    private func preparePlayback() async {
        switch video.source {
        case .direct:
            guard let url = video.playbackURL else {
                isResolving = false
                return
            }
            let item = AVPlayerItem(url: url)
            let player = makePlayer(item: item)
            nativePlayer = player
            isResolving = false
            startPlayback(player)
            await installArtwork(on: item)

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
                startPlayback(player)
                await installArtwork(on: item)
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
        item.externalMetadata = playerMetadata
        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        return player
    }

    private var playerMetadata: [AVMetadataItem] {
        var metadata = [
            metadataItem(identifier: .commonIdentifierTitle, value: video.title)
        ]
        if let description, !description.isEmpty {
            metadata.append(
                metadataItem(identifier: .commonIdentifierDescription, value: description)
            )
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
    private func installArtwork(on playerItem: AVPlayerItem) async {
        for url in video.artworkURLs(for: .hero) {
            guard !Task.isCancelled else { return }

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

            var metadata = playerMetadata
            metadata.append(artworkMetadataItem(data: artworkData))
            playerItem.externalMetadata = metadata
            return
        }
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
    private func startPlayback(_ player: AVPlayer) {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .moviePlayback)
        try? audioSession.setActive(true)
        player.play()
        playbackStarted = true
    }

    @MainActor
    private func showEmbeddedFallback(_ diagnostic: String) {
        nativePlayer?.pause()
        nativePlayer = nil
        isResolving = false
        diagnosticMessage = diagnostic
        usesEmbeddedFallback = true
        playbackStarted = true
    }
}

private struct NativePlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    @Binding var isPictureInPictureActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isPictureInPictureActive: $isPictureInPictureActive)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.delegate = context.coordinator
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        private var isPictureInPictureActive: Binding<Bool>

        init(isPictureInPictureActive: Binding<Bool>) {
            self.isPictureInPictureActive = isPictureInPictureActive
        }

        func playerViewControllerWillStartPictureInPicture(
            _ playerViewController: AVPlayerViewController
        ) {
            isPictureInPictureActive.wrappedValue = true
        }

        func playerViewControllerDidStopPictureInPicture(
            _ playerViewController: AVPlayerViewController
        ) {
            isPictureInPictureActive.wrappedValue = false
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            failedToStartPictureInPictureWithError error: Error
        ) {
            isPictureInPictureActive.wrappedValue = false
            print("Picture in Picture failed: \(error.localizedDescription)")
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            completionHandler(true)
        }
    }
}

private struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

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

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedVideoID: String?
    }
}
