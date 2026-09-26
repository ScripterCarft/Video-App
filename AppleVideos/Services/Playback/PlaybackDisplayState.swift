import Observation

/// Only presentation and transport state are published to the mini player.
/// Playback time stays in NativePlayback; it doesn't redraw the app each second.
@MainActor
@Observable
final class PlaybackDisplayState {
    var video: Video?
    var isMinimized = false
    var isPlaying = false
    var isWaiting = false
}
