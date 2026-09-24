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

    /// Remaining time such as "2h 30m", "40m" or, under a minute, "45s".
    var remainingLabel: String {
        let seconds = Int(remaining.rounded())
        let units: Set<Duration.UnitsFormatStyle.Unit> = seconds < 60 ? [.seconds] : [.hours, .minutes]
        return Duration.seconds(seconds).formatted(.units(allowed: units, width: .narrow))
    }
}
