import Foundation

/// Controlled responses deliberately ignore cancellation, like a shared
/// resolver can. No sleeps, network, simulator or timing-dependent assertions.
@main
@MainActor
struct DownloadPreparationChecks {
    enum Failure: Error { case assertion(String), oldRequest }

    @MainActor final class Response {
        private var continuation: CheckedContinuation<Int, Error>?
        private var started: CheckedContinuation<Void, Never>?

        func load() async throws -> Int {
            try await withCheckedThrowingContinuation {
                continuation = $0
                started?.resume()
                started = nil
            }
        }

        func waitUntilStarted() async {
            if continuation != nil { return }
            await withCheckedContinuation { started = $0 }
        }

        func complete(_ result: Result<Int, Error>) {
            let current = continuation
            continuation = nil
            current!.resume(with: result)
        }
    }

    static func expect(_ value: Bool, _ message: String) throws {
        if !value { throw Failure.assertion(message) }
    }

    static func main() async throws {
        let preparation = DownloadPreparation()
        var results: [Int] = []
        var errors = 0

        // Reproduce start A -> cancel -> start B -> A returns successfully.
        let old = Response()
        let first = preparation.start(for: "video", prepare: { try await old.load() },
                                      onReady: { results.append($0) }, onFailure: { _ in errors += 1 })
        await old.waitUntilStarted()
        preparation.cancel("video")
        let current = Response()
        let second = preparation.start(for: "video", prepare: { try await current.load() },
                                       onReady: { results.append($0) }, onFailure: { _ in errors += 1 })
        await current.waitUntilStarted()
        old.complete(.success(1))
        await first.value
        try expect(results.isEmpty && errors == 0, "Cancelled success escaped into the replacement")
        current.complete(.success(2))
        await second.value
        try expect(results == [2], "Old completion removed the replacement job")

        // An old failure arriving after the replacement finishes stays silent.
        let late = Response()
        let third = preparation.start(for: "video", prepare: { try await late.load() },
                                      onReady: { results.append($0) }, onFailure: { _ in errors += 1 })
        await late.waitUntilStarted()
        let fourth = preparation.start(for: "video", prepare: { 4 },
                                       onReady: { results.append($0) }, onFailure: { _ in errors += 1 })
        await fourth.value
        late.complete(.failure(Failure.oldRequest))
        await third.value
        try expect(results == [2, 4] && errors == 0, "An old error replaced current state")

        // Immediate cancellation must not even enter the provider.
        var called = false
        let immediate = preparation.start(for: "video", prepare: { called = true; return 5 },
                                          onReady: { results.append($0) }, onFailure: { _ in errors += 1 })
        preparation.cancel("video")
        await immediate.value
        try expect(!called && results == [2, 4], "Cancelled-before-start preparation ran")

        // Cancelling one video leaves another alone; genuine failures surface.
        let independent = Response()
        let fifth = preparation.start(for: "other", prepare: { try await independent.load() },
                                      onReady: { results.append($0) }, onFailure: { _ in errors += 1 })
        await independent.waitUntilStarted()
        preparation.cancel("video")
        independent.complete(.failure(Failure.oldRequest))
        await fifth.value
        try expect(errors == 1, "Current errors were suppressed or cross-video cancellation leaked")

        // The two background sessions may reuse the same numeric task ID.
        let wifi = DownloadTaskIdentity(sessionIdentifier: "wifi", taskIdentifier: 1)
        let cellular = DownloadTaskIdentity(sessionIdentifier: "cellular", taskIdentifier: 1)
        try expect(wifi != cellular, "Session identity was lost")
        let restored = try JSONDecoder().decode(DownloadTaskIdentity.self, from: JSONEncoder().encode(wifi))
        try expect(restored == wifi, "Task identity did not survive persistence")
        print("PASS: cancelled success, late failure, replacement ownership, immediate cancellation, independent videos, persisted session identity")
    }
}
