import SwiftUI

struct VideoDetailView: View {
    let video: Video
    let transition: Namespace.ID
    let transitionID: String

    @Environment(LibraryStore.self) private var library
    @State private var playback = PlaybackStarter()
    @State private var feedback = 0
    // TEST (do not merge)
    @AppStorage("test.detailEdgeEffect") private var testEdgeValue = "automatic"
    private var testEdgeStyle: ScrollEdgeEffectStyle {
        switch testEdgeValue {
        case "soft": .soft
        case "hard": .hard
        default: .automatic
        }
    }
    @State private var showDescription = false
    @State private var loadedDescription: String?
    @State private var loadedBadges: [String]?
    @State private var detailsLoadFinished = false
    @State private var detailsVideoID: String?
    @State private var refreshedVideo: Video?
    @State private var streamBadges: [String] = []

    init(video: Video, transition: Namespace.ID, transitionID: String) {
        self.video = video
        self.transition = transition
        self.transitionID = transitionID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                detailStage

                VStack(alignment: .leading, spacing: 8) {
                    Text("Up Next")
                        .font(.title2.bold())
                    Text("More recommendations will become personal as the Apple Videos algorithm evolves.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 30)
        }
        // TEST (do not merge): always scrollable, to look at the scroll edge
        // effect; normally .scrollBounceBehavior(.basedOnSize) goes here.
        // TEST (do not merge): edge effect style chosen in the Settings app.
        .scrollEdgeEffectStyle(testEdgeStyle, for: .top)
        .background(.black)
        .foregroundStyle(.white)
        // The detail screen is always dark; its toolbar buttons use white instead
        // of the app's red accent, like the TV app.
        .tint(.white)
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if let url = video.youtubeURL {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    DownloadToolbarButton(video: video)

                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                }
            }
        }
        .navigationTransition(.zoom(sourceID: transitionID, in: transition))
        .playbackPresentation(playback)
        .sheet(isPresented: $showDescription) {
            DescriptionSheet(video: shown, description: visibleDescription)
                .tint(.primary)
                .presentationDetents([.fraction(0.55), .fraction(0.8)])
                .presentationDragIndicator(.visible)
        }
        // One task, in order: the details, shown in one step, then the stream.
        // SwiftUI cancels it when the screen goes away.
        .task(id: video.id) {
            // The full-screen player removes this screen from the window, and an
            // interactive swipe-down re-adds it, which re-runs this task. Only reset
            // for a different video so state stays unchanged under AVKit's transition.
            if detailsVideoID != video.id {
                detailsVideoID = video.id
                loadedDescription = nil
                loadedBadges = nil
                refreshedVideo = nil
                streamBadges = []
                detailsLoadFinished = false
            }

            if !detailsLoadFinished {
                if video.source == .youtube {
                    let details = try? await YouTubeService.shared.details(for: video.id)
                    // A cancelled load is retried the next time the screen appears.
                    guard !Task.isCancelled else { return }
                    // Current title, views and publish date, from the details above.
                    let refreshed = details == nil ? nil : try? await YouTubeService.shared.refreshedVideo(video)
                    guard !Task.isCancelled else { return }

                    // Everything that loaded appears at once, not piece by piece.
                    withAnimation(.easeOut(duration: 0.25)) {
                        loadedDescription = details?.description
                        loadedBadges = details.flatMap { $0.badges.isEmpty ? nil : $0.badges }
                        refreshedVideo = refreshed
                        detailsLoadFinished = true
                    }
                    if let refreshed {
                        // Stored when the screen leaves; see onDisappear.
                        library.rememberFresh(refreshed)
                    }
                } else {
                    detailsLoadFinished = true
                }
            }

            // Then, while the screen stays, resolve the stream so Play starts
            // without waiting; its formats and captions also give the badges.
            let badges = await NativePlayback.prefetch(video)?.technicalBadges ?? []
            guard !Task.isCancelled, badges != streamBadges else { return }
            streamBadges = badges
        }
        .onDisappear {
            // Store the refreshed metadata once the screen has left, so nothing
            // on the screen behind changes during the zoom back. The player
            // covering this screen is not leaving it.
            guard !NativePlayback.isShowingPlayer, let refreshedVideo else { return }
            library.updateMetadata(of: refreshedVideo)
        }
        .sensoryFeedback(.selection, trigger: feedback)
    }

    /// The video with the freshest metadata available.
    private var shown: Video {
        refreshedVideo ?? video
    }

    /// Prefers the full description from the details request over the short
    /// snippet that search results carry.
    private var visibleDescription: String? {
        [loadedDescription, video.descriptionText]
            .lazy
            .compactMap { $0?.collapsedWhitespace }
            .first
    }

    private var visibleBadges: [String] {
        let original = video.badges ?? []
        // Technical badges come from the resolved stream; the details request
        // (WEB client) is refused playback data and only supplies live status.
        let verified = streamBadges + (loadedBadges ?? [])
        let resolutions = Set(["8K", "4K", "HD", "SD"])
        let resolution = verified.first(where: resolutions.contains)
            ?? original.first(where: resolutions.contains)
        let supported = ["HDR", "CC", "SDH", "360°", "LIVE", "PREMIERE", "UPCOMING"]
        let combined = Set(original + verified)
        return [resolution].compactMap { $0 } + supported.filter(combined.contains)
    }

    private var textMetadata: [String] {
        [shown.formattedDuration, shown.viewCountText, shown.publishedLabel]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
    }

    private var detailStage: some View {
        GeometryReader { geometry in
            let stageHeight = geometry.size.height

            ZStack(alignment: .bottomLeading) {
                VideoHeroArtwork(video: video, stageAspectRatio: 2.0 / 3.0)
                    .frame(width: geometry.size.width, height: stageHeight)
                    // The detail screen is always dark, so its stage gray is too.
                    .environment(\.colorScheme, .dark)

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.38),
                        .init(color: .black.opacity(0.08), location: 0.55),
                        .init(color: .black.opacity(0.3), location: 0.72),
                        .init(color: .black.opacity(0.62), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                detailInformation
            }
            .clipped()
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
    }

    private var detailInformation: some View {
        VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .center, spacing: 5) {
                    Text(shown.title)
                        .font(.title.bold())
                        .lineLimit(3)
                    Text(shown.channelName)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Spacer(minLength: 0)

                    Button {
                        if playback.isPreparing {
                            playback.cancel()
                        } else {
                            playback.start(video, description: visibleDescription, library: library)
                            feedback += 1
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
                        feedback += 1
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
                if !detailsLoadFinished {
                    DescriptionPlaceholder()
                } else if let description = visibleDescription {
                    DescriptionPreview(text: description) {
                        showDescription = true
                    }
                }

                HStack(spacing: 7) {
                    ForEach(Array(textMetadata.enumerated()), id: \.offset) { index, item in
                        if index > 0 {
                            Text("·")
                                .foregroundStyle(.white.opacity(0.42))
                        }
                        Text(item)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }

                    ForEach(visibleBadges, id: \.self) { badge in
                        MetadataBadge(text: badge)
                    }
                }
                .font(.footnote)
                .minimumScaleFactor(0.86)
                .redacted(reason: detailsLoadFinished ? [] : .placeholder)
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
