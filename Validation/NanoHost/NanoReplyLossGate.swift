import Foundation
import CoreFoundation

/// Finite observer for a single real commit request/reply; used only by the explicit qualification proxy.
struct NanoReplyLossGate {
    /// Transaction selected after actual SDK RAM verification.
    let uploadID: UInt32
    /// Expected capsule extent.
    let size: UInt32
    /// Expected whole-capsule identity.
    let sha256: String
    /// Correlated request consumed once before forwarding.
    private(set) var commitRequestID: UInt32?
    /// Actual complete firmware response withheld from the SDK, never a synthesized reply.
    private(set) var withheldResponse: Data?

    /// Requires a lexical unsigned integer and rejects JSON booleans, fractions and strings.
    private static func uint(_ value: Any?) -> UInt32? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return UInt32(number.stringValue)
    }
    /// Requires an actual JSON boolean rather than Foundation's permissive number bridging.
    private static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    /// Validates the fixed FMGO framing without interpreting binary upload bytes.
    static func header(_ data: Data, complete: Bool = true) throws -> (kind: UInt8, id: UInt32, size: Int) {
        let b = Array(data)
        guard b.count >= 16, Array(b[0..<8]) == [70,77,71,79,1,b[5],0,0], (1...4).contains(b[5]) else { throw NanoGate.Rejected() }
        let id = b[8..<12].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let length = b[12..<16].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length <= 4096, !complete || b.count == 16 + Int(length) else { throw NanoGate.Rejected() }
        return (b[5], id, Int(length))
    }

    /// Recognizes only control operations; other complete frames remain opaque and unchanged.
    static func operation(_ frame: Data) throws -> String? {
        guard try header(frame).kind == 1 else { return nil }
        guard let value = try JSONSerialization.jsonObject(with: Data(frame.dropFirst(16))) as? [String: Any],
              let op = value["op"] as? String else { throw NanoGate.Rejected() }
        return op
    }

    /// Rejects wrong targets/records and every second commit instead of forwarding a replay.
    mutating func observeCommit(_ frame: Data) throws {
        let h = try Self.header(frame)
        guard h.kind == 1, h.id > 0, commitRequestID == nil,
              let value = try JSONSerialization.jsonObject(with: Data(frame.dropFirst(16))) as? [String: Any],
              Set(value.keys) == ["op", "target_id", "upload_id"], value["op"] as? String == "flash.commit",
              Self.uint(value["target_id"]) == 2, Self.uint(value["upload_id"]) == uploadID else { throw NanoGate.Rejected() }
        commitRequestID = h.id
    }

    /// Withholds exactly a matching real queued-commit response; malformed/unrelated replies cannot prove the fault.
    mutating func shouldForward(_ frame: Data) throws -> Bool {
        let h = try Self.header(frame)
        guard h.kind == 2, h.id == commitRequestID else { return true }
        guard withheldResponse == nil,
              let value = try JSONSerialization.jsonObject(with: Data(frame.dropFirst(16))) as? [String: Any],
              Self.bool(value["ok"]) == true, let result = value["result"] as? [String: Any],
              Self.uint(result["upload_id"]) == uploadID, Self.uint(result["size"]) == size,
              Self.uint(result["received"]) == size, result["sha256"] as? String == sha256,
              result["state"] as? String == "committing", result["error"] as? String == "none",
              Self.bool(result["slot_touched"]) == false else { throw NanoGate.Rejected() }
        withheldResponse = frame
        return false
    }
}
