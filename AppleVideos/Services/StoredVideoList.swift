import Foundation
import Observation
import SwiftData

/// The stored videos matching a filter, handed to `onChange` whenever they
/// change, the way Apple derives state from SwiftData outside SwiftUI (WWDC26
/// "What's new in SwiftData"): a `ResultsObserver` refetches after saves, and
/// `withContinuousObservation(options: [.didSet])` calls back after each
/// change. Stores turn the records into values right there, so screens never
/// read a record, and a deleted one is never read (measured in
/// `ResultsObserverTests`).
@MainActor
final class StoredVideoList {
    private let observer: ResultsObserver<StoredVideo, Never>?
    private var token: ObservationTracking.Token?

    /// Calls `onChange` with the current records right away, then after each
    /// change. An observer whose first fetch fails reports an empty list.
    init(
        _ filter: Predicate<StoredVideo>,
        sortedBy sort: SortDescriptor<StoredVideo>,
        in context: ModelContext = LibraryDatabase.context,
        onChange: @escaping @MainActor @Sendable ([StoredVideo]) -> Void
    ) {
        observer = try? ResultsObserver(filterBy: filter, sortBy: [sort], modelContext: context)
        onChange(observer.map { Array($0.results) } ?? [])
        token = withContinuousObservation(options: [.didSet]) { @MainActor [weak self] _ in
            guard let results = self?.observer?.results else { return }
            onChange(Array(results))
        }
    }
}
