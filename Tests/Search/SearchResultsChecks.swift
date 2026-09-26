import Foundation

@main @MainActor
struct SearchResultsChecks {
    enum Failure: Error { case assertion(String), offline }

    /// Responses ignore cancellation deliberately. Tests choose their exact
    /// order, exercising the real model without network or timing assumptions.
    @MainActor final class Server {
        var calls: [(String, Bool)] = []
        private var replies: [Int: CheckedContinuation<[Video], Error>] = [:]
        private var waiter: (Int, CheckedContinuation<Void, Never>)?

        func fetch(_ query: String, _ refresh: Bool) async throws -> [Video] {
            let index = calls.count
            calls.append((query, refresh))
            return try await withCheckedThrowingContinuation { continuation in
                replies[index] = continuation
                if let (count, continuation) = waiter, calls.count >= count {
                    waiter = nil
                    continuation.resume()
                }
            }
        }

        func waitForCalls(_ count: Int) async {
            if calls.count >= count { return }
            await withCheckedContinuation { waiter = (count, $0) }
        }

        func reply(_ index: Int, _ result: Result<[Video], Error>) {
            replies.removeValue(forKey: index)!.resume(with: result)
        }
    }

    static func expect(_ value: Bool, _ message: String) throws {
        if !value { throw Failure.assertion(message) }
    }

    static func main() async throws {
        let server = Server()
        let results = SearchResults(fetch: server.fetch)
        let a = Video.youtube(id: "search00001", title: "Old", channel: "Test")
        let b = Video.youtube(id: "search00002", title: "New", channel: "Test")

        results.search(" A ")
        let initial = results.currentTask!
        await server.waitForCalls(1)
        results.search("A")
        try expect(server.calls.count == 1 && results.isLoading, "Duplicate submission restarted the request")
        let refresh = Task { await results.reload() }
        await server.waitForCalls(2)
        try expect(server.calls[1].1, "Refresh did not bypass the cache")
        results.search("B")
        let latest = results.currentTask!
        await server.waitForCalls(3)
        server.reply(1, .success([a]))
        await refresh.value
        server.reply(0, .failure(Failure.offline))
        await initial.value
        try expect(results.query == "B" && results.videos.isEmpty && results.isLoading && results.errorMessage == nil,
                   "Obsolete refresh/error changed the newer request")
        server.reply(2, .success([b]))
        await latest.value
        try expect(results.videos == [b] && !results.isLoading, "Current search failed to publish")

        // A query string alone cannot distinguish two refreshes of the same query.
        let olderRefresh = Task { await results.reload() }
        await server.waitForCalls(4)
        try expect(results.videos == [b], "Refresh discarded visible results")
        let newerRefresh = Task { await results.reload() }
        await server.waitForCalls(5)
        server.reply(4, .success([a]))
        await newerRefresh.value
        server.reply(3, .success([b]))
        await olderRefresh.value
        try expect(results.videos == [a] && !results.isLoading, "Older same-query refresh overwrote the latest")

        let clearedRefresh = Task { await results.reload() }
        await server.waitForCalls(6)
        results.search("  ")
        server.reply(5, .success([b]))
        await clearedRefresh.value
        await results.reload()
        try expect(results.query.isEmpty && results.videos.isEmpty && !results.isLoading && server.calls.count == 6,
                   "Clearing search allowed old results or an empty network request")

        results.search("C")
        let failed = results.currentTask!
        await server.waitForCalls(7)
        server.reply(6, .failure(Failure.offline))
        await failed.value
        try expect(results.errorMessage != nil && !results.isLoading, "Current error was swallowed")
        results.search("C")
        let retry = results.currentTask!
        await server.waitForCalls(8)
        server.reply(7, .success([]))
        await retry.value
        try expect(results.errorMessage == nil && !results.isLoading, "Retry did not recover")
        print("PASS: refresh vs new query, obsolete errors, same-query refresh ordering, clear, empty refresh, retry, duplicate submission")
    }
}
