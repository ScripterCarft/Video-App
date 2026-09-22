import SwiftUI

struct VideoDetailView: View {
    let video: Video
    let transition: Namespace.ID
    let transitionID: String

    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackStore.self) private var playback
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var feedback = 0
    @State private var showDescription = false
    @State private var loadedDetails: YouTubeService.VideoDetails?

    init(video: Video, transition: Namespace.ID, transitionID: String? = nil) {
        self.video = video
        self.transition = transition
        self.transitionID = transitionID ?? video.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                detailStage

                if dynamicTypeSize >= .accessibility1 {
                    accessibilityDetails
                }

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
        .background(.black)
        .foregroundStyle(.white)
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
        .sheet(isPresented: $showDescription) {
            DescriptionSheet(video: video, description: fullDescription)
                .presentationDetents([.fraction(0.55), .fraction(0.8)])
                .presentationDragIndicator(.visible)
        }
        .task(id: video.id) {
            guard video.source == .youtube else { return }
            loadedDetails = try? await YouTubeService.shared.details(for: video.id)
        }
        .sensoryFeedback(.selection, trigger: feedback)
    }

    private var visibleDescription: String? {
        let candidate = video.descriptionText ?? loadedDetails?.description
        guard let candidate, !candidate.isEmpty else { return nil }
        let normalized = candidate
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }

    private var fullDescription: String? {
        video.descriptionText ?? loadedDetails?.description
    }

    private var visibleBadges: [String] {
        let loaded = loadedDetails?.badges ?? []
        return loaded.isEmpty ? (video.badges ?? []) : loaded
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
                        library.markWatched(video)
                        playback.play(video)
                        feedback += 1
                    } label: {
                        Label("Play", systemImage: "play.fill")
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

                if dynamicTypeSize < .accessibility1 {
                    descriptionPreview
                    metadataRow
                }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var descriptionPreview: some View {
        if let description = visibleDescription {
            ZStack(alignment: .bottomTrailing) {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .shadow(color: .black.opacity(0.58), radius: 8, y: 2)
                    .mask {
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
                    }

                Button("MORE") { showDescription = true }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(.ultraThinMaterial, in: Capsule())
                    .contentShape(Rectangle().inset(by: -11))
            }
        }
    }

    private var metadataRow: some View {
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

    private var accessibilityDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let description = visibleDescription {
                Text(description)
                    .lineLimit(4)
                Button("More") { showDescription = true }
            }
            ScrollView(.horizontal) {
                metadataRow
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 18)
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
