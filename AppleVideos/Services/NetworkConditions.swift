import Foundation
import Network
import os

/// Tracks whether the current network path is constrained (Low Data Mode),
/// so optional downloads can be skipped or reduced, as Apple recommends.
/// Requests that are merely nice to have should also set
/// `allowsConstrainedNetworkAccess = false` and fall back when they fail.
final class NetworkConditions: @unchecked Sendable {
    // @unchecked: the only mutable state is guarded by the lock; the monitor
    // is configured once in init and never touched afterwards.
    static let shared = NetworkConditions()

    private let monitor = NWPathMonitor()
    private let constrained = OSAllocatedUnfairLock(initialState: false)

    private init() {
        monitor.pathUpdateHandler = { [constrained] path in
            constrained.withLock { $0 = path.isConstrained }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkConditions", qos: .utility))
    }

    /// True while Low Data Mode applies to the current network.
    var isConstrained: Bool {
        constrained.withLock { $0 }
    }
}
