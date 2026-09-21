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

    init(video: Video, transition: Namespace.ID, transitionID: String? = nil) {
        self.video = video
        self.transition = transition
        self.transitionID = transitionID ?? video.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VideoHeroArtwork(video: video)
                    .overlay {
                        Button {
                            library.markWatched(video)
                            showPlayer = true
                            feedback += 1
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.black)
                                .frame(width: 64, height: 64)
                                .background(.white, in: Circle())
                                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                        }
                        .accessibilityLabel("Play \(video.title)")
                    }

                VStack(alignment: .leading, spacing: 12) {
                    Text(video.title)
                        .font(.title2.bold())

                    Text(video.channelName)
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    if !video.metadataLine.isEmpty {
                        Text(video.metadataLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Button {
                            library.toggleSaved(video)
                            feedback += 1
                        } label: {
                            Label(library.isSaved(video) ? "Saved" : "Save", systemImage: library.isSaved(video) ? "bookmark.fill" : "bookmark")
                        }
                        .buttonStyle(.borderedProminent)

                        Menu {
                            ForEach(library.playlists) { playlist in
                                Button(playlist.name) {
                                    library.add(video, to: playlist.id)
                                    feedback += 1
                                }
                            }
                        } label: {
                            Label("Playlist", systemImage: "text.badge.plus")
                        }
                        .buttonStyle(.bordered)

                        if let url = video.youtubeURL {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Share")
                        }
                    }
                }
                .padding(.horizontal)

                Divider()
                    .padding(.horizontal)

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
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTransition(.zoom(sourceID: transitionID, in: transition))
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerScreen(video: video)
        }
        .sensoryFeedback(.selection, trigger: feedback)
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
