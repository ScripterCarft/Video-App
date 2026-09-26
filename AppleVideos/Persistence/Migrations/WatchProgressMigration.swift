import Foundation

@MainActor
enum WatchProgressMigration {
    /// A malformed legacy position is retained for recovery, never cleared.
    static func run() throws {
        try LibraryDatabase.transaction {
            for record in try LibraryDatabase.allRecords() where record.progressPosition != nil {
                guard let legacy = record.progress,
                      legacy.position.isFinite, legacy.duration.isFinite,
                      legacy.position >= 0, legacy.duration > 0 else {
                    throw LibraryDatabase.StorageError.invalidLegacyData("watch progress")
                }
                if try LibraryDatabase.progress(id: record.id) == nil {
                    try LibraryDatabase.setProgress(legacy, for: record.id)
                }
                record.setProgress(nil)
                try LibraryDatabase.deleteIfUnused(record)
            }
        }
    }
}
