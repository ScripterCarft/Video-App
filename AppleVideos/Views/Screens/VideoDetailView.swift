import SwiftUI

/// A video's detail screen: a SwiftUI shell (toolbar, zoom transition,
/// player, description sheet) around `DetailCollection`, which shows the
/// hero and the Up Next shelf. `VideoDetailModel` holds the state and loads.
struct VideoDetailView: View {
    let video: Video
    /// The SwiftUI zoom source, when a SwiftUI navigation stack opened the
    /// screen; a UIKit navigation controller sets its own zoom transition.
    let transition: Namespace.ID?
    let transitionID: String

    @Environment(LibraryStore.self) private var library
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.openVideo) private var openVideo
    @State private var model: VideoDetailModel
    @State private var playback = PlaybackStarter()
    @State private var feedback = 0
    @State private var showDescription = false

    init(video: Video, transition: Namespace.ID?, transitionID: String) {
        self.video = video
        self.transition = transition
        self.transitionID = transitionID
        _model = State(initialValue: VideoDetailModel(video: video))
    }

    var body: some View {
        DetailCollection(
            model: model,
            related: model.related,
            playback: playback,
            library: library,
            downloads: downloads,
            onShowDescription: { showDescription = true },
            onFeedback: { feedback += 1 },
            onOpen: { route in openVideo(route) }
        )
        .ignoresSafeArea()
        .background(.black)
        // The detail screen is always dark; its toolbar buttons use white instead
        // of the app's red accent, like the TV app.
        .tint(.white)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if let url = video.youtubeURL {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    DownloadToolbarButton(video: video)

                    // The standard share sheet from the bottom. A ShareLink in
                    // the toolbar grows out of the button, which glitched here.
                    Button {
                        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                        NativePlayback.topViewController()?.present(controller, animated: true)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                }
            }
        }
        .modifier(SwiftUIZoomTransition(namespace: transition, sourceID: transitionID))
        .playbackPresentation(playback)
        .sheet(isPresented: $showDescription) {
            DescriptionSheet(video: model.shown, description: model.visibleDescription)
                .tint(.primary)
                .presentationDetents([.fraction(0.55), .fraction(0.8)])
                .presentationDragIndicator(.visible)
        }
        // SwiftUI cancels the loading when the screen goes away. The player
        // removes and re-adds this screen; the model keeps what has loaded.
        .task(id: video.id) {
            await model.load(library: library)
        }
        .onDisappear {
            // Store the refreshed metadata once the screen has left, so nothing
            // on the screen behind changes during the zoom back. The player
            // covering this screen is not leaving it.
            guard !NativePlayback.isShowingPlayer, let refreshed = model.refreshedVideo else { return }
            library.updateMetadata(of: refreshed)
        }
        .sensoryFeedback(.selection, trigger: feedback)
    }
}

/// The detail screen's hero: title, channel, Play and Save, the description
/// and the info line. Reads `VideoDetailModel`, so it updates by itself.
struct DetailHero: View {
    let model: VideoDetailModel
    let playback: PlaybackStarter
    let onShowDescription: () -> Void
    let onFeedback: () -> Void

    @Environment(LibraryStore.self) private var library

    private var video: Video {
        model.video
    }

    /// Lies over the artwork stage (see `DetailCollection`), as tall as it:
    /// clear at the top, the information at the bottom. Behind it, a plain
    /// gradient starts below the thumbnail, leaving the image itself
    /// untouched, and ends in the black the shelf starts with.
    var body: some View {
        information
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .background {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0), location: DetailStage.thumbnailBottom),
                        .init(color: .black.opacity(0.6), location: DetailStage.thumbnailBottom + 0.12),
                        .init(color: .black.opacity(0.9), location: 0.92),
                        .init(color: .black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
    }

    private var information: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .center, spacing: 5) {
                Text(model.shown.title)
                    .font(.title.bold())
                    .lineLimit(3)
                Text(model.shown.channelName)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Spacer(minLength: 0)

                Button {
                    if playback.isPreparing {
                        playback.cancel()
                    } else {
                        playback.start(video, description: model.visibleDescription, library: library)
                        onFeedback()
                    }
                } label: {
                    PlayButtonContent(
                        progress: library.progress(for: video),
                        isPreparing: playback.isPreparing
                    )
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 26)
                    .frame(minWidth: 190, minHeight: 50)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    library.toggleSaved(video)
                    onFeedback()
                } label: {
                    Image(systemName: library.isSaved(video) ? "checkmark" : "plus")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Color(white: 0.24), in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(library.isSaved(video) ? "Remove from Saved" : "Add to Saved")

                Spacer(minLength: 0)
            }

            // Until the details are loaded, the description and the line
            // below are placeholders; then both appear in one step.
            if !model.detailsLoadFinished {
                DescriptionPlaceholder()
            } else if let description = model.visibleDescription {
                DescriptionPreview(text: description, onMore: onShowDescription)
            }

            HStack(spacing: 7) {
                ForEach(Array(model.textMetadata.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Text("·")
                            .foregroundStyle(.white.opacity(0.42))
                    }
                    Text(item)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }

                ForEach(model.visibleBadges, id: \.self) { badge in
                    MetadataBadge(text: badge)
                }
            }
            .font(.footnote)
            .minimumScaleFactor(0.86)
            .redacted(reason: model.detailsLoadFinished ? [] : .placeholder)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }
}

private struct DescriptionPlaceholder: View {
    var body: some View {
        // Full-width text that wraps, so the redacted skeleton always shows two
        // lines like the real description.
        Text(String(repeating: "Loading video description ", count: 8))
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.72))
            .lineLimit(2, reservesSpace: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
    }
}

/// Two lines of description with MORE below them, which opens the full text.
/// Plain text layout: measuring the text to place MORE on the second line
/// ran TextKit on every width change, work the zoom transition does not need.
private struct DescriptionPreview: View {
    let text: String
    let onMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("MORE", action: onMore)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .buttonStyle(.plain)
        }
    }
}

/// The zoom from a SwiftUI source, only where a SwiftUI stack opened the screen.
private struct SwiftUIZoomTransition: ViewModifier {
    let namespace: Namespace.ID?
    let sourceID: String

    func body(content: Content) -> some View {
        if let namespace {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}

private struct DescriptionSheet: View {
    let video: Video
    let description: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(video.title)
                        .font(.title2.bold())
                    Text(video.channelName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(description ?? "No description is available for this video.")
                        .font(.body)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct MetadataBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(0.2)
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
            }
    }
}
