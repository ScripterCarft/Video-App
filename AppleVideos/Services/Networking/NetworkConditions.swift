import Foundation
import Network
import os

/// Tracks the current network path: whether it is constrained (Low Data
/// Mode), so optional downloads can be skipped or reduced, as Apple
/// recommends, and whether it is expensive (mobile data or a hotspot) or
/// cellular, for the Streaming Options.
/// Requests that are merely nice to have should also set
/// `allowsConstrainedNetworkAccess = false` and fall back when they fail.
final class NetworkConditions: @unchecked Sendable {
    // @unchecked: the only mutable state is guarded by the lock; the monitor
    // is configured once in init and never touched afterwards.
    static let shared = NetworkConditions()
    static let didChange = Notification.Name("NetworkConditions.didChange")

    private struct State: Equatable {
        var isConstrained = false
        var isExpensive = false
        var usesCellular = false
    }

    private let monitor = NWPathMonitor()
    private let state = OSAllocatedUnfairLock(initialState: State())

    private init() {
        monitor.pathUpdateHandler = { [state] path in
            let changed = state.withLock {
                let next = State(
                    isConstrained: path.isConstrained,
                    isExpensive: path.isExpensive,
                    usesCellular: path.usesInterfaceType(.cellular)
                )
                let changed = $0 != next
                $0 = next
                return changed
            }
            if changed {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.didChange, object: nil)
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkConditions", qos: .utility))
    }

    /// True while Low Data Mode applies to the current network.
    var isConstrained: Bool {
        state.withLock { $0.isConstrained }
    }

    /// True on mobile data and on a personal hotspot.
    var isExpensive: Bool {
        state.withLock { $0.isExpensive }
    }

    /// True while the current path goes over mobile data.
    var usesCellular: Bool {
        state.withLock { $0.usesCellular }
    }
}
