import SwiftUI

struct VideoDetailView: View {
    let video: Video
    let transition: Namespace.ID
    let transitionID: String

    @Environment(LibraryStore.self) private var library
    @State private var isPreparingPlayback = false
    @State private var playbackTask: Task<Void, Never>?
    @State private var fallbackDiagnostic: String?
    @State private var feedback = 0
    @State private var showDescription = false
    @State private var loadedDescription: String?
    @State private var loadedBadges: [String]?
    @State private var detailsLoadFinished = false
    @State private var detailsVideoID: String?

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

                // EXPERIMENT (temporary): play Apple's public HLS test stream through
                // the same native path, to rule the YouTube stream in or out.
                Button("Apple Test Stream", systemImage: "testtube.2") {
                    startPlayback(Self.appleTestStream)
                }
                .buttonStyle(.bordered)
                .disabled(isPreparingPlayback)
                .padding(.horizontal)
            }
            .padding(.bottom, 30)
        }
        .background(.black)
        .foregroundStyle(.white)
        .toolbar {
            if let url = video.youtubeURL {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Section("Add to Playlist") {
                            ForEach(library.playlists) { playlist in
                                Button(playlist.name) {
                                    library.add(video, to: playlist.id)
                                    feedback += 1
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More options")

                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                }
            }
        }
        .navigationTransition(.zoom(sourceID: transitionID, in: transition))
        .overlay {
            if let fallbackDiagnostic {
                EmbeddedPlayerScreen(video: video, diagnostic: fallbackDiagnostic) {
                    self.fallbackDiagnostic = nil
                }
                .ignoresSafeArea()
            }
        }
        .onDisappear {
            // Leaving the screen while the source resolves cancels playback.
            // (While AVKit is presented nothing is preparing, so this is a no-op.)
            if isPreparingPlayback {
                cancelPlayback()
            }
        }
        .sheet(isPresented: $showDescription) {
            DescriptionSheet(video: video, description: visibleDescription)
                .presentationDetents([.fraction(0.55), .fraction(0.8)])
                .presentationDragIndicator(.visible)
        }
        .task(id: video.id) {
            // The full-screen player removes this screen from the window, and an
            // interactive swipe-down re-adds it, which re-runs this task. Only reset
            // for a different video so state stays unchanged under AVKit's transition.
            if detailsVideoID != video.id {
                detailsVideoID = video.id
                loadedDescription = nil
                loadedBadges = nil
                detailsLoadFinished = false
            }
            guard !detailsLoadFinished else { return }

            guard video.source == .youtube else {
                detailsLoadFinished = true
                return
            }

            let details = try? await YouTubeService.shared.details(for: video.id)
            // A cancelled load is retried the next time the screen appears.
            guard !Task.isCancelled else { return }
            loadedDescription = details?.description
            loadedBadges = details.flatMap { $0.badges.isEmpty ? nil : $0.badges }
            detailsLoadFinished = true
        }
        .sensoryFeedback(.selection, trigger: feedback)
    }

    private var visibleDescription: String? {
        [video.descriptionText, loadedDescription]
            .lazy
            .compactMap { $0?.collapsedWhitespace }
            .first
    }

    /// Resolves the video and hands it to AVKit. From then on AVKit owns the
    /// player; this view only hears back once, after the player has closed.
    private func startPlayback(_ target: Video? = nil) {
        isPreparingPlayback = true
        let video = target ?? self.video
        let recordsHistory = target == nil
        let library = self.library
        let description = target == nil ? visibleDescription : nil
        playbackTask = Task {
            let result = await NativePlayback.play(video, description: description) { reachedWatchThreshold in
                if reachedWatchThreshold && recordsHistory {
                    library.markWatched(video)
                }
            }
            guard !Task.isCancelled else { return }
            isPreparingPlayback = false
            playbackTask = nil
            if case let .fallback(diagnostic) = result {
                fallbackDiagnostic = diagnostic
            }
        }
    }

    // EXPERIMENT (temporary): Apple's public HLS example stream.
    private static let appleTestStream = Video(
        id: "apple-bipbop-test",
        title: "Apple HLS Test Stream",
        channelName: "Apple",
        thumbnailURL: nil,
        duration: nil,
        publishedText: nil,
        viewCountText: nil,
        descriptionText: nil,
        badges: nil,
        source: .direct,
        playbackURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8")
    )

    private func cancelPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPreparingPlayback = false
    }

    private var visibleBadges: [String] {
        let original = video.badges ?? []
        let verified = loadedBadges ?? []
        let resolutions = Set(["8K", "4K", "HD", "SD"])
        let resolution = verified.first(where: resolutions.contains)
            ?? original.first(where: resolutions.contains)
        let supported = ["HDR", "CC", "SDH", "360°", "LIVE", "PREMIERE", "UPCOMING"]
        let combined = Set(original + verified)
        return [resolution].compactMap { $0 } + supported.filter(combined.contains)
    }

    private var textMetadata: [String] {
        [video.formattedDuration, video.viewCountText, video.publishedText]
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
                    Text(video.title)
                        .font(.title.bold())
                        .lineLimit(3)
                    Text(video.channelName)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.62), radius: 9, y: 2)

                HStack(spacing: 10) {
                    Spacer(minLength: 0)

                    Button {
                        if isPreparingPlayback {
                            cancelPlayback()
                        } else {
                            startPlayback()
                            feedback += 1
                        }
                    } label: {
                        Group {
                            if isPreparingPlayback {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(.black)
                                    Text("Cancel")
                                }
                            } else {
                                Label("Play", systemImage: "play.fill")
                            }
                        }
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
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay {
                                Circle()
                                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(library.isSaved(video) ? "Remove from Saved" : "Add to Saved")

                    Spacer(minLength: 0)
                }

                if let description = visibleDescription {
                    DescriptionPreview(text: description) {
                        showDescription = true
                    }
                } else if video.source == .youtube && !detailsLoadFinished {
                    DescriptionPlaceholder()
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
                .shadow(color: .black.opacity(0.56), radius: 7, y: 2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }
}

private struct DescriptionPlaceholder: View {
    var body: some View {
        Text("Loading video description\nLoading video description")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.72))
            .lineLimit(2)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
    }
}

private struct DescriptionPreview: View {
    let text: String
    let onMore: () -> Void

    @State private var limitedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var isTruncated: Bool {
        limitedHeight > 0 && fullHeight > limitedHeight + 0.5
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .shadow(color: .black.opacity(0.58), radius: 8, y: 2)
                .background(alignment: .topLeading) {
                    Text(text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            fullHeight = height
                        }
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    limitedHeight = height
                }
                .mask {
                    if isTruncated {
                        VStack(spacing: 0) {
                            Color.white
                            HStack(spacing: 0) {
                                Color.white
                                LinearGradient(
                                    colors: [.white, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 84)
                            }
                        }
                    } else {
                        Color.white
                    }
                }

            if isTruncated {
                Button("MORE", action: onMore)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
            }
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
