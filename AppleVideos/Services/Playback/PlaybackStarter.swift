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
    /// Shown when Use Mobile Data is off and the device is on mobile data.
    var isShowingMobileDataAlert = false
    @ObservationIgnored private var task: Task<Void, Never>?

    func start(_ video: Video, description: String?, library: LibraryStore) {
        guard !isPreparing else { return }
        isPreparing = true
        task = Task {
            let outcome = await NativePlayback.play(
                video,
                description: description,
                startTime: library.resumePosition(for: video),
                onProgress: { position, duration in
                    library.recordProgress(for: video, position: position, duration: duration)
                },
                onFinish: { [weak self] ending in
                    // The player is closed now, so the UI may show the new progress.
                    library.publishProgress()
                    switch ending {
                    case let .closed(reachedWatchThreshold):
                        if reachedWatchThreshold {
                            library.markWatched(video)
                        }
                    case let .failed(diagnostic):
                        self?.fallBack(to: video, diagnostic: diagnostic)
                    }
                }
            )
            guard !Task.isCancelled else { return }
            isPreparing = false
            task = nil
            switch outcome {
            case let .fallback(diagnostic):
                fallBack(to: video, diagnostic: diagnostic)
            case .mobileDataOff:
                isShowingMobileDataAlert = true
            case .presented, .cancelled, .unavailable:
                break
            }
        }
    }

    /// Shows the embedded player, unless it would stream over mobile data that
    /// the Streaming Options do not allow (the web player cannot be kept off it).
    private func fallBack(to video: Video, diagnostic: String) {
        if NativePlayback.isMobileDataBlocked() {
            isShowingMobileDataAlert = true
        } else {
            fallback = Fallback(video: video, diagnostic: diagnostic)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isPreparing = false
    }
}
