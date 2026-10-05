import Foundation
import Testing
@testable import FirmingoKit

/// Bounded session behavior with an independently scripted byte-stream peer.
struct FirmingoSessionTests {
    /// Exact successful response envelope used by the firmware's open/close methods.
    private static let emptyResult = Data(#"{"ok":true,"result":{}}"#.utf8)
    /// Error envelope exercising firmware ownership rejection.
    private static let busy = Data(#"{"ok":false,"error":{"code":"busy","message":"busy"}}"#.utf8)
    /// Valid channel status with u64 counters and portable queue occupancy.
    private static let status = Data(#"{"ok":true,"result":{"channel_id":1,"backend_rx_bytes":4294967296,"backend_tx_bytes":7,"pending_to_backend":2,"pending_to_peer":3}}"#.utf8)

    /// Connects without real time passing; caller must disconnect before the test ends.
    private func connect(_ peer: SessionTestTransport,
                         backend: FirmingoDevice.Backend = .application,
                         deadlineSleep: (@Sendable (Duration) async throws -> Void)? = nil) async throws -> FirmingoSession {
        let handshakeDeadline = TestLatch()
        let sleeping = deadlineSleep ?? { _ in try await TestLatch().wait() }
        return try await FirmingoSession.connect(transport: peer, expectedBoard: .nanoRP2040Connect,
                                                 expectedBackend: backend,
                                                 deadline: { try await handshakeDeadline.wait() },
                                                 deadlineSleep: sleeping)
    }

    /// A coalesced serial-before-open frame survives hello/control routing and partial writes preserve tails.
    @Test func interleavedSerialAndPartialWrites() async throws {
        let peer = SessionTestTransport(
            hello: try ProtocolFixtures.bytes("hello-response"), writeLimit: 3,
            responses: ["serial.open": [Self.emptyResult], "serial.status": [Self.status],
                        "serial.close": [Self.emptyResult]],
            openPrelude: [try ProtocolFixtures.bytes("binary-data")], coalesceOpen: true
        )
        let session = try await connect(peer)
        try await session.openConsole()
        var bytes = session.serialBytes.makeAsyncIterator()
        #expect(try await bytes.next() == Data([0, 13, 10, 255]))
        let status = try await session.serialStatus()
        #expect(status.backendReceivedBytes == 4_294_967_296)
        #expect(status.backendTransmittedBytes == 7)
        #expect(status.pendingToBackend == 2)
        #expect(status.pendingToPeer == 3)
        try await session.sendSerial(Data([0, 13, 10, 255]))
        try await session.sendSerial(Data(repeating: 0xab, count: 300))
        try await session.closeConsole()
        #expect(try await bytes.next() == nil)
        let sent = await peer.sentFrames
        #expect(sent.map(\.kind) == [.request, .request, .request, .serial, .serial, .serial, .request])
        #expect(sent.map(\.requestID) == [1, 2, 3, 0, 0, 0, 4])
        #expect(try sent[3].encoded() == ProtocolFixtures.bytes("binary-data"))
        #expect(sent[4].payload.count == 260)
        #expect(sent[5].payload.count == 48)
        #expect(await peer.writeChunks.allSatisfy { $0.count <= 3 })
        #expect(await peer.opens == 1)
        await session.disconnect()
        #expect(await peer.closed)
    }

    /// Busy ownership is a device rejection, not success; a later explicit retry uses a new ID.
    @Test func busyOpenCanBeRetried() async throws {
        let peer = SessionTestTransport(hello: try ProtocolFixtures.bytes("hello-response"),
                                        responses: ["serial.open": [Self.busy, Self.emptyResult],
                                                    "serial.close": [Self.emptyResult]])
        let session = try await connect(peer)
        do {
            try await session.openConsole()
            Issue.record("Expected busy device rejection")
        } catch FirmingoError.deviceRejected(let code, _) {
            #expect(code == "busy")
        }
        #expect(!(await peer.closed))
        await #expect(throws: FirmingoError.self) { try await session.sendSerial(Data([1])) }
        try await session.openConsole()
        try await session.closeConsole()
        #expect(await peer.sentFrames.map(\.requestID) == [1, 2, 3, 4])
        await session.disconnect()
    }

    /// A full 4096-byte queue stops transport reads until the one consumer makes room.
    @Test func slowConsumerAppliesBackpressure() async throws {
        let peer = SessionTestTransport(hello: try ProtocolFixtures.bytes("hello-response"),
                                        responses: ["serial.open": [Self.emptyResult],
                                                    "serial.close": [Self.emptyResult]])
        let session = try await connect(peer)
        try await session.openConsole()
        for index in 0..<18 {
            let payload = Data([0, 0, 0, 1]) + Data(repeating: UInt8(index), count: 256)
            await peer.inject(try FMGOFrame(kind: .serial, requestID: 0, payload: payload).encoded())
        }
        await peer.waitForDelivered(19) // Hello + open reply + 17 data reads; the 17th is held for room.
        #expect(await peer.deliveredReads == 19)
        var bytes = session.serialBytes.makeAsyncIterator()
        #expect(try await bytes.next() == Data(repeating: 0, count: 256))
        await peer.waitForDelivered(20)
        for index in 1..<18 { #expect(try await bytes.next() == Data(repeating: UInt8(index), count: 256)) }
        try await session.closeConsole()
        await session.disconnect()
    }

    /// Malformed channel-prefixed data and wrong-direction frames are terminal with no resynchronization.
    @Test(arguments: [Data([0, 0, 0, 2, 7]), Data([0, 0, 0, 1]), Data([0, 0, 0, 1, 9])])
    func invalidIncomingSerial(payload: Data) async throws {
        let peer = SessionTestTransport(hello: try ProtocolFixtures.bytes("hello-response"),
                                        responses: ["serial.open": [Self.emptyResult]])
        let session = try await connect(peer)
        try await session.openConsole()
        let received = payload.count == 5 && payload.last == 9
            ? try FMGOFrame(kind: .request, requestID: 9, payload: payload).encoded()
            : try FMGOFrame(kind: .serial, requestID: 0, payload: payload).encoded()
        await peer.inject(received)
        try await peer.closedLatch.wait()
        await #expect(throws: FirmingoError.self) { try await session.serialStatus() }
        #expect(await peer.sentFrames.count == 2)
    }

    /// Malformed correlated status data is a terminal protocol error, not an empty successful status.
    @Test func invalidStatusTerminates() async throws {
        let invalid = Data(#"{"ok":true,"result":{"channel_id":1,"backend_rx_bytes":1.0}}"#.utf8)
        let peer = SessionTestTransport(hello: try ProtocolFixtures.bytes("hello-response"),
                                        responses: ["serial.open": [Self.emptyResult], "serial.status": [invalid]])
        let session = try await connect(peer)
        try await session.openConsole()
        await #expect(throws: FirmingoError.self) { try await session.serialStatus() }
        try await peer.closedLatch.wait()
        #expect(await peer.closed)
    }

    /// Only one control request may be outstanding, while serial delivery can proceed independently.
    @Test func pendingControlIsBounded() async throws {
        let peer = SessionTestTransport(hello: try ProtocolFixtures.bytes("hello-response"),
                                        responses: ["serial.open": [Self.emptyResult]])
        let session = try await connect(peer)
        try await session.openConsole()
        let first = Task { try await session.serialStatus() }
        await peer.waitForSent(3)
        await #expect(throws: FirmingoError.self) { try await session.serialStatus() }
        await peer.inject(try ProtocolFixtures.bytes("binary-data"))
        var stream = session.serialBytes.makeAsyncIterator()
        #expect(try await stream.next() == Data([0, 13, 10, 255]))
        await peer.inject(try FMGOFrame(kind: .response, requestID: 3, payload: Self.status).encoded())
        #expect(try await first.value.backendReceivedBytes == 4_294_967_296)
        await session.disconnect()
    }

    /// Cancellation of a pending command closes transport and does not replay the status request.
    @Test func cancelledRequestClosesWithoutReplay() async throws {
        let peer = SessionTestTransport(hello: try ProtocolFixtures.bytes("hello-response"),
                                        responses: ["serial.open": [Self.emptyResult]])
        let session = try await connect(peer)
        try await session.openConsole()
        let request = Task { try await session.serialStatus() }
        await peer.waitForSent(3)
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
        try await peer.closedLatch.wait()
        #expect(await peer.sentFrames.map(\.requestID) == [1, 2, 3])
    }

    /// A controlled five-second command deadline releases an otherwise suspended status request.
    @Test func requestDeadline() async throws {
        let requestDeadline = TestLatch()
        let otherDeadline = TestLatch()
        let peer = SessionTestTransport(hello: try ProtocolFixtures.bytes("hello-response"),
                                        responses: ["serial.open": [Self.emptyResult]])
        let session = try await connect(peer, deadlineSleep: { duration in
            if duration <= .seconds(5) { try await requestDeadline.wait() }
            else { try await otherDeadline.wait() }
        })
        try await session.openConsole()
        let status = Task { try await session.serialStatus() }
        await peer.waitForSent(3)
        await requestDeadline.signal()
        await #expect(throws: FirmingoError.self) { try await status.value }
        try await peer.closedLatch.wait()
        #expect(await peer.sentFrames.count == 3)
    }

    /// Cancellation of the sole pull consumer terminates pending transport work.
    @Test func cancelledSerialConsumerCloses() async throws {
        let peer = SessionTestTransport(hello: try ProtocolFixtures.bytes("hello-response"),
                                        responses: ["serial.open": [Self.emptyResult]])
        let session = try await connect(peer)
        try await session.openConsole()
        let waiting = TestLatch()
        let consumer = Task {
            var stream = session.serialBytes.makeAsyncIterator()
            await waiting.signal()
            return try await stream.next()
        }
        try await waiting.wait()
        consumer.cancel()
        await #expect(throws: CancellationError.self) { try await consumer.value }
        try await peer.closedLatch.wait()
    }

    /// A changed expected backend prevents channel acquisition before any non-hello request.
    @Test func backendMismatchCloses() async throws {
        let peer = SessionTestTransport(hello: try ProtocolFixtures.bytes("hello-response"))
        await #expect(throws: FirmingoError.self) { try await connect(peer, backend: .uart) }
        #expect(await peer.sentFrames.map(\.requestID) == [1])
        #expect(await peer.closed)
    }

    /// Failure after a partial serial frame reports an unknown outcome with its underlying transport error.
    @Test func partialSerialWriteIsUncertain() async throws {
        let peer = SessionTestTransport(hello: try ProtocolFixtures.bytes("hello-response"), writeLimit: 3,
                                        responses: ["serial.open": [Self.emptyResult]])
        let session = try await connect(peer)
        try await session.openConsole()
        await peer.failAfter(additionalWrites: 2)
        do {
            try await session.sendSerial(Data([0, 13, 10, 255]))
            Issue.record("Expected uncertain write")
        } catch FirmingoError.uncertainOutcome(let operation, let underlying) {
            #expect(operation == "serial write")
            guard case FirmingoError.disconnected = underlying else {
                Issue.record("Expected retained transport cause")
                return
            }
        }
        try await peer.closedLatch.wait()
        #expect(await peer.sentFrames.map(\.requestID) == [1, 2])
    }

    /// A partial frame has one absolute assembly deadline; trickling cannot leave it suspended.
    @Test func incompleteFrameDeadline() async throws {
        let frameDeadline = TestLatch()
        let idleDeadline = TestLatch()
        let peer = SessionTestTransport(hello: try ProtocolFixtures.bytes("hello-response"),
                                        responses: ["serial.open": [Self.emptyResult]])
        let session = try await connect(peer, deadlineSleep: { duration in
            if duration <= .seconds(5) { try await frameDeadline.wait() }
            else { try await idleDeadline.wait() }
        })
        try await session.openConsole()
        await peer.inject(Data([0x46, 0x4d]))
        await peer.waitForDelivered(3)
        await frameDeadline.signal()
        try await peer.closedLatch.wait()
        await #expect(throws: FirmingoError.self) { try await session.serialStatus() }
    }

    /// A host that never drains the full serial queue eventually receives a bounded timeout.
    @Test func backpressureDeadline() async throws {
        let roomDeadline = TestLatch()
        let requestDeadline = TestLatch()
        let peer = SessionTestTransport(hello: try ProtocolFixtures.bytes("hello-response"),
                                        responses: ["serial.open": [Self.emptyResult]])
        let session = try await connect(peer, deadlineSleep: { duration in
            if duration <= .seconds(5) { try await requestDeadline.wait() }
            else { try await roomDeadline.wait() }
        })
        try await session.openConsole()
        let frame = try FMGOFrame(kind: .serial, requestID: 0,
                                  payload: Data([0, 0, 0, 1]) + Data(repeating: 0xaa, count: 256)).encoded()
        for _ in 0..<17 { await peer.inject(frame) }
        await peer.waitForDelivered(19)
        await roomDeadline.signal()
        try await peer.closedLatch.wait()
        var stream = session.serialBytes.makeAsyncIterator()
        await #expect(throws: FirmingoError.self) { try await stream.next() }
    }

    /// Explicit close discards queued SDK bytes; a new session never inherits or replays them.
    @Test func closeDiscardsAndReconnectStartsFresh() async throws {
        let firstPeer = SessionTestTransport(hello: try ProtocolFixtures.bytes("hello-response"),
                                             responses: ["serial.open": [Self.emptyResult],
                                                         "serial.close": [Self.emptyResult]],
                                             openPrelude: [try ProtocolFixtures.bytes("binary-data")])
        let first = try await connect(firstPeer)
        try await first.openConsole()
        try await first.closeConsole()
        var oldBytes = first.serialBytes.makeAsyncIterator()
        #expect(try await oldBytes.next() == nil)
        await first.disconnect()
        let secondPeer = SessionTestTransport(hello: try ProtocolFixtures.bytes("hello-response"),
                                              responses: ["serial.open": [Self.emptyResult]])
        let second = try await connect(secondPeer)
        try await second.openConsole()
        #expect(await secondPeer.sentFrames.map(\.requestID) == [1, 2])
        await second.disconnect()
    }
}
