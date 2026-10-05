import Foundation

/// Single-use transport for the inspection consumer; close must promptly resolve pending I/O.
protocol InspectionTransport: Sendable {
    /// Opens once; never reconnects implicitly.
    func open() async throws
    /// Waits until it can accept at least one byte and returns the accepted prefix length.
    /// A return value of zero or more than `bytes.count` violates this boundary.
    func send(_ bytes: Data) async throws -> Int
    /// Returns at most one frame's bytes, nil on EOF. One ordered caller owns reads.
    func receive() async throws -> Data?
    /// Closes idempotently and releases every pending continuation.
    func close() async
}

extension InspectionTransport {
    /// Preserves a partial write tail until every byte has been accepted by the transport.
    /// This is transport acceptance, never an application-consumption acknowledgement.
    func sendAll(_ bytes: Data) async throws {
        var remaining = bytes
        while !remaining.isEmpty {
            try Task.checkCancellation()
            let count = try await send(remaining)
            guard (1...remaining.count).contains(count) else {
                throw FirmingoError.protocolViolation("invalid transport write count")
            }
            remaining = remaining.dropFirst(count)
        }
    }
}
