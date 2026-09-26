import Foundation

/// How far a video was watched on this device.
struct PlaybackProgress: Codable, Hashable, Sendable {
    var position: Double
    var duration: Double
    var updatedAt: Date

    /// Positions this close to the start are not worth resuming.
    static let minimumResumePosition: Double = 10
    /// From this share of the duration on, a video counts as finished.
    static let finishedFraction = 0.95

    var fraction: Double {
        duration > 0 ? min(max(position / duration, 0), 1) : 0
    }

    var remaining: Double {
        max(0, duration - position)
    }

    /// Started, but neither barely begun nor finished.
    var isResumable: Bool {
        position >= Self.minimumResumePosition && fraction < Self.finishedFraction
    }

    /// Remaining time in hours and minutes, such as "2h 30m" or "40m". Anything
    /// under a minute reads "1m".
    var remainingLabel: String {
        let seconds = max(60, Int(remaining.rounded()))
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}
