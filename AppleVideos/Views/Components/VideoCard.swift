import SwiftUI

struct VideoCard: View {
    let video: Video
    var compact = false

    @Environment(LibraryStore.self) private var library
    @State private var feedback = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VideoArtwork(video: video, cornerRadius: compact ? 12 : 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

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
        .contentShape(Rectangle())
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

            Menu("Add to Playlist", systemImage: "text.badge.plus") {
                ForEach(library.playlists) { playlist in
                    Button(playlist.name) {
                        library.add(video, to: playlist.id)
                        feedback += 1
                    }
                }
            }

            if let url = video.youtubeURL {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        } preview: {
            VideoArtwork(video: video, cornerRadius: 18)
                .frame(width: 320)
                .padding()
        }
        .sensoryFeedback(.selection, trigger: feedback)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens video details")
    }
}

