import Foundation

@MainActor
enum DetailLoadingChecks {
    static func run() async throws {
        let video = Video.youtube(id: "details0001", title: "Existing title", channel: "Checks")
        let server = Server()
        let model = VideoDetailModel(video: video, loadDetails: server.details, loadRelated: server.related)
        await model.load()
        try SearchResultsChecks.expect(model.hasLoadFailure && model.detailsLoadFinished && model.relatedLoadFinished,
                                       "Failed details left an endless loading state")
        try SearchResultsChecks.expect(model.shown == video, "Failure discarded existing metadata")
        await model.load()
        try SearchResultsChecks.expect(!model.hasLoadFailure && model.shown.title == "Refreshed",
                                       "Retry did not recover failed metadata")
        try SearchResultsChecks.expect(server.detailCalls == 2 && server.relatedCalls == 1,
                                       "Retry reloaded a successfully empty Up Next list")
        await model.load()
        try SearchResultsChecks.expect(server.detailCalls == 2 && server.relatedCalls == 1,
                                       "Reappearing reloaded successful results")

        let relatedServer = Server()
        relatedServer.detailCalls = 1
        relatedServer.failRelated = true
        let partial = VideoDetailModel(video: video, loadDetails: relatedServer.details, loadRelated: relatedServer.related)
        await partial.load()
        try SearchResultsChecks.expect(partial.hasLoadFailure && partial.shown.title == "Refreshed",
                                       "Related failure discarded successful details")
        relatedServer.failRelated = false
        await partial.load()
        try SearchResultsChecks.expect(!partial.hasLoadFailure && relatedServer.detailCalls == 2 && relatedServer.relatedCalls == 2,
                                       "Related retry fetched successful details again")

        let delayed = SearchResultsChecks.Server()
        let cancelled = VideoDetailModel(video: video, loadDetails: { _ in Server.payload }, loadRelated: { id in
            try await delayed.fetch(id, false)
        })
        let load = Task { await cancelled.load() }
        await delayed.waitForCalls(1)
        await cancelled.load()
        try SearchResultsChecks.expect(delayed.calls.count == 1, "Concurrent loads duplicated a request")
        load.cancel()
        delayed.reply(0, .success([video]))
        await load.value
        try SearchResultsChecks.expect(cancelled.related.isEmpty && !cancelled.isLoading,
                                       "Cancelled load published a late response")
        let retry = Task { await cancelled.load() }
        await delayed.waitForCalls(2)
        delayed.reply(1, .success([video]))
        await retry.value
        try SearchResultsChecks.expect(cancelled.related == [video] && !cancelled.hasLoadFailure,
                                       "Cancelled step was not retryable")
        print("PASS: partial detail failure, targeted retry, successful empty result, duplicate load, cancellation and late response")
    }

    @MainActor final class Server {
        var detailCalls = 0
        var relatedCalls = 0
        var failRelated = false
        nonisolated static let payload = YouTubeService.VideoDetails(
            title: "Refreshed", channelName: "Checks", duration: "5:00", publishedText: nil,
            publishedAt: nil, viewCountText: nil, thumbnailURL: nil, description: "Full description", badges: []
        )

        func details(_ id: String) async throws -> YouTubeService.VideoDetails {
            detailCalls += 1
            if detailCalls == 1 { throw SearchResultsChecks.Failure.offline }
            return Self.payload
        }

        func related(_ id: String) async throws -> [Video] {
            relatedCalls += 1
            if failRelated { throw SearchResultsChecks.Failure.offline }
            return []
        }
    }
}
