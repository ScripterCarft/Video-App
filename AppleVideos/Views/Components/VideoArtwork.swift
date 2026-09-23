import SwiftUI
import UIKit

struct VideoArtwork: View {
    let video: Video
    var cornerRadius: CGFloat = 14
    var showsDuration = true
    var quality: ArtworkQuality = .search

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            FallbackThumbnailImage(
                urls: video.artworkURLs(for: quality),
                requiresSixteenByNine: video.source == .youtube
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: { isLoading in
                ZStack {
                    placeholder
                    if isLoading {
                        ProgressView()
                            .tint(.secondary)
                    }
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
        FallbackThumbnailImage(
            urls: video.artworkURLs(for: .hero),
            requiresSixteenByNine: video.source == .youtube
        ) { image in
            GeometryReader { proxy in
                let imageFraction = min(1, stageAspectRatio / (16.0 / 9.0))
                let imageEdge = (1 - imageFraction) / 2

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
            }
        } placeholder: { isLoading in
            ZStack {
                heroPlaceholder
                if isLoading {
                    ProgressView()
                        .tint(.secondary)
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

private struct FallbackThumbnailImage<Content: View, Placeholder: View>: View {
    let urls: [URL]
    let requiresSixteenByNine: Bool
    let content: (Image) -> Content
    let placeholder: (Bool) -> Placeholder

    @State private var loadedImage: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let loadedImage {
                content(Image(uiImage: loadedImage))
            } else {
                placeholder(isLoading)
            }
        }
        .task(id: urls) {
            loadedImage = nil
            isLoading = true
            let image = await ArtworkLoader.firstImage(from: urls, requiresSixteenByNine: requiresSixteenByNine)
            guard !Task.isCancelled else { return }
            loadedImage = image
            isLoading = false
        }
    }
}
