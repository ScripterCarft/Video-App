import SwiftUI

struct VideoCard: View {
    let video: Video
    var compact = false

    @Environment(LibraryStore.self) private var library
    @Environment(DownloadManager.self) private var downloads
    @State private var feedback = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VideoArtwork(
                video: video,
                cornerRadius: 14,
                quality: compact ? .compact : .search
            )
            .frame(height: compact ? Self.compactArtworkHeight : nil)

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(video.channelName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !video.metadataLine.isEmpty {
                    Text(video.metadataLine)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .clipped()
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .contextMenu {
            // A control group in a menu shows its buttons side by side.
            ControlGroup {
                DownloadMenuButton(video: video) {
                    feedback += 1
                }

                Button {
                    withAnimation {
                        library.toggleSaved(video)
                    }
                    feedback += 1
                } label: {
                    Label(
                        // Short titles fit the side-by-side buttons, like Podcasts' "Unsave".
                        library.isSaved(video) ? "Unsave" : "Save",
                        systemImage: library.isSaved(video) ? "bookmark.slash" : "bookmark"
                    )
                }

                if let url = video.youtubeURL {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section {
                VideoLibraryActions(video: video) {
                    feedback += 1
                }
            }

            if downloads.isDownloaded(video) {
                Section {
                    Button("Remove Download", systemImage: "trash", role: .destructive) {
                        withAnimation {
                            downloads.remove(video)
                        }
                        feedback += 1
                    }
                }
            }
        } preview: {
            VideoArtwork(video: video, cornerRadius: 18, quality: .search)
                .frame(width: 320)
                .padding()
        }
        .sensoryFeedback(.selection, trigger: feedback)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens video details")
    }
}

extension VideoCard {
    static let compactArtworkHeight: CGFloat = 153

    /// Takes the height of a compact card with a two-line title, a channel
    /// line and a metadata line at the current text size, and shows nothing.
    /// Mirrors the layout above; shelves use it as their height so a lazily
    /// loaded card with a long title is never squeezed.
    struct CompactHeightTemplate: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Color.clear
                    .frame(height: VideoCard.compactArtworkHeight)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "X\nX")
                        .font(.headline)
                        .lineLimit(2)
                    Text(verbatim: "X")
                        .font(.subheadline)
                    Text(verbatim: "X")
                        .font(.caption)
                }
            }
            .hidden()
            .accessibilityHidden(true)
        }
    }
}
