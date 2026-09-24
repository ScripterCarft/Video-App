import SwiftUI

struct VideoCard: View {
    let video: Video
    var compact = false

    @Environment(LibraryStore.self) private var library
    @State private var feedback = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VideoArtwork(
                video: video,
                cornerRadius: 14,
                quality: compact ? .compact : .search
            )
            .frame(height: compact ? 153 : nil)

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 22, alignment: .topLeading)

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
        // Rounded highlight when the card lifts for its context menu.
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            Button {
                library.toggleSaved(video)
                feedback += 1
            } label: {
                Label(
                    library.isSaved(video) ? "Remove from Saved" : "Save Video",
                    systemImage: library.isSaved(video) ? "bookmark.slash" : "bookmark"
                )
            }

            if !library.playlists.isEmpty {
                Menu("Add to Playlist", systemImage: "text.badge.plus") {
                    ForEach(library.playlists) { playlist in
                        Button(playlist.name) {
                            library.add(video, to: playlist.id)
                            feedback += 1
                        }
                    }
                }
            }

            if let url = video.youtubeURL {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
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
