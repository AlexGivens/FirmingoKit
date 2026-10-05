import Foundation
import Testing
@testable import FirmingoKit

/// Single-use inspection correlation, deadline, cancellation, and fresh-connection behavior.
struct FirmingoInspectorTests {
    /// Fragmented hello sends one exact golden request and closes before returning.
    @Test func fragmentedInspection() async throws {
        let golden = try ProtocolFixtures.bytes("hello-response")
        let peer = InspectionTestTransport(golden.map { Data([$0]) })
        let deadline = TestLatch()
        let device = try await FirmingoInspector.inspect(transport: peer, expectedBoard: .nanoRP2040Connect) {
            try await deadline.wait()
        }
        #expect(device.maximumPayload == 4096)
        #expect(await peer.sends == [try ProtocolFixtures.bytes("hello-request")])
        #expect(await peer.opens == 1)
        #expect(await peer.closed)
    }

    /// Wrong correlation, invalid direction, disconnect, and identity rejection close without retry.
    @Test(arguments: ["reset-unsupported", "hello-request", "binary-data", "hello-response"])
    func failedInspection(name: String) async throws {
        let peer = InspectionTestTransport([try ProtocolFixtures.bytes(name)])
        let deadline = TestLatch()
        await #expect(throws: FirmingoError.self) {
            try await FirmingoInspector.inspect(transport: peer, expectedBoard: .raspberryPiPico) {
                try await deadline.wait()
            }
        }
        #expect(await peer.closed)
        #expect(await peer.sends.count == 1)
        #expect(await peer.opens == 1)
    }

    /// A fresh inspection uses a fresh request/decoder and never resumes an incomplete previous frame.
    @Test func freshConnectionAndEOF() async throws {
        let golden = try ProtocolFixtures.bytes("hello-response")
        let first = InspectionTestTransport([Data(golden.prefix(17))])
        let deadline = TestLatch()
        await #expect(throws: FirmingoError.self) {
            try await FirmingoInspector.inspect(transport: first, expectedBoard: .nanoRP2040Connect) {
                try await deadline.wait()
            }
        }
        let second = InspectionTestTransport([golden])
        _ = try await FirmingoInspector.inspect(transport: second, expectedBoard: .nanoRP2040Connect) {
            try await deadline.wait()
        }
        #expect(await first.closed)
        #expect(await second.closed)
        #expect(await first.sends == second.sends)
    }

    /// Triggering the fake absolute deadline closes a suspended reader and reports timeout consistently.
    @Test func deadlineClosesReader() async throws {
        let peer = InspectionTestTransport([], eof: false)
        let deadline = TestLatch()
        let task = Task {
            try await FirmingoInspector.inspect(transport: peer, expectedBoard: .nanoRP2040Connect) {
                try await deadline.wait()
            }
        }
        try await peer.blocked.wait()
        await deadline.signal()
        do {
            _ = try await task.value
            Issue.record("Expected deadline failure")
        } catch FirmingoError.timedOut { }
        #expect(await peer.closed)
        #expect(await peer.sends.count == 1)
    }

    /// Task cancellation releases I/O and deadline waiters before returning CancellationError.
    @Test func cancellationClosesReader() async throws {
        let peer = InspectionTestTransport([], eof: false)
        let deadline = TestLatch()
        let task = Task {
            try await FirmingoInspector.inspect(transport: peer, expectedBoard: .nanoRP2040Connect) {
                try await deadline.wait()
            }
        }
        try await peer.blocked.wait()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await peer.closed)
        #expect(await peer.sends.count == 1)
    }

    /// Numeric endpoints accept IPv4/IPv6 and reject hostnames, malformed addresses, and zero ports.
    @Test func numericEndpoints() throws {
        #expect(try FirmingoEndpoint(address: "192.168.77.1").port == 7420)
        #expect(try FirmingoEndpoint(address: "::1", port: 1).address == "::1")
        for address in ["", "firmingo.local", "999.1.1.1", "https://192.168.77.1", "192.168.77.1:7420"] {
            #expect(throws: FirmingoError.self) { try FirmingoEndpoint(address: address) }
        }
        #expect(throws: FirmingoError.self) { try FirmingoEndpoint(address: "127.0.0.1", port: 0) }
    }
}
