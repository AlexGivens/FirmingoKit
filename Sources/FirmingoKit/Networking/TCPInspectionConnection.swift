import Foundation
import Network

/// Narrow callback boundary for testing the production TCP transport without sockets.
protocol TCPInspectionConnection: Sendable {
    /// Starts one connection and delivers platform states to its owning transport.
    func start(queue: DispatchQueue, changed: @escaping @Sendable (NWConnection.State) async -> Void)
    /// Completes one whole-frame send; the platform owns partial TCP delivery.
    func send(_ bytes: Data, completion: @escaping @Sendable (NWError?) -> Void)
    /// Requests one bounded read, preserving final bytes before EOF.
    func receive(completion: @escaping @Sendable (Data?, Bool, NWError?) -> Void)
    /// Ends platform activity and removes its state handler; late callbacks remain possible.
    func cancel()
}
