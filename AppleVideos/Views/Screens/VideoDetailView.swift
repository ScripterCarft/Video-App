import SwiftUI

/// The detail screen on the SwiftUI navigation stacks (Search, Library,
/// Explore) until they move to UIKit: `VideoDetailViewController` inside a
/// thin shell. A SwiftUI stack ignores a UIKit screen's bar buttons and
/// zooms from SwiftUI sources, so the shell brings its own toolbar and zoom.
/// On UIKit stacks (Home) the controller is pushed directly.
struct VideoDetailView: View {
    let video: Video
    /// The SwiftUI zoom source, when a SwiftUI navigation stack opened the
    /// screen; a UIKit navigation controller sets its own zoom transition.
    let transition: Namespace.ID?
    let transitionID: String

    @Environment(LibraryStore.self) private var library
    @Environment(\.openVideo) private var openVideo

    var body: some View {
        DetailControllerView(
            route: VideoRoute(video: video, section: "detail"),
            library: library,
            openVideo: openVideo
        )
        .ignoresSafeArea()
        .background(.black)
        // The detail screen is always dark; its toolbar buttons use white
        // instead of the app's red accent, like the TV app.
        .tint(.white)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if let url = video.youtubeURL {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    DownloadToolbarButton(video: video)

                    // The standard share sheet from the bottom.
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
    }
}

private struct DetailControllerView: UIViewControllerRepresentable {
    let route: VideoRoute
    let library: LibraryStore
    let openVideo: OpenVideoAction

    func makeUIViewController(context: Context) -> VideoDetailViewController {
        // Up Next opens on the SwiftUI stack, without the UIKit zoom.
        VideoDetailViewController(route: route, library: library) { route, _ in
            openVideo(route)
        }
    }

    func updateUIViewController(_ controller: VideoDetailViewController, context: Context) {}
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
