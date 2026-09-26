import Foundation
import SwiftData

/// An isolated macOS executable using the production persistence code.
/// No simulator, network requests, app launch, or real user preferences.
@main
@MainActor
struct StorageRegressionChecks {
    struct Failure: Error { let message: String }
    enum InjectedError: Error { case interrupted }

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure(message: message) }
    }

    static func expectFailure(_ operation: () throws -> Void) throws {
        do {
            try operation()
        } catch {
            return
        }
        throw Failure(message: "Expected the operation to fail")
    }

    static func container(at url: URL, allowsSave: Bool = true) throws -> ModelContainer {
        try ModelContainer(
            for: StoredVideo.self, WatchProgress.self,
            configurations: ModelConfiguration(url: url, allowsSave: allowsSave, cloudKitDatabase: .none)
        )
    }

    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "StorageChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            LibraryDatabase.useTestContainer(nil)
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }

        // An unavailable store must throw, not create an ephemeral library.
        try expectFailure { _ = try LibraryDatabase.allRecords() }
        try expectFailure { try LibraryDatabase.transaction {} }

        let url = folder.appendingPathComponent("library.store")
        LibraryDatabase.useTestContainer(try container(at: url))
        let video = Video.youtube(id: "storage0001", title: "Stored title", channel: "Checks")
        let another = Video.youtube(id: "storage0002", title: "Second title", channel: "Checks")
        let savedKey = "apple-videos.saved"
        let progressKey = "apple-videos.progress"
        let originalPayload = try JSONEncoder().encode([video])
        defaults.set(originalPayload, forKey: savedKey)
        defaults.set(Data("broken".utf8), forKey: progressKey)
        try expectFailure { try LegacyLibraryMigration.run(defaults: defaults) }
        try expect(defaults.data(forKey: savedKey) == originalPayload, "Malformed import deleted source")
        try expect(try LibraryDatabase.allRecords().isEmpty, "Malformed import left partial records")

        // Invalid values fail inside the transaction, rolling back prior inserts.
        let invalid = PlaybackProgress(position: 20, duration: 0, updatedAt: .now)
        defaults.set(try JSONEncoder().encode([video.id: invalid]), forKey: progressKey)
        try expectFailure { try LegacyLibraryMigration.run(defaults: defaults) }
        try expect(try LibraryDatabase.allRecords().isEmpty, "Failed transaction retained an insert")
        try expect(defaults.data(forKey: savedKey) != nil, "Failed transaction discarded source")

        let position = PlaybackProgress(position: 30, duration: 300, updatedAt: .now)
        defaults.set(try JSONEncoder().encode([video.id: position]), forKey: progressKey)
        let oldPlaylistKey = "apple-videos.playlists"
        defaults.set(Data("untouched legacy format".utf8), forKey: oldPlaylistKey)
        try LegacyLibraryMigration.run(defaults: defaults)
        try expect(defaults.object(forKey: savedKey) == nil, "Successful import retained imported key")
        try expect(defaults.object(forKey: oldPlaylistKey) != nil, "Deleted an unhandled format")

        // Reopen the durable store; data must survive a new context/container.
        LibraryDatabase.useTestContainer(try container(at: url))
        try expect(try LibraryDatabase.record(id: video.id)?.savedAt != nil, "Imported video was not durable")
        try expect(try LibraryDatabase.progress(id: video.id)?.position == 30, "Imported progress was not durable")

        // A replay after commit/before UserDefaults cleanup must not overwrite
        // newer progress or create duplicate records.
        try LibraryDatabase.transaction {
            try LibraryDatabase.setProgress(PlaybackProgress(position: 90, duration: 300, updatedAt: .now), for: video.id)
        }
        defaults.set(originalPayload, forKey: savedKey)
        defaults.set(try JSONEncoder().encode([video.id: position]), forKey: progressKey)
        try LegacyLibraryMigration.run(defaults: defaults)
        try expect(try LibraryDatabase.allRecords().count == 1, "Replay duplicated records")
        try expect(try LibraryDatabase.progress(id: video.id)?.position == 90, "Replay overwrote newer progress")

        // Roll back a mixed mutation of existing records and new records.
        try expectFailure {
            try LibraryDatabase.transaction {
                let record = try LibraryDatabase.record(for: video)
                record.title = "Should roll back"
                LibraryDatabase.context?.delete(record)
                _ = try LibraryDatabase.record(for: another)
                throw InjectedError.interrupted
            }
        }
        try expect(try LibraryDatabase.record(id: video.id)?.title == video.title, "Rollback lost original record")
        try expect(try LibraryDatabase.record(id: another.id) == nil, "Rollback retained new record")

        // A genuine SwiftData save error: import into a read-only store.
        LibraryDatabase.useTestContainer(try container(at: url, allowsSave: false))
        defaults.set(try JSONEncoder().encode([another]), forKey: savedKey)
        try expectFailure { try LegacyLibraryMigration.run(defaults: defaults) }
        try expect(defaults.object(forKey: savedKey) != nil, "Save failure deleted migration source")
        try expect(LibraryDatabase.context?.hasChanges == false, "Save failure left dirty changes")
        try expect(try LibraryDatabase.record(id: another.id) == nil, "Failed save appears successful")

        // The service must retain the last committed UI snapshot on save failure.
        let library = try LibraryStore()
        library.toggleSaved(video)
        try expect(library.isSaved(video), "Failed removal changed the published library")
        try expect(LibraryStorageStatus.shared.issue != nil, "Save failure was not reported")

        LibraryDatabase.useTestContainer(try container(at: url))
        try LegacyLibraryMigration.run(defaults: defaults)
        try expect(try LibraryDatabase.record(id: another.id)?.savedAt != nil, "Retry did not import retained source")

        // Moving legacy positions must keep the video needed by that progress.
        let legacy = Video.youtube(id: "storage0003", title: "Legacy progress", channel: "Checks")
        try LibraryDatabase.transaction {
            let record = try LibraryDatabase.record(for: legacy)
            record.setProgress(position)
        }
        try WatchProgressMigration.run()
        try expect(try LibraryDatabase.record(id: legacy.id) != nil, "Progress migration deleted its video")
        try expect(try LibraryDatabase.record(id: legacy.id)?.progressPosition == nil, "Legacy fields were not cleared")
        try expect(try LibraryDatabase.progress(id: legacy.id)?.position == 30, "Legacy progress not migrated")
        try WatchProgressMigration.run()
        try expect(try LibraryDatabase.allProgress().count == 2, "Progress migration was not idempotent")
        print("PASS: unavailable store, malformed import, rollback, durable reopen, idempotency, save failure, UI snapshot, retry, progress migration")
    }
}
