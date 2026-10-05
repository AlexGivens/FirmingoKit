import Foundation
import Network

/// Actor-owned Network.framework adapter with one outstanding operation in each direction.
/// No input stream or output queue grows without a bound; callbacks return to this actor.
actor TCPInspectionTransport: InspectionTransport {
    /// The single-use TCP connection, never restarted after close.
    private let connection: NWConnection
    /// A dedicated callback queue that keeps transport I/O off the main actor.
    private let queue = DispatchQueue(label: "FirmingoKit.inspection")
    /// Whether start has been invoked.
    private var started = false
    /// Sticky close state rejects reentry after EOF, cancellation, or failure.
    private var closed = false
    /// Pending connection establishment, resumed exactly once.
    private var opening: CheckedContinuation<Void, any Error>?
    /// Pending bounded receive, resumed exactly once.
    private var reading: CheckedContinuation<Data?, any Error>?
    /// Pending complete send, resumed exactly once.
    private var writing: CheckedContinuation<Void, any Error>?

    /// Creates a connection without starting network activity.
    init(endpoint: FirmingoEndpoint) throws {
        guard let port = NWEndpoint.Port(rawValue: endpoint.port) else { throw FirmingoError.invalidEndpoint }
        connection = NWConnection(host: NWEndpoint.Host(endpoint.address), port: port, using: .tcp)
    }

    /// Starts once and waits for ready. The inspector owns the deadline and closes on cancellation.
    func open() async throws {
        try Task.checkCancellation()
        guard !started, !closed else { throw FirmingoError.disconnected }
        started = true
        try await withCheckedThrowingContinuation { continuation in
            opening = continuation
            connection.stateUpdateHandler = { [weak self] state in
                Task { await self?.changed(state) }
            }
            connection.start(queue: queue)
        }
    }

    /// Enqueues one complete write; Network.framework retains partial TCP sends internally.
    func send(_ bytes: Data) async throws -> Int {
        try Task.checkCancellation()
        guard started, !closed, opening == nil, writing == nil,
              bytes.count <= FMGOFrame.headerSize + FMGOFrame.maximumPayload else {
            throw FirmingoError.protocolViolation("transport send unavailable or oversized")
        }
        try await withCheckedThrowingContinuation { continuation in
            writing = continuation
            connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
                Task { await self?.sent(error) }
            })
        }
        return bytes.count
    }

    /// Issues one bounded read. The consumer retains any coalesced frame tail.
    func receive() async throws -> Data? {
        try Task.checkCancellation()
        guard started, !closed, opening == nil, reading == nil else { throw FirmingoError.disconnected }
        return try await withCheckedThrowingContinuation { continuation in
            reading = continuation
            connection.receive(minimumIncompleteLength: 1,
                               maximumLength: FMGOFrame.headerSize + FMGOFrame.maximumPayload) { [weak self] data, _, done, error in
                Task { await self?.received(data, done: done, error: error) }
            }
        }
    }

    /// Closes and resolves pending operations even if Network.framework callbacks arrive late.
    func close() { finish(FirmingoError.disconnected) }

    /// Handles only terminal connection states and the first ready transition.
    private func changed(_ state: NWConnection.State) {
        guard !closed else { return }
        switch state {
        case .ready:
            let continuation = opening
            opening = nil
            continuation?.resume()
        case .failed(let error), .waiting(let error): finish(FirmingoError.transport(error))
        case .cancelled: finish(FirmingoError.disconnected)
        default: break
        }
    }

    /// Completes the current send or terminates the connection with its underlying error.
    private func sent(_ error: NWError?) {
        guard !closed else { return }
        if let error { finish(FirmingoError.transport(error)); return }
        let continuation = writing
        writing = nil
        continuation?.resume()
    }

    /// Delivers final bytes before EOF; any subsequent read fails on the closed connection.
    private func received(_ data: Data?, done: Bool, error: NWError?) {
        guard !closed else { return }
        if let error { finish(FirmingoError.transport(error)); return }
        let continuation = reading
        reading = nil
        if let data, !data.isEmpty { continuation?.resume(returning: data) }
        else if done { continuation?.resume(returning: nil) }
        else { continuation?.resume(throwing: FirmingoError.protocolViolation("empty transport read")) }
        if done { finish(FirmingoError.disconnected) }
    }

    /// Makes closure sticky and clears continuations before resuming them to prevent reentrancy races.
    private func finish(_ error: any Error) {
        guard !closed else { return }
        closed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        let open = opening, read = reading, write = writing
        opening = nil
        reading = nil
        writing = nil
        open?.resume(throwing: error)
        read?.resume(throwing: error)
        write?.resume(throwing: error)
    }
}
