import AVKit
import SwiftUI
import UIKit
@preconcurrency import WebKit

struct PlayerScreen: View {
    @Environment(PlaybackStore.self) private var playback

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let video = playback.currentVideo {
                Group {
                    switch video.source {
                    case .youtube:
                        YouTubePlayerSurface(session: playback.youtubeSession)
                    case .direct:
                        if let player = playback.directPlayer {
                            VideoPlayer(player: player)
                        }
                    }
                }
                .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Button {
                        playback.minimize()
                    } label: {
                        Image(systemName: "chevron.down")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Minimize player")

                    Spacer()

                    Button {
                        playback.stop()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close player")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .padding()

                Spacer()
            }
        }
        .statusBarHidden()
    }
}

struct MiniPlayerAccessory: View {
    @Environment(PlaybackStore.self) private var playback
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    @ViewBuilder
    var body: some View {
        if let video = playback.currentVideo {
            switch placement {
            case .inline:
                inlineAccessory(video)
            case .expanded:
                expandedAccessory(video)
            @unknown default:
                expandedAccessory(video)
            }
        }
    }

    private func inlineAccessory(_ video: Video) -> some View {
        HStack(spacing: 6) {
            Button {
                playback.expand()
            } label: {
                Text(video.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            playbackButton
        }
        .padding(.leading, 8)
    }

    private func expandedAccessory(_ video: Video) -> some View {
        HStack(spacing: 12) {
            Button {
                playback.expand()
            } label: {
                HStack(spacing: 10) {
                    VideoArtwork(video: video)
                        .frame(width: 58, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(video.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let remaining = playback.remainingText {
                            Text(remaining)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        } else {
                            Text(video.channelName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(video.title)")

            playbackButton

            Button {
                playback.stop()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close player")
        }
        .overlay(alignment: .bottom) {
            ProgressView(value: playback.progress)
                .progressViewStyle(.linear)
                .tint(.primary)
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
    }

    private var playbackButton: some View {
        Button {
            playback.togglePlayback()
        } label: {
            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
    }
}

private struct YouTubePlayerSurface: UIViewRepresentable {
    let session: YouTubePlaybackSession

    func makeUIView(context: Context) -> WebPlayerHostView {
        let host = WebPlayerHostView()
        host.attach(session.webView)
        return host
    }

    func updateUIView(_ host: WebPlayerHostView, context: Context) {
        host.attach(session.webView)
    }

    static func dismantleUIView(_ host: WebPlayerHostView, coordinator: Void) {
        host.detach()
    }
}

private final class WebPlayerHostView: UIView {
    private weak var playerView: WKWebView?

    func attach(_ view: WKWebView) {
        guard view.superview !== self else { return }
        view.removeFromSuperview()
        addSubview(view)
        playerView = view
        setNeedsLayout()
    }

    func detach() {
        guard playerView?.superview === self else { return }
        playerView?.removeFromSuperview()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard playerView?.superview === self else { return }
        playerView?.frame = bounds
    }
}
