import Foundation

/// The Download Options people set in the Settings app (Settings.bundle).
/// Read when a download starts; the keys and defaults match Root.plist.
struct DownloadSettings: Sendable {
    enum Quality: String, Sendable {
        case high
        case fast

        /// The tallest H.264 variant a download may pick. YouTube's HLS offers
        /// H.264 up to 1080p; VP9 is never downloaded because AVFoundation
        /// cannot play it.
        var maximumHeight: CGFloat {
            switch self {
            case .high: 1080
            case .fast: 720
            }
        }
    }

    let useMobileData: Bool
    let quality: Quality

    private enum Keys {
        static let useMobileData = "downloads.useMobileData"
        static let quality = "downloads.quality"
    }

    /// The Settings app writes a value only once it is changed there, so the
    /// bundle's defaults are registered at launch as well.
    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Keys.useMobileData: false,
            Keys.quality: Quality.fast.rawValue
        ])
    }

    static func current(in defaults: UserDefaults = .standard) -> DownloadSettings {
        DownloadSettings(
            useMobileData: defaults.bool(forKey: Keys.useMobileData),
            quality: defaults.string(forKey: Keys.quality).flatMap { Quality(rawValue: $0) } ?? .fast
        )
    }
}
