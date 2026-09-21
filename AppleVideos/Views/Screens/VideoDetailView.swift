import AVKit
import SwiftUI
import WebKit

struct VideoDetailView: View {
    let video: Video
    let transition: Namespace.ID
    let transitionID: String

    @Environment(LibraryStore.self) private var library
    @State private var showPlayer = false
    @State private var feedback = 0
    @State private var descriptionExpanded = false
    @State private var showDownloadNotice = false

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
        .coordinateSpace(name: "videoDetailScroll")
        .background(.black)
        .foregroundStyle(.white)
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if let url = video.youtubeURL {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showDownloadNotice = true
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .accessibilityLabel("Download")

                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                }
            }
        }
        .navigationTransition(.zoom(sourceID: transitionID, in: transition))
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerScreen(video: video)
        }
        .alert("Download Unavailable", isPresented: $showDownloadNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("YouTube does not provide an offline download to Apple Videos. Direct video sources can support downloads later.")
        }
        .sensoryFeedback(.selection, trigger: feedback)
    }

    private var detailStage: some View {
        GeometryReader { geometry in
            let minY = geometry.frame(in: .named("videoDetailScroll")).minY
            let scrollUp = max(0, -minY)
            let pullDown = max(0, minY)
            let stageHeight = geometry.size.height

            ZStack(alignment: .bottomLeading) {
                VideoHeroArtwork(video: video, stageAspectRatio: 2.0 / 3.0)
                    .frame(width: geometry.size.width, height: stageHeight)
                    .scaleEffect(1 + (pullDown / max(stageHeight, 1)) * 0.55, anchor: .bottom)
                    .offset(y: scrollUp * 0.76 - pullDown * 0.36)

                Color.black
                    .opacity(min(0.26, scrollUp / max(stageHeight, 1)))

                Rectangle()
                    .fill(.black.opacity(0.72))
                    .frame(height: stageHeight * 0.48)
                    .blur(radius: 44)
                    .offset(y: stageHeight * 0.2)

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.2),
                        .init(color: .black.opacity(0.12), location: 0.4),
                        .init(color: .black.opacity(0.58), location: 0.66),
                        .init(color: .black.opacity(0.94), location: 0.88),
                        .init(color: .black, location: 1)
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
                VStack(alignment: .leading, spacing: 5) {
                    Text(video.title)
                        .font(.title.bold())
                        .lineLimit(3)
                    Text(video.channelName)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.72))
                }

                HStack(spacing: 10) {
                    Button {
                        library.markWatched(video)
                        showPlayer = true
                        feedback += 1
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.glassProminent)

                    Button {
                        library.toggleSaved(video)
                        feedback += 1
                    } label: {
                        Image(systemName: library.isSaved(video) ? "checkmark" : "plus")
                            .font(.headline)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(library.isSaved(video) ? "Remove from Saved" : "Add to Saved")

                    Menu {
                        ForEach(library.playlists) { playlist in
                            Button(playlist.name) {
                                library.add(video, to: playlist.id)
                                feedback += 1
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("More options")
                }

                if let description = video.descriptionText, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(descriptionExpanded ? nil : 3)

                        Button(descriptionExpanded ? "LESS" : "MORE") {
                            withAnimation(.snappy) {
                                descriptionExpanded.toggle()
                            }
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 7) {
                    ForEach(video.badges ?? [], id: \.self) { badge in
                        MetadataBadge(text: badge)
                    }

                    if let duration = video.formattedDuration {
                        Text(duration)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    if let published = video.publishedText {
                        Text(published)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Group {
                switch video.source {
                case .youtube:
                    YouTubePlayerView(videoID: video.id)
                case .direct:
                    if let url = video.playbackURL {
                        VideoPlayer(player: AVPlayer(url: url))
                    }
                }
            }
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
            .accessibilityLabel("Close player")
        }
        .statusBarHidden()
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
