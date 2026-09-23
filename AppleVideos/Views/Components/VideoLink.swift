import SwiftUI

/// Navigation value for a video's detail screen.
///
/// The transition ID names the tapped thumbnail, so the zoom transition starts
/// from the right place even when a video appears in several sections.
struct VideoRoute: Hashable {
    let video: Video
    let transitionID: String

    init(video: Video, section: String) {
        self.video = video
        transitionID = "\(section)-\(video.id)"
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
            VideoDetailView(video: route.video, transition: transition, transitionID: route.transitionID)
        }
    }
}
