import Foundation
@testable import FirmingoKit

/// Deterministic single-use peer recording every hello and cleanup action.
actor InspectionTestTransport: InspectionTransport {
    /// Ordered fragments delivered without a network service.
    private var fragments: [Data]
    /// Whether exhausted fragments report EOF rather than await closure.
    private let eof: Bool
    /// Suspended receive, released when the inspector closes.
    private var pending: CheckedContinuation<Data?, any Error>?
    /// All complete sends accepted by the transport.
    private(set) var sends: [Data] = []
    /// Number of opens; proves no implicit reconnect/replay.
    private(set) var opens = 0
    /// Whether resources have been closed.
    private(set) var closed = false
    /// Signals that a reader reached the controlled blocking point.
    let blocked = TestLatch()
    /// Selects fragments and exhaustion behavior.
    init(_ fragments: [Data], eof: Bool = true) {
        self.fragments = fragments
        self.eof = eof
    }
    /// Records a fresh open, rejecting a closed transport.
    func open() throws {
        guard !closed else { throw FirmingoError.disconnected }
        opens += 1
    }
    /// Records exact sends without retrying.
    func send(_ bytes: Data) throws -> Int {
        guard !closed else { throw FirmingoError.disconnected }
        sends.append(bytes)
        return bytes.count
    }
    /// Supplies deterministic data or waits until explicitly closed.
    func receive() async throws -> Data? {
        guard !closed else { throw FirmingoError.disconnected }
        if !fragments.isEmpty { return fragments.removeFirst() }
        if eof { return nil }
        await blocked.signal()
        guard !closed else { throw FirmingoError.disconnected }
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    /// Releases suspended I/O and retains observations for assertions.
    func close() {
        closed = true
        let continuation = pending
        pending = nil
        continuation?.resume(throwing: FirmingoError.disconnected)
    }
}
