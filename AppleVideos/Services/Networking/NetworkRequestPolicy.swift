import Foundation

/// Request-level limits remain effective if the route changes after a path
/// check. Cached responses may be reused regardless of the requesting policy.
struct NetworkRequestPolicy: Hashable, Sendable {
    var allowsCellular = true
    var allowsConstrained = true

    static let interactive = Self()
    static let optional = Self(allowsConstrained: false)

    func apply(to request: inout URLRequest) {
        request.allowsCellularAccess = allowsCellular
        request.allowsConstrainedNetworkAccess = allowsConstrained
    }
}
