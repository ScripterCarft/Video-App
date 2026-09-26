import Foundation

/// Moves the library that earlier versions kept as JSON in UserDefaults into
/// SwiftData, once. Order is kept by spacing the dates a second apart.
@MainActor
enum LegacyLibraryMigration {
    private enum Keys {
        static let saved = "apple-videos.saved"
        static let watchlist = "apple-videos.watchlist"
        static let recent = "apple-videos.recent"
        static let progress = "apple-videos.progress"
        static let downloads = "apple-videos.downloads"
    }

    private struct WatchlistEntry: Decodable {
        let video: Video
        let addedAt: Date
    }

    private struct DownloadRecord: Decodable {
        let video: Video
        let path: String
        let downloadedAt: Date
    }

    static func run(defaults: UserDefaults = .standard) throws {
        let keys = [Keys.saved, Keys.watchlist, Keys.recent, Keys.progress, Keys.downloads]
        guard keys.contains(where: { defaults.object(forKey: $0) != nil }) else { return }
        let now = Date.now

        // Decode the entire source before changing the destination. Missing
        // keys are empty; malformed or wrongly typed payloads are errors.
        let saved = try decode([Video].self, Keys.saved, defaults) ?? []
        let recent = try decode([Video].self, Keys.recent, defaults) ?? []
        let watchlist = try decode([WatchlistEntry].self, Keys.watchlist, defaults) ?? []
        let downloads = try decode([DownloadRecord].self, Keys.downloads, defaults) ?? []
        let entries = try decode([String: PlaybackProgress].self, Keys.progress, defaults) ?? [:]

        try LibraryDatabase.transaction {
            for (offset, video) in saved.enumerated() {
                let record = try LibraryDatabase.record(for: video)
                record.savedAt = record.savedAt ?? now.addingTimeInterval(-Double(offset))
            }
            for (offset, video) in recent.prefix(50).enumerated() {
                let record = try LibraryDatabase.record(for: video)
                record.watchedAt = record.watchedAt ?? now.addingTimeInterval(-Double(offset))
            }
            for entry in watchlist {
                let record = try LibraryDatabase.record(for: entry.video)
                record.watchlistAddedAt = record.watchlistAddedAt ?? entry.addedAt
            }
            for entry in downloads {
                let record = try LibraryDatabase.record(for: entry.video)
                if record.downloadPath == nil {
                    record.downloadPath = entry.path
                    record.downloadedAt = entry.downloadedAt
                }
            }
            // Positions are kept by video ID, apart from the video records.
            for (id, entry) in entries {
                guard entry.position.isFinite, entry.duration.isFinite,
                      entry.position >= 0, entry.duration > 0 else {
                    throw LibraryDatabase.StorageError.invalidLegacyData(Keys.progress)
                }
                // A repeated import after interruption must not overwrite newer progress.
                if try LibraryDatabase.progress(id: id) == nil {
                    try LibraryDatabase.setProgress(entry, for: id)
                }
            }
        }

        // Only the keys actually imported, only after the durable commit.
        // Older playlist formats are not decoded here and must remain intact.
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        _ key: String,
        _ defaults: UserDefaults
    ) throws -> T? {
        guard let value = defaults.object(forKey: key) else { return nil }
        guard let data = value as? Data else {
            throw LibraryDatabase.StorageError.invalidLegacyData(key)
        }
        return try JSONDecoder().decode(type, from: data)
    }
}
