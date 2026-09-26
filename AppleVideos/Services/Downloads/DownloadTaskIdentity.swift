import Foundation

/// Task identifiers are unique only inside a session, not across the app's
/// Wi-Fi and cellular sessions. Persist both to reject stale delegate events.
struct DownloadTaskIdentity: Codable, Equatable, Sendable {
    let sessionIdentifier: String
    let taskIdentifier: Int
}
