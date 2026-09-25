import SwiftUI

/// Navigation value for a video's detail screen: only the video's ID and the
/// section it was tapped in, so paths stay small and can be restored after a
/// relaunch. The destination reads the video from `VideoCatalog`.
///
/// The transition ID names the tapped thumbnail, so the zoom transition starts
/// from the right place even when a video appears in several sections.
struct VideoRoute: Hashable, Codable {
    let videoID: String
    let section: String

    var transitionID: String {
        "\(section)-\(videoID)"
    }

    /// A route to `video`; the catalog remembers the video for the destination.
    @MainActor
    init(video: Video, section: String) {
        VideoCatalog.shared.remember(video)
        videoID = video.id
        self.section = section
    }
}

/// A plain navigation link to a video that also acts as its zoom source.
struct VideoLink<Label: View>: View {
    let video: Video
    let section: String
    let transition: Namespace.ID
    @ViewBuilder let label: () -> Label

    var body: some View {
        let route = VideoRoute(video: video, section: section)
        NavigationLink(value: route, label: label)
            .buttonStyle(.plain)
            .matchedTransitionSource(id: route.transitionID, in: transition)
    }
}

extension View {
    /// Registers the video detail destination. Declare it once per
    /// `NavigationStack`, on the stack's root content.
    func videoDestination(transition: Namespace.ID) -> some View {
        navigationDestination(for: VideoRoute.self) { route in
            VideoDestination(route: route, transition: transition)
        }
    }
}

/// The detail screen for a route. A video the catalog does not know, such as
/// one restored after a relaunch, is loaded first on a black screen.
private struct VideoDestination: View {
    let route: VideoRoute
    let transition: Namespace.ID

    @State private var loaded: Video?
    @State private var loadFailed = false

    var body: some View {
        if let video = loaded ?? VideoCatalog.shared.video(id: route.videoID) {
            VideoDetailView(video: video, transition: transition, transitionID: route.transitionID)
        } else {
            ZStack {
                Color.black.ignoresSafeArea()
                if loadFailed {
                    ContentUnavailableView("Video Unavailable", systemImage: "play.slash")
                        .foregroundStyle(.white)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .task {
                loaded = await VideoCatalog.shared.load(id: route.videoID)
                loadFailed = loaded == nil
            }
        }
    }
}

/// A navigation stack whose path survives relaunches, stored with the
/// path's `CodableRepresentation` in scene storage, as Apple documents for
/// `NavigationPath`. Every value pushed on it must be `Codable`.
struct RestorableNavigationStack<Root: View>: View {
    @SceneStorage private var storedPath: Data?
    @State private var path = NavigationPath()
    @State private var didRestore = false
    private let root: (Binding<NavigationPath>) -> Root

    init(id: String, @ViewBuilder root: @escaping (Binding<NavigationPath>) -> Root) {
        _storedPath = SceneStorage(id)
        self.root = root
    }

    var body: some View {
        NavigationStack(path: $path) {
            root($path)
        }
        .onAppear {
            guard !didRestore else { return }
            didRestore = true
            if let storedPath,
               let representation = try? JSONDecoder().decode(NavigationPath.CodableRepresentation.self, from: storedPath) {
                path = NavigationPath(representation)
            }
        }
        .onChange(of: path) { _, newPath in
            storedPath = newPath.codable.flatMap { try? JSONEncoder().encode($0) }
        }
    }
}
