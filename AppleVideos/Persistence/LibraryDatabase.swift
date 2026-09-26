import Foundation
import SwiftData

/// The durable store. Models stay inside synchronous main-actor operations;
/// screens receive value snapshots only after a successful commit.
@MainActor
enum LibraryDatabase {
    private static var container: ModelContainer?

    static var context: ModelContext? { container?.mainContext }

    #if STORAGE_CHECKS
    /// Only compiled by the isolated macOS regression executable, never by
    /// the application. Tests can supply temporary durable/read-only stores.
    static func useTestContainer(_ container: ModelContainer?) {
        self.container = container
        context?.autosaveEnabled = false
    }
    #endif

    /// Keep the original default store location and schema. Never substitute
    /// an in-memory store when opening or automatic schema migration fails.
    static func open() throws {
        guard container == nil else { return }
        let opened = try ModelContainer(for: StoredVideo.self, WatchProgress.self)
        opened.mainContext.autosaveEnabled = false
        container = opened
    }

    private static func requireContext() throws -> ModelContext {
        guard let context else { throw StorageError.notOpen }
        return context
    }

    /// No suspension inside a transaction: another operation cannot save its
    /// partial changes. Roll back fetch failures as well as save failures.
    @discardableResult
    static func transaction<T>(_ changes: () throws -> T) throws -> T {
        let context = try requireContext()
        do {
            let result = try changes()
            if context.hasChanges { try context.save() }
            return result
        } catch {
            context.rollback()
            throw error
        }
    }

    static func record(id: String) throws -> StoredVideo? {
        var descriptor = FetchDescriptor<StoredVideo>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try requireContext().fetch(descriptor).first
    }

    static func record(for video: Video) throws -> StoredVideo {
        if let existing = try record(id: video.id) { return existing }
        let record = StoredVideo(video: video)
        try requireContext().insert(record)
        return record
    }

    static func allRecords() throws -> [StoredVideo] {
        try requireContext().fetch(FetchDescriptor<StoredVideo>())
    }

    static func progress(id: String) throws -> WatchProgress? {
        var descriptor = FetchDescriptor<WatchProgress>(predicate: #Predicate { $0.videoID == id })
        descriptor.fetchLimit = 1
        return try requireContext().fetch(descriptor).first
    }

    static func allProgress() throws -> [WatchProgress] {
        try requireContext().fetch(FetchDescriptor<WatchProgress>())
    }

    static func setProgress(_ progress: PlaybackProgress?, for id: String) throws {
        let context = try requireContext()
        let existing = try self.progress(id: id)
        guard let progress else {
            if let existing { context.delete(existing) }
            return
        }
        if let existing {
            existing.position = progress.position
            existing.duration = progress.duration
            existing.updatedAt = progress.updatedAt
        } else {
            context.insert(WatchProgress(videoID: id, progress: progress))
        }
    }

    static func deleteProgress(_ progress: WatchProgress) throws {
        try requireContext().delete(progress)
    }

    static func deleteIfUnused(_ record: StoredVideo) throws {
        if record.isUnused, try progress(id: record.id) == nil {
            try requireContext().delete(record)
        }
    }

    enum StorageError: LocalizedError {
        case notOpen
        case invalidLegacyData(String)

        var errorDescription: String? {
            switch self {
            case .notOpen: "The library could not be opened."
            case let .invalidLegacyData(key): "The stored data for \(key) could not be read."
            }
        }
    }
}
