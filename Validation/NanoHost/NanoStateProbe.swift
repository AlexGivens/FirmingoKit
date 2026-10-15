import Foundation

/// Independent binary observation checks for the two bounded FMS2 qualification sketches.
enum NanoStateProbe {
    /// Exact decoded fields plus original bytes; no status or LED is treated as RAM initialization proof.
    struct Sample {
        /// Startup data value observed inside setup.
        let initialData: UInt32
        /// Startup loop-counter BSS observed before the first loop.
        let initialBSS: UInt32
        /// Current initialized-data counter.
        let counter: UInt32
        /// Number of loops observed in the same reply.
        let loops: UInt32
        /// Original 24-byte response for independent journal review.
        let bytes: Data
    }
    /// Requires the selected variant, fresh nonce, startup values and exact per-loop state relationship.
    static func parse(_ bytes: Data, sketch: String, nonce: UInt8) throws -> Sample {
        guard bytes.count == 24, ["state-a", "state-b"].contains(sketch) else { throw NanoGate.Rejected() }
        let data = Array(bytes), seed: UInt32 = sketch == "state-a" ? 7 : 23
        guard data[0..<4].elementsEqual([70, 81, 50, sketch == "state-a" ? 65 : 66]) else { throw NanoGate.Rejected() }
        let values = stride(from: 4, to: 24, by: 4).map { offset in data[offset..<offset + 4].reversed().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } }
        guard values[0] == nonce, values[1] == seed, values[2] == 0, values[4] > 0, values[3] == seed &+ values[4] else { throw NanoGate.Rejected() }
        return Sample(initialData: values[1], initialBSS: values[2], counter: values[3], loops: values[4], bytes: bytes)
    }
    /// Requires forward progress without assuming a particular hardware loop rate or wall-clock timing.
    static func advancing(_ first: Sample, _ second: Sample) throws {
        let delta = second.loops &- first.loops
        guard delta > 0, delta < 0x80000000, second.counter &- first.counter == delta else { throw NanoGate.Rejected() }
    }
}
