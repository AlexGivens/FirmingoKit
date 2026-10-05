import Foundation

/// Pull-based, lossless binary output for one open Firmingo console.
/// The session buffers at most 4096 bytes and stops reading TCP when full;
/// the host must keep consuming or close the console. Do not create competing iterators.
public struct SerialBytes: AsyncSequence, Sendable {
    /// One serial frame's opaque bytes, never decoded or newline-normalized.
    public typealias Element = Data
    /// The session whose ordered reader owns the transport.
    let session: FirmingoSession

    /// A single consumer's state; each `next()` asks the session for one chunk.
    public struct AsyncIterator: AsyncIteratorProtocol {
        /// The owning session.
        let session: FirmingoSession
        /// Waits for the next exact byte chunk, nil after a normal console close.
        /// Cancellation closes the session and throws `CancellationError`.
        public mutating func next() async throws -> Data? {
            try await session.receiveSerial()
        }
    }

    /// Makes a pull iterator without creating any queue or worker.
    public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(session: session) }
}
