import SwiftUI

/// The SwiftUI video card of the screens that are still SwiftUI (Search,
/// Library, Explore), with its own context menu. Collection views show the
/// UIKit card, `VideoCardConfiguration`.
struct VideoCard: View {
    let video: Video

    @Environment(LibraryStore.self) private var library
    @Environment(DownloadManager.self) private var downloads
    @State private var feedback = 0

    var body: some View {
        card
            .contextMenu {
                menu
            } preview: {
                VideoArtwork(video: video, cornerRadius: 18, quality: .search)
                    .frame(width: 320)
                    .padding()
            }
            .sensoryFeedback(.selection, trigger: feedback)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens video details")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            VideoArtwork(video: video, cornerRadius: 14, quality: .search)

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
    }

    @ViewBuilder
    private var menu: some View {
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
    }
}
