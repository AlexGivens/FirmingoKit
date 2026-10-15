import Foundation
import Testing
@testable import FirmingoKit

/// Independent firmware FMS2 vectors and fake-peer deployment checks; no fixture is deployed to hardware.
struct ManagedStatefulTests {
    /// Reads immutable SDK-local metadata without consulting another checkout or a connected device.
    static func file(_ name: String) throws -> Data {
        let root = try #require(Bundle.module.resourceURL)
        return try Data(contentsOf: root.appendingPathComponent("Fixtures/compiler-stateful/" + name))
    }
    /// Synthetic RAM/API association from the firmware parser fixture; it identifies no installed resident.
    static func resident() throws -> ManagedResidentBinding {
        try ManagedResidentBinding(deviceID: "a1b2c3d4e5f60718", residentELFSHA256: String(repeating: "2", count: 64),
            firmwareImageSHA256: String(repeating: "3", count: 64), apiAddress: 0x10000100,
            state: ManagedResidentState(address: 0x20030000, capacityBytes: 32))
    }
    /// Extracts the non-executable capsule from a firmware-owned type-four golden frame.
    static func capsule() throws -> ManagedCapsule {
        try ManagedCapsule(bytes: Data(ProtocolFixtures.frame("managed-upload-v2/chunk").payload.dropFirst(8)),
            reportJSON: file("parser-report.json"), resident: resident())
    }
    /// Re-correlates only hello; every other response is re-correlated by the fake transport.
    static func hello() throws -> Data {
        try FMGOFrame(kind: .response, requestID: 1, payload: response("hello")).encoded()
    }
    /// Returns firmware-owned transaction response bytes, without SDK encoding of their JSON schema.
    static func response(_ name: String) throws -> Data {
        try ProtocolFixtures.frame("managed-upload-v2/\(name)-response").payload
    }
    /// Supplies the accepted/chunk/verified sequence for one target-two stage, without implicit commit.
    static func responses() throws -> [String: [Data]] {
        ["flash.begin": [try response("accepted")], "upload.chunk": [try response("chunk")], "flash.finish": [try response("verified")]]
    }
    /// Exact golden vectors cover both FMS2 digests, state binding and target-two begin/chunk/finish/commit bytes.
    @Test func goldenStagingAndSingleCommit() async throws {
        let capsule = try Self.capsule()
        #expect(capsule.sha256 == "1c955e832d351a9b91a3bd5e5e4463a2f6732e4e87cd1de0d783c769f01ae867")
        var replies = try Self.responses(); replies["flash.commit"] = [try Self.response("committing")]
        let peer = SessionTestTransport(hello: try Self.hello(), writeLimit: 3, responses: replies)
        let session = try await ManagedUploadFixtures.connect(peer)
        let record = try await session.stageManagedUpload(capsule)
        #expect(record.targetID == 2); #expect(record.format == "nano-managed-v2")
        #expect(try JSONDecoder().decode(ManagedUploadRecord.self, from: JSONEncoder().encode(record)) == record)
        #expect(try await session.commitManagedUpload(record).state == .committing)
        await #expect(throws: FirmingoError.self) { try await session.commitManagedUpload(record) }
        let frames = await peer.sentFrames
        for (index, name) in [(1, "begin-request"), (2, "chunk"), (3, "finish-request"), (4, "commit-request")] {
            #expect(try FMGOFrame(kind: frames[index].kind, requestID: 9, payload: frames[index].payload).encoded() == ProtocolFixtures.bytes("managed-upload-v2/\(name)"))
        }
    }
    /// A lost target-two commit reply cannot cause replay; a fresh connection can only read the saved record.
    @Test func lostCommitAndFreshReconciliation() async throws {
        let peer = SessionTestTransport(hello: try Self.hello(), responses: try Self.responses())
        let session = try await ManagedUploadFixtures.connect(peer)
        let record = try await session.stageManagedUpload(Self.capsule())
        let commit = Task { try await session.commitManagedUpload(record) }
        await peer.waitForSent(5); await peer.close()
        do { _ = try await commit.value; Issue.record("Lost reply must remain uncertain") }
        catch ManagedUploadError.uncertainCommit(let saved, _) { #expect(saved == record) }
        let freshPeer = SessionTestTransport(hello: try Self.hello(), responses: ["flash.status": [try Self.response("boot-confirmed")]])
        let fresh = try await ManagedUploadFixtures.connect(freshPeer)
        guard case .snapshot(let snapshot) = try await fresh.reconcileManagedUpload(record) else { Issue.record("Expected retained transaction"); return }
        #expect(snapshot.state == .bootConfirmed)
        #expect(await freshPeer.sentFrames.count == 2)
        let frame = try #require(await freshPeer.sentFrames.last)
        #expect(try FMGOFrame(kind: .request, requestID: 9, payload: frame.payload).encoded() == ProtocolFixtures.bytes("managed-upload-v2/status-request"))
        await fresh.disconnect()
        let oldPeer = SessionTestTransport(hello: try ManagedUploadFixtures.hello())
        let oldSession = try await ManagedUploadFixtures.connect(oldPeer)
        guard case .unknown(.targetUnavailable) = try await oldSession.reconcileManagedUpload(record) else {
            Issue.record("An ABI-one hello cannot reconcile target two"); return
        }
        #expect(await oldPeer.sentFrames.count == 1)
        await oldSession.disconnect()
        let encoded = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ManagedUploadRecord.self, from: Data(encoded.replacingOccurrences(of: "nano-managed-v2", with: "nano-managed-v1").utf8))
        }
    }
    /// ABI-one advertisement cannot stage FMS2 or reconcile a target-two record, even on the same device/boot.
    @Test func oldTargetCannotReceiveStatefulCapsule() async throws {
        let oldPeer = SessionTestTransport(hello: try ManagedUploadFixtures.hello())
        let session = try await ManagedUploadFixtures.connect(oldPeer)
        await #expect(throws: ManagedUploadError.self) { try await session.stageManagedUpload(Self.capsule()) }
        #expect(await oldPeer.sentFrames.count == 1)
        await session.disconnect()
    }
    /// Invalid RAM bounds and schema/ABI/contract mixtures fail before build, association or transport creation.
    @Test func rejectsInvalidStateMetadata() throws {
        for (address, capacity): (UInt32, UInt32) in [(0xffffffff, 4), (0x20000001, 4), (0x20000000, 0), (0x20000000, 4097), (0x20041ffc, 8)] {
            #expect(throws: ManagedUploadError.self) { try ManagedResidentState(address: address, capacityBytes: capacity) }
        }
        let original = try #require(JSONSerialization.jsonObject(with: Self.file("descriptor.json")) as? [String: Any])
        for (field, wrong): (String, Any) in [("schema", 1), ("residentABI", 1), ("targetID", 1), ("compilerContractSHA256", String(repeating: "0", count: 64))] {
            var changed = original; changed[field] = wrong
            let data = try JSONSerialization.data(withJSONObject: changed)
            #expect(throws: ManagedCatalogueError.self) { try ManagedFirmwareBuildDescriptor(recordJSON: data) }
        }
    }
    /// Each constrained FMS2 region rejects mutation before a device or transport is needed.
    @Test(arguments: [0, 4, 6, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60, 64, 96, 128, 255, 256, 271])
    func rejectsCorruptStatefulBytes(offset: Int) throws {
        var bytes = try Self.capsule().bytes; bytes[offset] ^= 1
        #expect(throws: ManagedUploadError.self) { try ManagedCapsule(bytes: bytes, reportJSON: Self.file("parser-report.json"), resident: Self.resident()) }
    }
    /// The real WASM fixture validates independently and the SDK computes the same closed descriptor identity.
    @Test func realCompilerFixtureAndDescriptor() throws {
        let descriptor = try ManagedFirmwareBuildDescriptor(recordJSON: Self.file("descriptor.json"))
        let receipt = try WireJSON.parse(Self.file("receipt.json"))
        #expect(descriptor.id == (try receipt.required("firmwareBuildID").string()))
        let association = try ManagedDeviceAssociation(deviceID: "0102030405060708", firmwareBuildID: descriptor.id, evidence: .hostConfirmedExistingFirmware)
        let binding = try ManagedResidentBinding(association: association, firmwareBuild: descriptor)
        #expect(binding.state?.address == 0x2000893c)
        let text = String(decoding: try Self.file("counter.fms.hex"), as: UTF8.self)
        let bytes = Data(try text.split(whereSeparator: \.isWhitespace).map { try #require(UInt8($0, radix: 16)) })
        let capsule = try ManagedCapsule(bytes: bytes, reportJSON: Self.file("report.json"), resident: binding)
        #expect(capsule.sha256 == "e349a77d85958db1c4eba4f5c10f27e23dc9dd2ce03eb675c108d07bbfd93abb")
    }
}
