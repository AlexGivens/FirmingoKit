import Foundation
import Testing
@testable import FirmingoKit

/// Loads independent firmware vectors from this test bundle, never from a sibling checkout.
enum ProtocolFixtures {
    /// Parses whitespace-separated hex and rejects corrupt fixture text.
    static func bytes(_ name: String) throws -> Data {
        let root = try #require(Bundle.module.resourceURL)
        let url = root.appendingPathComponent("Fixtures/protocol-v1/\(name).hex")
        let text = try String(contentsOf: url, encoding: .utf8)
        return Data(try text.split(whereSeparator: \.isWhitespace).map {
            try #require(UInt8($0, radix: 16))
        })
    }
    /// Decodes one complete golden frame, requiring no trailing bytes.
    static func frame(_ name: String) throws -> FMGOFrame {
        var bytes = try bytes(name)
        var decoder = FMGOFrameDecoder()
        while !bytes.isEmpty { bytes = bytes.dropFirst(try decoder.consume(bytes)) }
        let frame = decoder.takeFrame()
        return try #require(frame)
    }
}
