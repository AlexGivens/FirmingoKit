import Foundation
import Testing
@testable import FirmingoKit

/// Independent vectors and malformed-header boundaries for the bounded frame assembler.
struct FMGOFrameTests {
    /// Every imported vector re-encodes byte-for-byte, including upload and failed-transaction frames.
    @Test func goldenVectors() throws {
        let root = try #require(Bundle.module.resourceURL).appendingPathComponent("Fixtures/protocol-v1")
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where url.pathExtension == "hex" {
            let name = String(url.path.dropFirst(root.path.count + 1).dropLast(4))
            let frame = try ProtocolFixtures.frame(name)
            #expect(try frame.encoded() == ProtocolFixtures.bytes(name))
        }
    }

    /// Every two-part TCP split, including empty fragments, preserves complete fixture bytes.
    @Test(arguments: ["hello-request", "hello-response", "binary-data", "managed-upload/hello-response"])
    func everySplit(name: String) throws {
        let golden = try ProtocolFixtures.bytes(name)
        let expected = try ProtocolFixtures.frame(name)
        for split in 0...golden.count {
            var decoder = FMGOFrameDecoder()
            var output: [FMGOFrame] = []
            for fragment in [Data(golden.prefix(split)), Data(golden.dropFirst(split))] {
                var tail = fragment
                while !tail.isEmpty {
                    tail = tail.dropFirst(try decoder.consume(tail))
                    if let frame = decoder.takeFrame() { output.append(frame) }
                }
            }
            #expect(output == [expected])
        }
    }

    /// Ready frames consume nothing until drained; coalesced tails and a partial next header survive.
    @Test func coalescedAndBytewise() throws {
        let names = ["hello-request", "binary-data", "reset-unsupported"]
        let input = try names.reduce(into: Data()) { $0.append(try ProtocolFixtures.bytes($1)) }
        for width in [1, input.count] {
            var decoder = FMGOFrameDecoder()
            var frames: [FMGOFrame] = []
            for start in stride(from: 0, to: input.count, by: width) {
                var tail = Data(input.dropFirst(start).prefix(width))
                while !tail.isEmpty {
                    tail = tail.dropFirst(try decoder.consume(tail))
                    if decoder.bufferedByteCount >= 16, let frame = decoder.takeFrame() { frames.append(frame) }
                }
            }
            #expect(frames == (try names.map(ProtocolFixtures.frame)))
            #expect(try decoder.consume(Data([0x46, 0x4d])) == 2)
            #expect(decoder.bufferedByteCount == 2)
        }
        var decoder = FMGOFrameDecoder()
        var tail = try ProtocolFixtures.bytes("hello-request")
        tail = tail.dropFirst(try decoder.consume(tail))
        _ = try decoder.consume(tail)
        #expect(try decoder.consume(input) == 0)
        let ready = decoder.takeFrame()
        #expect(ready != nil)
    }

    /// Raw channel data preserves NUL, CR/LF, and invalid UTF-8; it never passes through JSON/text.
    @Test func exactBinary() throws {
        let frame = try ProtocolFixtures.frame("binary-data")
        #expect(frame.kind == .serial)
        #expect(frame.requestID == 0)
        #expect(frame.payload == Data([0, 0, 0, 1, 0, 13, 10, 255]))
    }

    /// All invalid header fields fail with only 16 buffered bytes and permanently poison the decoder.
    @Test func terminalHeaders() throws {
        let header = Array(try ProtocolFixtures.bytes("hello-request").prefix(16))
        let mutations: [(Int, UInt8)] = [(0, 0), (4, 2), (5, 0), (5, 6), (6, 1), (7, 1), (11, 0), (5, 3), (5, 5), (12, 255)]
        for (index, value) in mutations {
            var bad = header
            bad[index] = value
            var decoder = FMGOFrameDecoder()
            #expect(throws: FirmingoError.self) { try decoder.consume(Data(bad) + Data(repeating: 1, count: 4096)) }
            #expect(decoder.bufferedByteCount == 16)
            #expect(throws: FirmingoError.self) { try decoder.consume(ProtocolFixtures.bytes("hello-request")) }
            #expect(throws: FirmingoError.self) { try decoder.negotiate(peerOffer: 4096) }
            let frame = decoder.takeFrame()
            #expect(frame == nil)
        }
    }

    /// Payload boundaries, zero payloads, and negotiation are checked independently of payload semantics.
    @Test func limits() throws {
        for limit: UInt32 in [512, 4096, 65536] {
            var decoder = FMGOFrameDecoder()
            try decoder.negotiate(peerOffer: limit)
            let cap = min(Int(limit), 4096)
            for length in [0, cap] {
                let encoded = try FMGOFrame(kind: .response, requestID: UInt32.max,
                                            payload: Data(repeating: 255, count: length)).encoded(limit: cap)
                var tail = encoded
                while !tail.isEmpty { tail = tail.dropFirst(try decoder.consume(tail)) }
                let frame = decoder.takeFrame()
                #expect(frame?.payload.count == length)
            }
            var oversized = Array(try ProtocolFixtures.bytes("hello-request").prefix(16))
            let size = UInt32(cap + 1)
            for i in 0..<4 { oversized[12 + i] = UInt8(truncatingIfNeeded: size >> (24 - 8 * i)) }
            #expect(throws: FirmingoError.self) { try decoder.consume(Data(oversized)) }
        }
        for offer: UInt32 in [0, 511, 65537, UInt32.max] {
            var decoder = FMGOFrameDecoder()
            #expect(throws: FirmingoError.self) { try decoder.negotiate(peerOffer: offer) }
        }
        var decoder = FMGOFrameDecoder()
        _ = try decoder.consume(Data([0x46]))
        #expect(throws: FirmingoError.self) { try decoder.negotiate(peerOffer: 512) }
        #expect(throws: FirmingoError.self) { try FMGOFrame(kind: .request, requestID: 0, payload: Data()).encoded() }
        #expect(throws: FirmingoError.self) {
            try FMGOFrame(kind: .serial, requestID: 1, payload: Data()).encoded()
        }
        #expect(throws: FirmingoError.self) {
            try FMGOFrame(kind: .request, requestID: 1, payload: Data(repeating: 0, count: 4097)).encoded()
        }
    }
}
