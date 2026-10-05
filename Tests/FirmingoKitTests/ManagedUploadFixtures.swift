import CryptoKit
import Foundation
import Testing
@testable import FirmingoKit

/// Non-executable parser vectors and synthetic metadata for fake transports ONLY. Never use on hardware.
enum ManagedUploadFixtures {
    /// Fixed capsule digest independently recorded by the pinned firmware vector.
    static let capsuleDigest = "ef8bff817d9b80026f6eaeac33d1c40fac2f41b046865de967d3c0cf2539d52a"
    /// Synthetic exact resident association; none of these hashes identifies a real installed image.
    static func resident(deviceID: String = "a1b2c3d4e5f60718") throws -> ManagedResidentBinding {
        try ManagedResidentBinding(deviceID: deviceID, residentELFSHA256: String(repeating: "2", count: 64),
                                   firmwareImageSHA256: String(repeating: "3", count: 64), apiAddress: 0x1002154c)
    }
    /// Extracts the independent test capsule from the golden type-four frame without executing it.
    static func bytes() throws -> Data {
        Data(try ProtocolFixtures.frame("managed-upload/chunk").payload.dropFirst(8))
    }
    /// Provides a synthetic matching report using the vector's independent code/whole digests.
    static func report(bytes: Data? = nil) throws -> [String: Any] {
        let bytes = try bytes ?? self.bytes()
        let data = Array(bytes)
        return ["board": "nano_rp2040_connect", "image_format": "nano-managed-v1", "target_id": 1,
                "resident_elf_sha256": String(repeating: "2", count: 64), "api_address": "0x1002154c",
                "setup_address": String(format: "0x%08x", littleEndian(data, offset: 24)),
                "loop_address": String(format: "0x%08x", littleEndian(data, offset: 28)),
                "code_bytes": bytes.count - 256, "capsule_bytes": bytes.count,
                "code_sha256": data[32..<64].map { String(format: "%02x", $0) }.joined(),
                "capsule_sha256": bytes.count == 264 ? capsuleDigest : digest(bytes),
                "source_sha256": ["fixtures/parser-only.bin": String(repeating: "1", count: 64)],
                "compiler": "parser-fixture-not-executable"]
    }
    /// Encodes one bounded fake build report; it has no executable compiler or source dependency.
    static func reportJSON(_ report: [String: Any]? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: report ?? self.report(), options: [.sortedKeys])
    }
    /// Validates the parser-only artifact for deterministic fake-peer tests.
    static func capsule() throws -> ManagedCapsule {
        try ManagedCapsule(bytes: bytes(), reportJSON: reportJSON(), resident: resident())
    }
    /// Returns a golden response payload for re-correlation by the fake peer.
    static func response(_ name: String) throws -> Data {
        try ProtocolFixtures.frame("managed-upload/\(name)-response").payload
    }
    /// Re-correlates the fixture's hello ID nine to the SDK's initial hello ID one.
    static func hello(mutate: ((inout [String: Any]) -> Void)? = nil) throws -> Data {
        let payload = try response("hello")
        guard let mutate else { return try FMGOFrame(kind: .response, requestID: 1, payload: payload).encoded() }
        var envelope = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        var result = try #require(envelope["result"] as? [String: Any])
        mutate(&result)
        envelope["result"] = result
        return try FMGOFrame(kind: .response, requestID: 1,
                             payload: JSONSerialization.data(withJSONObject: envelope)).encoded()
    }
    /// Connects to a scripted peer with injectable deadlines and no live networking.
    static func connect(_ peer: SessionTestTransport,
                        sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in try await TestLatch().wait() }) async throws -> FirmingoSession {
        try await FirmingoSession.connect(transport: peer, expectedBoard: .nanoRP2040Connect,
                                           expectedBackend: .application,
                                           deadline: { try await TestLatch().wait() }, deadlineSleep: sleep)
    }
    /// Default independent accepted/chunk/verified envelopes for the 264-byte parser vector.
    static func stagingResponses() throws -> [String: [Data]] {
        ["flash.begin": [try response("accepted")], "upload.chunk": [try response("chunk")],
         "flash.finish": [try response("verified")]]
    }
    /// Makes a verified test record without commit; the session remains owned by the test caller.
    static func staged() async throws -> (FirmingoSession, SessionTestTransport, ManagedUploadRecord) {
        let peer = SessionTestTransport(hello: try hello(), responses: try stagingResponses())
        let session = try await connect(peer)
        return (session, peer, try await session.stageManagedUpload(capsule()))
    }
    /// Mutates a firmware result payload for mismatched/malformed schema tests.
    static func mutatedResponse(_ name: String, change: (inout [String: Any]) -> Void) throws -> Data {
        var envelope = try #require(JSONSerialization.jsonObject(with: response(name)) as? [String: Any])
        var result = try #require(envelope["result"] as? [String: Any])
        change(&result)
        envelope["result"] = result
        return try JSONSerialization.data(withJSONObject: envelope)
    }
    /// Makes a longer non-executable vector for independent transfer-boundary assertions.
    static func boundaryBytes(size: Int) throws -> Data {
        var data = Array(try bytes().prefix(256)) + [UInt8](repeating: 0xaa, count: size - 256)
        let count = UInt32(size - 256)
        for i in 0..<4 { data[20 + i] = UInt8(truncatingIfNeeded: count >> (i * 8)) }
        // The minimum parser-only image gives both Thumb entries the sole byte's address.
        if size == 257 { data.replaceSubrange(28..<32, with: [1, 1, 0x20, 0x10]) }
        let hash = Array(SHA256.hash(data: Data(data.dropFirst(256))))
        data.replaceSubrange(32..<64, with: hash)
        return Data(data)
    }
    /// Builds a synthetic boundary response; golden vectors remain the primary expectation elsewhere.
    static func boundaryResponse(bytes: Data, received: Int, state: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["ok": true, "result": [
            "upload_id": 1, "state": state, "size": bytes.count, "received": received,
            "sha256": digest(bytes), "slot_touched": false, "error": "none"]])
    }
    /// Supplementary digest used only for synthesized boundary vectors.
    private static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    /// Decodes already bounded fixture header fields without unaligned memory access.
    private static func littleEndian(_ bytes: [UInt8], offset: Int) -> UInt32 {
        bytes[offset..<offset + 4].reversed().reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
