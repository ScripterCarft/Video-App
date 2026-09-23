import Observation

/// Starts playback for a screen: resolves the source, hands the player to
/// `NativePlayback` and, when no native source exists, provides the embedded
/// fallback to show. Owned as `@State` by the screen that has a Play button.
@MainActor
@Observable
final class PlaybackStarter {
    struct Fallback {
        let video: Video
        let diagnostic: String
    }

    private(set) var isPreparing = false
    var fallback: Fallback?
    @ObservationIgnored private var task: Task<Void, Never>?

    func start(_ video: Video, description: String?, library: LibraryStore) {
        guard !isPreparing else { return }
        isPreparing = true
        task = Task {
            let outcome = await NativePlayback.play(video, description: description) { reachedWatchThreshold in
                if reachedWatchThreshold {
                    library.markWatched(video)
                }
            }
            guard !Task.isCancelled else { return }
            isPreparing = false
            task = nil
            if case let .fallback(diagnostic) = outcome {
                fallback = Fallback(video: video, diagnostic: diagnostic)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isPreparing = false
    }
}
