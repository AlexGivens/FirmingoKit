import Foundation
import Network
import os
import Testing
@testable import FirmingoKit

/// Exercises production connection-state handling and handshake deadlines without a network service.
@Suite(.timeLimit(.minutes(1))) struct TCPInspectionTransportTests {
    /// Permission/path waiting before ready sends no bytes, then one ready event permits exactly one hello.
    @Test func initialWaitingThenReadyUsesOneConnectionAndHello() async throws {
        let peer = TCPCallbackPeer(response: try ProtocolFixtures.bytes("hello-response"))
        let transport = TCPInspectionTransport(connection: peer)
        let deadline = TestLatch()
        let task = Task {
            try await FirmingoInspector.inspect(transport: transport, expectedBoard: .nanoRP2040Connect) {
                try await deadline.wait()
            }
        }
        try await peer.started.wait()
        await peer.emit(.waiting(.posix(.ENETDOWN)))
        await peer.emit(.waiting(.posix(.EACCES)))
        #expect(peer.snapshot.starts == 1 && peer.snapshot.sends.isEmpty && peer.snapshot.cancels == 0)
        await peer.emit(.ready)
        let device = try await task.value
        #expect(device.boardID == "nano_rp2040_connect")
        #expect(peer.snapshot.sends == [try ProtocolFixtures.bytes("hello-request")])
        #expect(peer.snapshot.starts == 1 && peer.snapshot.cancels == 1)
        await peer.emit(.ready) // Simulates a callback queued before cancel removed the handler.
        await #expect(throws: FirmingoError.self) { try await transport.open() }
        #expect(peer.snapshot.starts == 1)
    }

    /// An initial wait is bounded by the original absolute deadline and never sends hello after closure.
    @Test func deadlineDuringInitialWaitingClosesWithoutHello() async throws {
        let peer = TCPCallbackPeer(response: Data())
        let transport = TCPInspectionTransport(connection: peer)
        let deadline = TestLatch()
        let task = Task {
            try await FirmingoInspector.inspect(transport: transport, expectedBoard: .nanoRP2040Connect) {
                try await deadline.wait()
            }
        }
        try await peer.started.wait()
        await peer.emit(.waiting(.posix(.ENETDOWN)))
        await deadline.signal()
        do { _ = try await task.value; Issue.record("Expected original connection deadline") }
        catch FirmingoError.timedOut { }
        await peer.emit(.ready)
        #expect(peer.snapshot.sends.isEmpty && peer.snapshot.cancels == 1 && peer.snapshot.starts == 1)
    }

    /// Cancelling initial permission/path waiting releases the original open continuation without replay.
    @Test func cancellationDuringInitialWaitingClosesWithoutHello() async throws {
        let peer = TCPCallbackPeer(response: Data())
        let transport = TCPInspectionTransport(connection: peer)
        let deadline = TestLatch()
        let task = Task {
            try await FirmingoInspector.inspect(transport: transport, expectedBoard: .nanoRP2040Connect) {
                try await deadline.wait()
            }
        }
        try await peer.started.wait()
        await peer.emit(.waiting(.posix(.ENETDOWN)))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        await peer.emit(.ready)
        #expect(peer.snapshot.sends.isEmpty && peer.snapshot.cancels == 1)
    }

    /// A real terminal failure while opening retains its platform error instead of waiting for timeout.
    @Test func terminalFailureDuringOpen() async throws {
        let peer = TCPCallbackPeer(response: Data())
        let transport = TCPInspectionTransport(connection: peer)
        let task = Task { try await transport.open() }
        try await peer.started.wait()
        await peer.emit(.failed(.posix(.ECONNREFUSED)))
        do { try await task.value; Issue.record("Expected connection refusal") }
        catch FirmingoError.transport(let error) { #expect(error as? NWError == .posix(.ECONNREFUSED)) }
        #expect(peer.snapshot.sends.isEmpty && peer.snapshot.cancels == 1)
    }

    /// Waiting after ready is terminal, releases a pending read, and rejects any later send/open.
    @Test func establishedWaitingDoesNotReconnectOrReplay() async throws {
        let peer = TCPCallbackPeer(response: nil)
        let transport = TCPInspectionTransport(connection: peer)
        let opening = Task { try await transport.open() }
        try await peer.started.wait(); await peer.emit(.ready); try await opening.value
        let reading = Task { try await transport.receive() }
        try await peer.readRequested.wait()
        await peer.emit(.waiting(.posix(.ENETDOWN)))
        do { _ = try await reading.value; Issue.record("Expected established path loss") }
        catch FirmingoError.transport(let error) { #expect(error as? NWError == .posix(.ENETDOWN)) }
        await peer.emit(.ready)
        await #expect(throws: FirmingoError.self) { try await transport.send(Data([1])) }
        await #expect(throws: FirmingoError.self) { try await transport.open() }
        #expect(peer.snapshot.starts == 1 && peer.snapshot.cancels == 1 && peer.snapshot.sends.isEmpty)
    }
}

/// Thread-safe finite platform callback peer; all transport and handshake logic remains production code.
private final class TCPCallbackPeer: TCPInspectionConnection {
    /// Mutable callback observations protected by one platform lock; no callback is invoked under it.
    struct State {
        /// Retained to simulate an already queued late callback after cancellation.
        var handler: (@Sendable (NWConnection.State) async -> Void)?
        /// Captured application frames, without simulating a TCP retry.
        var sends: [Data] = []
        /// Sole platform-start count.
        var starts = 0
        /// Sole platform-cancellation count.
        var cancels = 0
    }
    /// Immutable lock owns every mutable observation.
    private let storage = OSAllocatedUnfairLock(initialState: State())
    /// Fixed golden hello or a deliberately blocked receive.
    private let response: Data?
    /// Signals callback registration without scheduling sleeps.
    let started = TestLatch()
    /// Signals a pending receive before path-loss injection.
    let readRequested = TestLatch()
    /// Selects an independently authored firmware frame or blocked-read behavior.
    init(response: Data?) { self.response = response }
    /// Returns a consistent observation snapshot.
    var snapshot: State { storage.withLock { $0 } }
    /// Registers the production actor's callback before announcing start.
    func start(queue: DispatchQueue, changed: @escaping @Sendable (NWConnection.State) async -> Void) {
        storage.withLock { $0.handler = changed; $0.starts += 1 }
        Task { await started.signal() }
    }
    /// Awaits actual production handling so tests can check state without time assumptions.
    func emit(_ state: NWConnection.State) async { await snapshot.handler?(state) }
    /// Records each whole frame and acknowledges local send completion.
    func send(_ bytes: Data, completion: @escaping @Sendable (NWError?) -> Void) {
        storage.withLock { $0.sends.append(bytes) }; completion(nil)
    }
    /// Returns a golden response or leaves the actor continuation pending until close.
    func receive(completion: @escaping @Sendable (Data?, Bool, NWError?) -> Void) {
        Task { await readRequested.signal() }
        if let response { completion(response, false, nil) }
    }
    /// Counts platform cancellation without delivering recursive state changes.
    func cancel() { storage.withLock { $0.cancels += 1 } }
}
