import SwiftUI

struct VideoArtwork: View {
    let video: Video
    var cornerRadius: CGFloat = 14
    var showsDuration = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            FallbackAsyncImage(urls: video.artworkURLs) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    ZStack {
                        placeholder
                        ProgressView()
                            .tint(.secondary)
                    }
                @unknown default:
                    placeholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if showsDuration, let duration = video.duration {
                Text(duration)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.76), in: Capsule())
                    .padding(8)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: "play.rectangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
    }
}

/// A taller presentation for editorial and detail screens. The complete 16:9
/// thumbnail stays visible while a blurred copy extends its own colors into
/// the additional vertical space.
struct VideoHeroArtwork: View {
    let video: Video
    var cornerRadius: CGFloat = 0
    var stageAspectRatio: CGFloat = 4.0 / 5.0

    var body: some View {
        FallbackAsyncImage(urls: video.artworkURLs) { phase in
            GeometryReader { proxy in
                let imageFraction = min(1, stageAspectRatio / (16.0 / 9.0))
                let imageEdge = (1 - imageFraction) / 2

                switch phase {
                case .success(let image):
                    ZStack {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .blur(radius: 28)
                            .scaleEffect(1.16)
                            .saturation(0.92)

                        Color.black.opacity(0.12)

                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .scaleEffect(1.08)
                            .blur(radius: 11)
                            .opacity(0.78)
                            .mask {
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: max(0, imageEdge - 0.12)),
                                        .init(color: .black, location: min(0.5, imageEdge + 0.07)),
                                        .init(color: .black, location: max(0.5, 1 - imageEdge - 0.07)),
                                        .init(color: .clear, location: min(1, 1 - imageEdge + 0.12))
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }

                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .mask {
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: max(0, imageEdge - 0.035)),
                                        .init(color: .black, location: min(0.5, imageEdge + 0.115)),
                                        .init(color: .black, location: max(0.5, 1 - imageEdge - 0.115)),
                                        .init(color: .clear, location: min(1, 1 - imageEdge + 0.035))
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                    }
                case .failure:
                    heroPlaceholder
                case .empty:
                    ZStack {
                        heroPlaceholder
                        ProgressView()
                            .tint(.secondary)
                    }
                @unknown default:
                    heroPlaceholder
                }
            }
        }
        .aspectRatio(stageAspectRatio, contentMode: .fit)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var heroPlaceholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: "play.rectangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
    }
}

private struct FallbackAsyncImage<Content: View>: View {
    let urls: [URL]
    let content: (AsyncImagePhase) -> Content

    @State private var index = 0

    init(urls: [URL], @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.urls = urls
        self.content = content
    }

    var body: some View {
        if urls.indices.contains(index) {
            AsyncImage(url: urls[index]) { phase in
                if case .failure = phase, index < urls.count - 1 {
                    Color.clear
                        .task { index += 1 }
                } else {
                    content(phase)
                }
            }
            .id(urls[index])
        } else {
            content(.empty)
        }
    }
}
