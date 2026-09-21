import SwiftUI

struct VideoArtwork: View {
    let video: Video
    var cornerRadius: CGFloat = 14
    var showsDuration = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: video.artworkURL) { phase in
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
        AsyncImage(url: video.artworkURL) { phase in
            GeometryReader { proxy in
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
                            .mask {
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.06),
                                        .init(color: .black, location: 0.22),
                                        .init(color: .black, location: 0.78),
                                        .init(color: .clear, location: 0.94)
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
