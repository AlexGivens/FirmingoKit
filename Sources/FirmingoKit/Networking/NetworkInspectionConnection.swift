import Foundation
import Network

/// Network.framework implementation of the transport's finite callback boundary.
final class NetworkInspectionConnection: TCPInspectionConnection {
    /// The single platform connection; never restarted or replaced.
    private let connection: NWConnection

    /// Validates the selected port without starting network activity.
    init(endpoint: FirmingoEndpoint) throws {
        guard let port = NWEndpoint.Port(rawValue: endpoint.port) else { throw FirmingoError.invalidEndpoint }
        connection = NWConnection(host: NWEndpoint.Host(endpoint.address), port: port, using: .tcp)
    }

    /// Installs the owner callback before starting the sole connection.
    func start(queue: DispatchQueue, changed: @escaping @Sendable (NWConnection.State) async -> Void) {
        connection.stateUpdateHandler = { state in Task { await changed(state) } }
        connection.start(queue: queue)
    }

    /// Lets Network.framework complete the entire supplied TCP write.
    func send(_ bytes: Data, completion: @escaping @Sendable (NWError?) -> Void) {
        connection.send(content: bytes, completion: .contentProcessed(completion))
    }

    /// Limits each callback to one maximum FMGO frame's worth of data.
    func receive(completion: @escaping @Sendable (Data?, Bool, NWError?) -> Void) {
        connection.receive(minimumIncompleteLength: 1,
                           maximumLength: FMGOFrame.headerSize + FMGOFrame.maximumPayload) { data, _, done, error in
            completion(data, done, error)
        }
    }

    /// Clears the state callback and cancels exactly this connection.
    func cancel() {
        connection.stateUpdateHandler = nil
        connection.cancel()
    }
}
