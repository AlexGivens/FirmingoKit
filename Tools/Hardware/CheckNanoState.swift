import Foundation

/// Executes independent binary observation checks without an SDK transport or device.
@main struct CheckNanoState {
    /// Requires the policy rejection so malformed observations cannot count as hardware evidence.
    static func rejected(_ action: () throws -> Void) throws {
        do { try action() } catch is NanoGate.Rejected { return }
        throw NSError(domain: "NanoStateChecks", code: 1)
    }

    /// Builds a reply from explicit byte fields, independently of the production decoder.
    static func reply(tag: UInt8 = 65, seed: UInt32 = 7, loops: UInt32, nonce: UInt32 = 49) -> Data {
        var bytes: [UInt8] = [70, 81, 50, tag]
        for word in [nonce, seed, 0, seed &+ loops, loops] {
            for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8(truncatingIfNeeded: word >> shift)) }
        }
        return Data(bytes)
    }

    /// Covers golden little-endian fields, every corrupt byte, variants, replay and modular progress.
    static func main() throws {
        let golden = Data([70,81,50,65,49,0,0,0,7,0,0,0,0,0,0,0,11,3,2,1,4,3,2,1])
        let first = try NanoStateProbe.parse(golden, sketch: "state-a", nonce: 49)
        guard first.initialData == 7, first.initialBSS == 0, first.loops == 0x01020304,
              first.counter == 0x0102030b, first.bytes == golden else { throw NSError(domain: "NanoStateChecks", code: 2) }
        for offset in golden.indices {
            var corrupt = golden; corrupt[offset] ^= 1
            try rejected { _ = try NanoStateProbe.parse(corrupt, sketch: "state-a", nonce: 49) }
        }
        for invalid in [Data(), Data(golden.dropLast()), golden + Data([0])] {
            try rejected { _ = try NanoStateProbe.parse(invalid, sketch: "state-a", nonce: 49) }
        }
        try rejected { _ = try NanoStateProbe.parse(golden, sketch: "state-b", nonce: 49) }
        try rejected { _ = try NanoStateProbe.parse(golden, sketch: "unknown", nonce: 49) }
        try rejected { _ = try NanoStateProbe.parse(golden, sketch: "state-a", nonce: 115) }
        try rejected { _ = try NanoStateProbe.parse(reply(loops: 0), sketch: "state-a", nonce: 49) }
        let second = try NanoStateProbe.parse(reply(loops: first.loops + 8, nonce: 115), sketch: "state-a", nonce: 115)
        try NanoStateProbe.advancing(first, second)
        try rejected { try NanoStateProbe.advancing(first, first) }
        try rejected { try NanoStateProbe.advancing(second, first) }
        let beforeWrap = try NanoStateProbe.parse(reply(loops: UInt32.max - 2), sketch: "state-a", nonce: 49)
        let afterWrap = try NanoStateProbe.parse(reply(loops: 3, nonce: 115), sketch: "state-a", nonce: 115)
        try NanoStateProbe.advancing(beforeWrap, afterWrap)
        let other = try NanoStateProbe.parse(reply(tag: 66, seed: 23, loops: second.loops), sketch: "state-b", nonce: 49)
        try rejected { try NanoStateProbe.advancing(first, other) }
        print("Nano state checks passed: golden fields, 24 corrupt bytes, exact framing, nonce/variant, replay and modular progress; no device access")
    }
}
