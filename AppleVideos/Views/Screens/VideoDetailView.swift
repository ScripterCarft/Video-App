import SwiftUI

/// A video's detail screen: a SwiftUI shell (toolbar, zoom transition,
/// player, description sheet) around `DetailCollection`, which shows the
/// hero and the Up Next shelf. `VideoDetailModel` holds the state and loads.
struct VideoDetailView: View {
    let video: Video
    let transition: Namespace.ID
    let transitionID: String

    @Environment(LibraryStore.self) private var library
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.openVideo) private var openVideo
    @State private var model: VideoDetailModel
    @State private var playback = PlaybackStarter()
    @State private var feedback = 0
    @State private var showDescription = false

    init(video: Video, transition: Namespace.ID, transitionID: String) {
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
            transition: transition,
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
        .navigationTransition(.zoom(sourceID: transitionID, in: transition))
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

