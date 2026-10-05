import Foundation
import Testing
@testable import FirmingoKit

/// Validates strict linked-output rejection and independent firmware capsule bytes; no code is executed.
struct ManagedELFConverterTests {
    /// LLD readonly merged-string metadata preserves code bytes; writable/unknown flag variants still fail.
    @Test func readonlyMergedStrings() throws {
        var elf = try CompilerFixtures.elf()
        CompilerFixtures.word(0x36, at: 560, in: &elf)
        #expect(try ManagedELFImage(elf).code == Data(elf[256..<264]))
        for flags: UInt32 in [7, 0x37, 0x16, 0x26, 0x46, 0x136] {
            CompilerFixtures.word(flags, at: 560, in: &elf)
            #expect(throws: SketchBuildError.self) { try ManagedELFImage(elf) }
        }
    }
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
            #expect(throws: SketchBuildError.self) { try ManagedELFImage(CompilerFixtures.boundaryELF(codeBytes: size)) }
        }
        var minimal = try CompilerFixtures.boundaryELF(codeBytes: 4)
        // Both wrappers may alias the sole four-byte function; the capsule contract permits that.
        CompilerFixtures.word(0x10200101, at: 308, in: &minimal)
        let result = try await ManagedELFConverter.convert(minimal, prepared: prepared, provenance: provenance)
        #expect(result.capsule.bytes.count == 260)
    }
    /// Whole-file and every truncated-table boundary fail safely without allocating from declared lengths.
    @Test func truncationAndFileBounds() throws {
        let elf = try CompilerFixtures.elf()
        for length in 0..<elf.count { #expect(throws: SketchBuildError.self) { try ManagedELFImage(elf.prefix(length)) } }
        #expect(throws: SketchBuildError.self) { try ManagedELFImage(Data(repeating: 0, count: 2 * 1024 * 1024 + 1)) }
        var prefixed = Data([0xde, 0xad]); prefixed.append(elf)
        #expect(try ManagedELFImage(prefixed.dropFirst(2)).code == Data(elf[256..<264]))
    }
    /// Header identity, address/range mapping, symbol attributes and forbidden section types are terminal.
    @Test func malformedELFMatrix() throws {
        let original = try CompilerFixtures.elf()
        let words: [(Int, UInt32)] = [
            (0, 0), (16, 0x00280001), (20, 0), (24, 0x10200105), (28, 0xfffffff0), (32, 0xfffffff0),
            (36, 0x05000400), (40, 0), (44, 0x00280000), (48, 0x00040000), (48, 0x00040081),
            (52, 2), (56, 4), (60, 0x10000100), (64, 0x10200004), (68, 263), (72, 265), (76, 7), (80, 3),
            (512, 1), (552, 9999), (556, 8), (560, 7), (564, 0x10000100), (568, 52), (572, 3844),
            (592, 9999), (596, 9), (600, 2), (608, 256), (616, 9999), (624, 3), (628, 8),
            (648, 0xfffffff0), (652, 0xfffffff0), (688, 256),
            (272, 1), (288, 9999), (292, 0x10200100), (296, 9), (300, 0x00010002),
            (304, 1), (308, 0x10200109), (312, 8), (316, 0x00020012)
        ]
        for (offset, value) in words {
            var data = original
            CompilerFixtures.word(value, at: offset, in: &data)
            #expect(throws: SketchBuildError.self, "word \(offset) = \(value)") { try ManagedELFImage(data) }
        }
        for (offset, value) in [(4, UInt8(2)), (5, 2), (7, 1), (302, 0), (300, 0x22), (301, 2), (320, 1), (416, 1)] {
            var data = original; data[offset] = value
            #expect(throws: SketchBuildError.self, "byte \(offset) = \(value)") { try ManagedELFImage(data) }
        }
        // A valid static symbol name with section UNDEF or COMMON remains forbidden, even for nonwrappers.
        for section: UInt32 in [0, 0xfff2, 0xffff] {
            var data = original
            CompilerFixtures.word(section << 16 | 0x12, at: 300, in: &data)
            #expect(throws: SketchBuildError.self) { try ManagedELFImage(data) }
        }
        for type: UInt32 in [4, 6, 9, 11, 14, 15, 16] {
            var data = original; CompilerFixtures.word(type, at: 636, in: &data)
            #expect(throws: SketchBuildError.self) { try ManagedELFImage(data) }
        }
    }
    /// A full-firmware/UF2 input cannot be repackaged as managed code by adding an FMS header.
    @Test func refusesConventionalArtifacts() throws {
        #expect(throws: SketchBuildError.self) { try ManagedELFImage(Data("UF2\n".utf8) + Data(repeating: 0, count: 508)) }
        var data = try CompilerFixtures.elf()
        CompilerFixtures.word(0x10000100, at: 564, in: &data)
        #expect(throws: SketchBuildError.self) { try ManagedELFImage(data) }
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
