import SwiftUI
import UIKit

struct VideoArtwork: View {
    let video: Video
    var cornerRadius: CGFloat = 14
    var showsDuration = true
    var quality: ArtworkQuality = .search

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            FallbackThumbnailImage(
                candidates: video.artworkCandidates(lowData: NetworkConditions.shared.isConstrained),
                maxPixelWidth: quality.displayWidth * displayScale,
                requiresSixteenByNine: video.source == .youtube
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ArtworkPlaceholder()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // Read from the shared manager: context menu previews may not
            // carry the environment.
            let isDownloaded = DownloadManager.shared.isDownloaded(video)
            if showsDuration, video.duration != nil || isDownloaded {
                HStack(spacing: 4) {
                    if isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .accessibilityLabel("Downloaded")
                    }
                    if let duration = video.duration {
                        Text(duration)
                    }
                }
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
}

private struct ArtworkPlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: "play.rectangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
    }
}

/// Shows a static placeholder until the first usable candidate image loads.
private struct FallbackThumbnailImage<Content: View, Placeholder: View>: View {
    /// What to load: the candidates and the width to downsample to.
    private struct Request: Hashable {
        let candidates: [ArtworkCandidate]
        let maxPixelWidth: CGFloat
    }

    private let request: Request
    let requiresSixteenByNine: Bool
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var loadedImage: UIImage?
    @State private var loadedRequest: Request?

    init(
        candidates: [ArtworkCandidate],
        maxPixelWidth: CGFloat,
        requiresSixteenByNine: Bool,
        content: @escaping (Image) -> Content,
        placeholder: @escaping () -> Placeholder
    ) {
        let request = Request(candidates: candidates, maxPixelWidth: maxPixelWidth)
        self.request = request
        self.requiresSixteenByNine = requiresSixteenByNine
        self.content = content
        self.placeholder = placeholder
        // Start with an already prepared image so cached artwork appears in the
        // first frame instead of after a placeholder.
        let cached = ArtworkLoader.cachedImage(for: candidates, maxPixelWidth: maxPixelWidth)
        _loadedImage = State(initialValue: cached)
        _loadedRequest = State(initialValue: cached == nil ? nil : request)
    }

    var body: some View {
        Group {
            if let loadedImage {
                content(Image(uiImage: loadedImage))
            } else {
                placeholder()
            }
        }
        .task(id: request) {
            // The task re-runs whenever the view re-enters the window (for example
            // under a full-screen player's interactive dismissal). Keep a finished
            // load for the same request instead of loading again.
            guard loadedRequest != request else { return }
            // When the artwork URL changes (for example after a metadata
            // refresh), keep showing the current image until the new one is ready.
            let image = await ArtworkLoader.firstImage(
                from: request.candidates,
                requiresSixteenByNine: requiresSixteenByNine,
                maxPixelWidth: request.maxPixelWidth
            )
            guard !Task.isCancelled else { return }
            if let image {
                loadedImage = image
            }
            loadedRequest = request
        }
    }
}
