import Foundation
import Observation
import os

/// A storage failure is visible to the app, never an empty successful fetch.
/// Repeated failures (such as periodic progress saves) share one notice until
/// a write succeeds, so playback does not produce an alert every five seconds.
@MainActor
@Observable
final class LibraryStorageStatus {
    static let shared = LibraryStorageStatus()

    struct Issue {
        let id = UUID()
        let operation: String
        var acknowledged = false
    }

    private(set) var issue: Issue?
    private let logger = Logger(subsystem: "com.scriptercarft.AppleVideos", category: "Persistence")

    func report(_ error: Error, operation: String) {
        logger.error("Could not \(operation, privacy: .public): \(String(describing: error), privacy: .private)")
        if issue == nil { issue = Issue(operation: operation) }
    }

    func acknowledge(_ id: UUID) {
        guard issue?.id == id else { return }
        issue?.acknowledged = true
    }

    func didSave() {
        // A later successful operation must not hide an error the user has
        // not seen yet, including an error raised by a didSave observer.
        if issue?.acknowledged == true { issue = nil }
    }
}
