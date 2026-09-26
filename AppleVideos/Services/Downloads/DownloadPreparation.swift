import Foundation

/// Owns cancellable preparation, before an AVFoundation background task exists.
/// A provider may finish despite cancellation; only the current job may publish
/// a result or error. All callbacks run synchronously on the main actor.
@MainActor
final class DownloadPreparation {
    private struct Job {
        let id: UUID
        let task: Task<Void, Never>
    }
    private var jobs: [String: Job] = [:]

    @discardableResult
    func start<Output>(
        for videoID: String,
        prepare: @escaping @MainActor () async throws -> Output,
        onReady: @escaping @MainActor (Output) -> Void,
        onFailure: @escaping @MainActor (Error) -> Void
    ) -> Task<Void, Never> {
        cancel(videoID)
        let id = UUID()
        let task = Task {
            do {
                try Task.checkCancellation()
                let output = try await prepare()
                try Task.checkCancellation()
                guard jobs[videoID]?.id == id else { return }
                jobs[videoID] = nil
                onReady(output)
            } catch {
                guard jobs[videoID]?.id == id else { return }
                jobs[videoID] = nil
                guard !Task.isCancelled else { return }
                onFailure(error)
            }
        }
        jobs[videoID] = Job(id: id, task: task)
        return task
    }

    func cancel(_ videoID: String) {
        jobs.removeValue(forKey: videoID)?.task.cancel()
    }
}
