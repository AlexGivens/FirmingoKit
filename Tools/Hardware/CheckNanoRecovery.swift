import Foundation

/// Independent framing and intent checks; fixture responses never contact a device or establish a hardware pass.
@main struct CheckNanoRecovery {
    /// Requires a rejection rather than accepting malformed wire evidence or unsafe host retirement.
    static func rejected(_ action: () throws -> Void) throws {
        do { try action() } catch { return }
        throw NSError(domain: "NanoRecoveryChecks", code: 1)
    }
    /// Builds fixed big-endian frame vectors independently of the proxy's production parser.
    static func frame(_ payload: String, kind: UInt8, id: UInt32 = 101) -> Data {
        let bytes = Data(payload.utf8)
        var result = Data([70,77,71,79,1,kind,0,0])
        for word in [id, UInt32(bytes.count)] {
            for shift in [24,16,8,0] { result.append(UInt8(truncatingIfNeeded: word >> shift)) }
        }
        result.append(bytes); return result
    }
    /// Checks exact correlation, untouched transparent frames, one withheld reply, strict scalars and conservative intent.
    static func main() throws {
        let digest = String(repeating: "0", count: 64)
        let request = frame(#"{"op":"flash.commit","target_id":2,"upload_id":1}"#, kind: 1)
        let json = #"{"ok":true,"result":{"upload_id":1,"state":"committing","size":548,"received":548,"sha256":"DIGEST","slot_touched":false,"error":"none"}}"#.replacingOccurrences(of: "DIGEST", with: digest)
        let response = frame(json, kind: 2)
        for length in 0..<16 { try rejected { _ = try NanoReplyLossGate.header(Data(request.prefix(length)), complete: false) } }
        let header = try NanoReplyLossGate.header(Data(request.prefix(16)), complete: false)
        guard header.id == 101, header.kind == 1, header.size == request.count - 16 else { throw NSError(domain: "NanoRecoveryChecks", code: 2) }
        for index in [0,1,2,3,4,6,7,12] {
            var bad = request; bad[index] ^= 1
            try rejected { _ = try NanoReplyLossGate.header(bad) }
        }
        try rejected { _ = try NanoReplyLossGate.header(request + Data([0])) }
        var gate = NanoReplyLossGate(uploadID: 1, size: 548, sha256: digest)
        guard try gate.shouldForward(response), gate.withheldResponse == nil else { throw NSError(domain: "NanoRecoveryChecks", code: 3) }
        for body in [#"{"op":"flash.commit","target_id":1,"upload_id":1}"#,
                     #"{"op":"flash.commit","target_id":2,"upload_id":2}"#,
                     #"{"op":"flash.commit","target_id":2,"upload_id":true}"#,
                     #"{"op":"flash.commit","target_id":2,"upload_id":"1"}"#,
                     #"{"op":"flash.status","target_id":2,"upload_id":1}"#,
                     #"{"op":"flash.commit","target_id":2,"upload_id":1,"extra":0}"#] {
            try rejected { try gate.observeCommit(frame(body, kind: 1)) }
        }
        try gate.observeCommit(request)
        try rejected { try gate.observeCommit(request) }
        guard try gate.shouldForward(frame(json, kind: 2, id: 100)) else { throw NSError(domain: "NanoRecoveryChecks", code: 4) }
        for (before, after) in [("548", "549"), ("committing", "boot_confirmed"), ("\"ok\":true", "\"ok\":1"),
                                ("\"slot_touched\":false", "\"slot_touched\":0"), ("\"upload_id\":1", "\"upload_id\":true"),
                                ("\"upload_id\":1", "\"upload_id\":2"), (digest, String(repeating: "1", count: 64))] {
            try rejected { _ = try gate.shouldForward(frame(json.replacingOccurrences(of: before, with: after), kind: 2)) }
        }
        guard try !gate.shouldForward(response), gate.withheldResponse == response else { throw NSError(domain: "NanoRecoveryChecks", code: 5) }
        try rejected { _ = try gate.shouldForward(response) }
        try NanoRecoveryIntent.ramOnly.requirePrecommitRetirement(bootChanged: true)
        try rejected { try NanoRecoveryIntent.ramOnly.requirePrecommitRetirement(bootChanged: false) }
        for changed in [false, true] { try rejected { try NanoRecoveryIntent.commitIntent.requirePrecommitRetirement(bootChanged: changed) } }
        for intent in [NanoRecoveryIntent.ramOnly, .commitIntent] {
            let encoded = try JSONEncoder().encode(intent)
            guard try JSONDecoder().decode(NanoRecoveryIntent.self, from: encoded) == intent else { throw NSError(domain: "NanoRecoveryChecks", code: 6) }
        }
        try rejected { _ = try JSONDecoder().decode(NanoRecoveryIntent.self, from: Data(#""invented""#.utf8)) }
        print("Nano recovery checks passed: bounded framing, exact transaction correlation, strict scalars, single withheld reply, no commit replay and conservative reboot retirement; no sockets or hardware")
    }
}
