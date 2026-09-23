import SwiftUI
import UIKit

struct VideoDetailView: View {
    let video: Video
    let transition: Namespace.ID
    let transitionID: String

    @Environment(LibraryStore.self) private var library
    @State private var playback = PlaybackStarter()
    @State private var feedback = 0
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
        // Only scroll when the content is taller than the screen, so a downward
        // swipe closes the screen instead of pulling the content.
        .scrollBounceBehavior(.basedOnSize)
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
                    // The menu only offers playlists; hide it when there are none.
                    if !library.playlists.isEmpty {
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
                    }

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
        .task(id: video.id) {
            // Resolve the stream while the user reads, so Play starts without
            // waiting. The resolved formats and captions also give the badges.
            let badges = await NativePlayback.prefetch(video)?.technicalBadges ?? []
            guard !Task.isCancelled, badges != streamBadges else { return }
            streamBadges = badges
        }
        .task(id: video.id) {
            // The full-screen player removes this screen from the window, and an
            // interactive swipe-down re-adds it, which re-runs this task. Only reset
            // for a different video so state stays unchanged under AVKit's transition.
            if detailsVideoID != video.id {
                detailsVideoID = video.id
                loadedDescription = nil
                loadedBadges = nil
                refreshedVideo = nil
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

            // Show current title, views and publish date, and keep the library's
            // copies of this video up to date. Uses the details loaded above.
            if details != nil,
               let refreshed = try? await YouTubeService.shared.refreshedVideo(video),
               !Task.isCancelled {
                refreshedVideo = refreshed
                library.updateMetadata(of: refreshed)
            }
            detailsLoadFinished = true
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
                .shadow(color: .black.opacity(0.62), radius: 9, y: 2)

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
                        Group {
                            if playback.isPreparing {
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

/// Two lines of description with MORE at the end of the second line. The
/// shown text is cut at a word so that it ends before MORE; nothing overlaps.
private struct DescriptionPreview: View {
    let text: String
    let onMore: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var width: CGFloat = 0

    var body: some View {
        let preview = Self.preview(of: text, width: width, dynamicTypeSize: dynamicTypeSize)

        Text(preview ?? text)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.88))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: Alignment(horizontal: .trailing, vertical: .lastTextBaseline)) {
                if preview != nil {
                    Button("MORE", action: onMore)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .buttonStyle(.plain)
                }
            }
            .shadow(color: .black.opacity(0.58), radius: 8, y: 2)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                width = newWidth
            }
    }

    /// Returns nil when the whole text fits in two lines. Otherwise returns the
    /// longest word prefix plus an ellipsis that still leaves room for MORE at
    /// the end of the second line.
    private static func preview(
        of text: String,
        width: CGFloat,
        dynamicTypeSize: DynamicTypeSize
    ) -> String? {
        guard width > 0 else { return nil }

        // Measure with the same Dynamic Type size SwiftUI renders with.
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let bodyFont = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits)
        let moreFont = UIFont.systemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traits).pointSize,
            weight: .semibold
        )
        // A small margin keeps TextKit's wrapping on the safe side of SwiftUI's.
        let measuringWidth = max(0, width - 4)

        func fits(_ candidate: String, reservingMore: Bool) -> Bool {
            let string = NSMutableAttributedString(string: candidate, attributes: [.font: bodyFont])
            if reservingMore {
                string.append(NSAttributedString(string: "   MORE", attributes: [.font: moreFont]))
            }
            return lineCount(of: string, width: measuringWidth) <= 2
        }

        guard !fits(text, reservingMore: false) else { return nil }

        let words = text.split(separator: " ")
        var low = 0
        var high = words.count
        while low < high {
            let middle = (low + high + 1) / 2
            if fits(words.prefix(middle).joined(separator: " ") + "…", reservingMore: true) {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return words.prefix(low).joined(separator: " ") + "…"
    }

    /// Counts the lines TextKit produces for `string` at `width`. Counting lines
    /// avoids comparing floating-point heights, which misjudged two lines as three.
    private static func lineCount(of string: NSAttributedString, width: CGFloat) -> Int {
        let storage = NSTextStorage(attributedString: string)
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)

        var lines = 0
        var glyphIndex = 0
        while glyphIndex < layoutManager.numberOfGlyphs {
            var lineRange = NSRange()
            layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
            glyphIndex = NSMaxRange(lineRange)
            lines += 1
        }
        return lines
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
