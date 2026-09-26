import Foundation
import Observation
import SwiftData
import Synchronization
import Testing
import UIKit
@testable import Apple_Videos

/// Checks, with the real SDK, how SwiftData's `ResultsObserver` (iOS 27)
/// reports changes, before the library lists are built on it. Each case also
/// prints a `PROBE` line with what it measured; CI shows those lines.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ResultsObserverTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(
            for: StoredVideo.self, WatchProgress.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func savedObserver() throws -> ResultsObserver<StoredVideo, Never> {
        try ResultsObserver<StoredVideo, Never>(
            filterBy: #Predicate { $0.savedAt != nil },
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)],
            modelContext: context
        )
    }

    private func record(_ id: String) -> StoredVideo {
        StoredVideo(video: .youtube(id: id, title: "Title \(id)", channel: "Channel"))
    }

    @Test func insertingAMatchingRecordAndSavingUpdatesResults() async throws {
        let observer = try savedObserver()
        #expect(observer.results.isEmpty)

        let change = await observeChange(of: { _ = observer.results }) {
            let video = record("a")
            video.savedAt = .now
            context.insert(video)
            try context.save()
        }
        probe("insert + save of a matching record: \(change)")
        #expect(change.fired)
        #expect(observer.results.map(\.id) == ["a"])
    }

    @Test func insertingWithoutSavingIsReported() async throws {
        let observer = try savedObserver()
        let change = await observeChange(of: { _ = observer.results }) {
            let video = record("b")
            video.savedAt = .now
            context.insert(video)
        }
        probe("insert without save: \(change), results \(observer.results.map(\.id))")
    }

    /// Measured on the iOS 27.0 simulator: the first save of a new
    /// WatchProgress does report a change (once per video), but saving a
    /// changed one, which playback does every 5 s, does not.
    @Test func savingOnlyWatchProgressLeavesVideoResultsAlone() async throws {
        let video = record("c")
        video.savedAt = .now
        context.insert(video)
        try context.save()
        let observer = try savedObserver()

        let change = await observeChange(of: { _ = observer.results }) {
            context.insert(WatchProgress(videoID: "c", progress: PlaybackProgress(position: 30, duration: 600, updatedAt: .now)))
            try context.save()
        }
        probe("save of a new WatchProgress only: \(change)")

        let update = await observeChange(of: { _ = observer.results }) {
            let entry = try context.fetch(FetchDescriptor<WatchProgress>()).first
            entry?.position = 35
            try context.save()
        }
        probe("save of a changed WatchProgress only: \(update)")
        #expect(!update.fired)
    }

    @Test func changingARecordOutsideTheFilterLeavesResultsAlone() async throws {
        let saved = record("d")
        saved.savedAt = .now
        let other = record("e")
        context.insert(saved)
        context.insert(other)
        try context.save()
        let observer = try savedObserver()

        let change = await observeChange(of: { _ = observer.results }) {
            other.watchedAt = .now
            try context.save()
        }
        probe("save of a record outside the filter: \(change)")
    }

    @Test func changingAnIncludedRecordsTitleIsReported() async throws {
        let video = record("f")
        video.savedAt = .now
        context.insert(video)
        try context.save()
        let observer = try savedObserver()
        let shown = try #require(observer.results.first)

        let viaResults = await observeChange(of: { _ = observer.results }) {
            video.title = "New title"
            try context.save()
        }
        probe("title change of an included record, observing results: \(viaResults)")

        let viaModel = await observeChange(of: { _ = shown.title }) {
            video.title = "Newer title"
            try context.save()
        }
        probe("title change of an included record, observing the model: \(viaModel)")
        #expect(viaResults.fired || viaModel.fired)
    }

    @Test func removingFromTheFilterUpdatesResults() async throws {
        let video = record("g")
        video.savedAt = .now
        context.insert(video)
        try context.save()
        let observer = try savedObserver()

        let change = await observeChange(of: { _ = observer.results }) {
            video.savedAt = nil
            try context.save()
        }
        probe("unsave + save: \(change), results \(observer.results.map(\.id))")
        #expect(change.fired)
        #expect(observer.results.isEmpty)
    }

    /// Measured on iOS 27: reading a record deleted and saved while an
    /// observer still lists it (until its update, milliseconds later) crashes
    /// with "Could not cast value of type 'Optional<Any>' to 'String'". So
    /// records only leave their lists while the app runs; a record leaving
    /// its last list stays readable.
    @Test func aRecordLeavingItsLastListStaysReadable() async throws {
        let video = record("i")
        video.savedAt = .now
        context.insert(video)
        try context.save()
        let observer = try savedObserver()
        let shown = try #require(observer.results.first)

        video.savedAt = nil
        try context.save()
        #expect(shown.title == "Title i")
        try await Task.sleep(for: .milliseconds(300))
        #expect(observer.results.isEmpty)
    }

    /// Unused records are deleted at launch, before any observer exists.
    @Test func launchDeletesOnlyUnusedRecords() throws {
        let unused = record("j")
        let saved = record("k")
        saved.savedAt = .now
        context.insert(unused)
        context.insert(saved)
        try context.save()

        LibraryDatabase.deleteUnusedRecords(in: context)
        let remaining = try context.fetch(FetchDescriptor<StoredVideo>()).map(\.id)
        #expect(remaining == ["k"])
    }

    /// The part that matters for the UIKit screens: a view that reads the
    /// results in `updateProperties()` runs it again by itself.
    @Test func uikitUpdatePropertiesTracksResults() async throws {
        let observer = try savedObserver()
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let view = CountingView(observer: observer)
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(view)
        window.isHidden = false
        defer { window.isHidden = true }

        view.updatePropertiesIfNeeded()
        let initial = view.updates
        #expect(initial >= 1)

        let video = record("h")
        video.savedAt = .now
        context.insert(video)
        try context.save()
        let afterInsert = await waitForUpdates(of: view, beyond: initial)
        probe("UIKit updateProperties: \(initial) before, \(afterInsert.count) after insert (\(afterInsert.milliseconds) ms), shown \(view.shownIDs)")
        #expect(afterInsert.count > initial)
        #expect(view.shownIDs == ["h"])

        context.insert(WatchProgress(videoID: "h", progress: PlaybackProgress(position: 30, duration: 600, updatedAt: .now)))
        try context.save()
        let afterProgress = await waitForUpdates(of: view, beyond: afterInsert.count)
        probe("UIKit updateProperties after a new WatchProgress save: \(afterProgress.count) (was \(afterInsert.count))")

        let entry = try #require(try context.fetch(FetchDescriptor<WatchProgress>()).first)
        entry.position = 40
        try context.save()
        let afterUpdate = await waitForUpdates(of: view, beyond: afterProgress.count)
        probe("UIKit updateProperties after a changed WatchProgress save: \(afterUpdate.count) (was \(afterProgress.count))")
        #expect(afterUpdate.count == afterProgress.count)
    }

    // MARK: - Helpers

    struct Change: CustomStringConvertible {
        /// Whether observation reported a change within the wait.
        let fired: Bool
        /// Whether it was reported before the action returned.
        let synchronous: Bool
        let milliseconds: Int

        var description: String {
            fired ? "fired \(synchronous ? "synchronously" : "after \(milliseconds) ms")" : "not fired within 1 s"
        }
    }

    /// Tracks the reads in `read`, runs `action` and waits up to a second
    /// for observation to report a change.
    private func observeChange(of read: @escaping @MainActor () -> Void, after action: () throws -> Void) async -> Change {
        let flag = Mutex(false)
        withObservationTracking {
            read()
        } onChange: {
            flag.withLock { $0 = true }
        }
        let start = ContinuousClock.now
        try? action()
        let synchronous = flag.withLock { $0 }
        while !flag.withLock({ $0 }), ContinuousClock.now - start < .seconds(1) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let elapsed = ContinuousClock.now - start
        return Change(
            fired: flag.withLock { $0 },
            synchronous: synchronous,
            milliseconds: Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        )
    }

    private func waitForUpdates(of view: CountingView, beyond count: Int) async -> (count: Int, milliseconds: Int) {
        let start = ContinuousClock.now
        while view.updates <= count, ContinuousClock.now - start < .seconds(1) {
            try? await Task.sleep(for: .milliseconds(10))
            view.superview?.layoutIfNeeded()
        }
        let elapsed = ContinuousClock.now - start
        return (view.updates, Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000))
    }

    private func probe(_ message: String) {
        print("PROBE ResultsObserver: \(message)")
    }
}

/// Reads the observer's results in `updateProperties()` and counts the calls.
private final class CountingView: UIView {
    let observer: ResultsObserver<StoredVideo, Never>
    private(set) var updates = 0
    private(set) var shownIDs: [String] = []

    init(observer: ResultsObserver<StoredVideo, Never>) {
        self.observer = observer
        super.init(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func updateProperties() {
        super.updateProperties()
        updates += 1
        shownIDs = observer.results.map(\.id)
    }
}
