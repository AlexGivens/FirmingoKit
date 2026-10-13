import Foundation
import Testing
@testable import FirmingoKit

/// Validates strict linked-output rejection and independent firmware capsule bytes; no code is executed.
struct ManagedELFConverterTests {
    /// The independent ELF produces the firmware's complete golden capsule, excluding mapped ELF headers.
    @Test func goldenCapsuleAndReceipt() async throws {
        let prepared = try await ManagedSketchPreprocessor.prepare(CompilerFixtures.request())
        let provenance = try CompilerFixtures.provenance()
        let elf = try CompilerFixtures.elf()
        let first = try await ManagedELFConverter.convert(elf, prepared: prepared, provenance: provenance)
        let second = try await ManagedELFConverter.convert(elf, prepared: prepared, provenance: provenance)
        #expect(first.capsule.bytes == (try ManagedUploadFixtures.bytes()))
        #expect(first.capsule.sha256 == ManagedUploadFixtures.capsuleDigest)
        #expect(first.capsule.bytes.count == 264)
        #expect(first.filename == "Sketch.fms")
        #expect(first.receipt == second.receipt)
        #expect(first.reportJSON == second.reportJSON)
        #expect(first.receipt.documentID == CompilerFixtures.documentID)
        // Independently computed with Python compact sorted JSON; legacy receipt meaning is unchanged.
        #expect(first.receipt.buildInputSHA256 == "cf9d3b07f04a8566ca5c63481225681df707e752bbf8eac06bd4ededc65d668a")
        #expect(first.compilerReceiptJSON == nil)
        #expect(first.receipt.sourceRevision == 7)
        #expect(first.receipt.sourceSHA256 == prepared.sourceSHA256)
        #expect(first.receipt.translationUnitSHA256 == prepared.translationUnitSHA256)
        #expect(first.receipt.linkedELFSHA256 == NanoManagedContract.digest(elf))
        #expect(first.receipt.provenance == provenance)
        #expect(first.capsule.sourceSHA256["recipe/manifest.json"] == provenance.recipeSHA256)
        #expect(first.capsule.sourceSHA256["toolchain/manifest.json"] == provenance.toolchainSHA256)
        let report = try #require(JSONSerialization.jsonObject(with: first.reportJSON) as? [String: Any])
        #expect(report["status"] as? String == "structurally validated packaging; compiler/source association is host supplied; no hardware proof")
        #expect(first.capsule.compiler == provenance.compiler)
    }
    /// Every source/revision/target association affects input identity even when the parser code is unchanged.
    @Test func completeInputIdentity() async throws {
        let resident = try ManagedUploadFixtures.resident()
        let requests = [
            try CompilerFixtures.request(), try CompilerFixtures.request(revision: 8),
            try CompilerFixtures.request(source: "// changed\nvoid setup() {} void loop() {}"),
            try CompilerFixtures.request(filename: "Other.ino"), try CompilerFixtures.request(documentID: UUID()),
            try CompilerFixtures.request(resident: ManagedUploadFixtures.resident(deviceID: "0102030405060708")),
            try CompilerFixtures.request(resident: ManagedResidentBinding(deviceID: resident.deviceID,
                residentELFSHA256: String(repeating: "6", count: 64), firmwareImageSHA256: resident.firmwareImageSHA256, apiAddress: resident.apiAddress)),
            try CompilerFixtures.request(resident: ManagedResidentBinding(deviceID: resident.deviceID,
                residentELFSHA256: resident.residentELFSHA256, firmwareImageSHA256: String(repeating: "7", count: 64), apiAddress: resident.apiAddress)),
            try CompilerFixtures.request(resident: ManagedResidentBinding(deviceID: resident.deviceID,
                residentELFSHA256: resident.residentELFSHA256, firmwareImageSHA256: resident.firmwareImageSHA256, apiAddress: 0x10020000))
        ]
        var identities: Set<String> = []
        let elf = try CompilerFixtures.elf()
        for request in requests {
            let prepared = try await ManagedSketchPreprocessor.prepare(request)
            let artifact = try await ManagedELFConverter.convert(elf, prepared: prepared, provenance: CompilerFixtures.provenance())
            #expect(identities.insert(artifact.receipt.buildInputSHA256).inserted)
            #expect(artifact.capsule.resident == request.resident)
        }
        let prepared = try await ManagedSketchPreprocessor.prepare(requests[0])
        for provenance in [try CompilerFixtures.provenance(compiler: "different compiler"),
                           try CompilerFixtures.provenance(recipe: "different-recipe"),
                           try CompilerFixtures.provenance(recipeHash: String(repeating: "8", count: 64)),
                           try CompilerFixtures.provenance(toolchainHash: String(repeating: "9", count: 64))] {
            let artifact = try await ManagedELFConverter.convert(elf, prepared: prepared, provenance: provenance)
            #expect(identities.insert(artifact.receipt.buildInputSHA256).inserted)
        }
    }
    /// Half-open limits allow exactly 4 KiB, reject extra/unaligned code, and accept the aligned minimum.
    @Test func exactCapsuleBounds() async throws {
        let prepared = try await ManagedSketchPreprocessor.prepare(CompilerFixtures.request())
        let provenance = try CompilerFixtures.provenance()
        for size in [8, 3840] {
            let result = try await ManagedELFConverter.convert(CompilerFixtures.boundaryELF(codeBytes: size), prepared: prepared, provenance: provenance)
            #expect(result.capsule.bytes.count == 256 + size)
        }
        for size in [0, 1, 7, 3844] {
            await #expect(throws: SketchBuildError.self) { try await ManagedELFConverter.convert(CompilerFixtures.boundaryELF(codeBytes: size), prepared: prepared, provenance: provenance) }
        }
        var minimal = try CompilerFixtures.boundaryELF(codeBytes: 4)
        // Both wrappers may alias the sole four-byte function; the capsule contract permits that.
        CompilerFixtures.word(0x10200101, at: 308, in: &minimal)
        let result = try await ManagedELFConverter.convert(minimal, prepared: prepared, provenance: provenance)
        #expect(result.capsule.bytes.count == 260)
    }
    /// Host-declared metadata is bounded and canonical; malformed digests cannot produce a valid receipt.
    @Test func provenanceValidation() throws {
        for compiler in ["", "compiler\0", String(repeating: "é", count: 129)] {
            #expect(throws: SketchBuildError.self) { try CompilerFixtures.provenance(compiler: compiler) }
        }
        for recipe in ["", "../recipe", "recipe\n", "recipe with spaces", String(repeating: "a", count: 97)] {
            #expect(throws: SketchBuildError.self) { try CompilerFixtures.provenance(recipe: recipe) }
        }
        for hash in ["", String(repeating: "A", count: 64), String(repeating: "g", count: 64), String(repeating: "a", count: 63)] {
            #expect(throws: SketchBuildError.self) { try CompilerFixtures.provenance(recipeHash: hash) }
            #expect(throws: SketchBuildError.self) { try CompilerFixtures.provenance(toolchainHash: hash) }
        }
    }
    /// Cancellation cannot return a packaged artifact after the host withdraws the operation.
    @Test func cancelledPackaging() async throws {
        let prepared = try await ManagedSketchPreprocessor.prepare(CompilerFixtures.request())
        let elf = try CompilerFixtures.elf(), provenance = try CompilerFixtures.provenance()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ManagedELFConverter.convert(elf, prepared: prepared, provenance: provenance)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
