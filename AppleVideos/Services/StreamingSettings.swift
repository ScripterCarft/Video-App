import Foundation

/// The Streaming Options people set in the Settings app (Settings.bundle).
/// Read when playback starts; the keys and defaults match Root.plist.
struct StreamingSettings: Sendable {
    enum MobileDataQuality: String, Sendable {
        case high
        case automatic
    }

    enum WiFiQuality: String, Sendable {
        case high
        case dataSaver
    }

    let useMobileData: Bool
    let mobileDataQuality: MobileDataQuality
    let wifiQuality: WiFiQuality

    private enum Keys {
        static let useMobileData = "streaming.useMobileData"
        static let mobileDataQuality = "streaming.mobileDataQuality"
        static let wifiQuality = "streaming.wifiQuality"
    }

    /// The Settings app writes a value only once it is changed there, so the
    /// bundle's defaults are registered at launch as well.
    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Keys.useMobileData: true,
            Keys.mobileDataQuality: MobileDataQuality.automatic.rawValue,
            Keys.wifiQuality: WiFiQuality.high.rawValue
        ])
    }

    static func current(in defaults: UserDefaults = .standard) -> StreamingSettings {
        StreamingSettings(
            useMobileData: defaults.bool(forKey: Keys.useMobileData),
            mobileDataQuality: defaults.string(forKey: Keys.mobileDataQuality)
                .flatMap { MobileDataQuality(rawValue: $0) } ?? .automatic,
            wifiQuality: defaults.string(forKey: Keys.wifiQuality)
                .flatMap { WiFiQuality(rawValue: $0) } ?? .high
        )
    }
}
