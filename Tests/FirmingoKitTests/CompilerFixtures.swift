import Foundation
import Testing
@testable import FirmingoKit

/// Offline non-executable ELF/capsule vectors and declared fake compiler metadata; never use on hardware.
enum CompilerFixtures {
    /// Stable document identity for deterministic preparation and receipt comparisons.
    static let documentID = UUID(uuid: (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15))
    /// Loads the independently hand-authored ELF layout from packaged test resources.
    static func elf() throws -> Data {
        let root = try #require(Bundle.module.resourceURL)
        let text = try String(contentsOf: root.appendingPathComponent("Fixtures/compiler/stateless.elf.hex"), encoding: .utf8)
        return Data(try text.split(whereSeparator: \.isWhitespace).map { try #require(UInt8($0, radix: 16)) })
    }
    /// Makes one immutable source selection without running a compiler or contacting firmware.
    static func request(source: String = "void setup() {}\nvoid loop() {}", revision: UInt64 = 7,
                        filename: String = "Sketch.ino", documentID: UUID = documentID,
                        resident: ManagedResidentBinding? = nil) throws -> ManagedSketchBuildRequest {
        try ManagedSketchBuildRequest(snapshot: SketchSourceSnapshot(documentID: documentID, revision: revision,
            filename: filename, source: source), board: .nanoRP2040Connect, profile: .nanoManagedV1,
            resident: resident ?? ManagedUploadFixtures.resident())
    }
    /// Declares fake hashes only for receipt syntax/identity tests; they do not identify verified assets.
    static func provenance(compiler: String = "parser fixture, no compiler execution",
                           recipe: String = "nano-test-v1", recipeHash: String = String(repeating: "4", count: 64),
                           toolchainHash: String = String(repeating: "5", count: 64)) throws -> ManagedELFProvenance {
        try ManagedELFProvenance(compiler: compiler, recipeIdentifier: recipe,
                                recipeSHA256: recipeHash, toolchainSHA256: toolchainHash)
    }
    /// Changes an independent ELF word for rejection tests, without using any SDK encoder.
    static func word(_ value: UInt32, at offset: Int, in data: inout Data) {
        for index in 0..<4 { data[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8)) }
    }
    /// Constructs a non-executable exact-limit layout by moving metadata beyond the larger .text.
    static func boundaryELF(codeBytes: Int) throws -> Data {
        let original = try elf()
        let metadataOffset = (256 + codeBytes + 15) / 16 * 16
        let tableOffset = metadataOffset + 240
        var data = Data(repeating: 0, count: tableOffset + 200)
        data.replaceSubrange(0..<84, with: original.prefix(84))
        data.replaceSubrange(256..<(256 + codeBytes), with: [UInt8](repeating: 0xaa, count: codeBytes))
        data.replaceSubrange(metadataOffset..<(metadataOffset + 145), with: original[272..<417])
        data.replaceSubrange(tableOffset..<(tableOffset + 200), with: original[512..<712])
        word(UInt32(tableOffset), at: 32, in: &data)
        word(UInt32(256 + codeBytes), at: 68, in: &data)
        word(UInt32(256 + codeBytes), at: 72, in: &data)
        word(UInt32(codeBytes), at: tableOffset + 60, in: &data)
        word(UInt32(metadataOffset), at: tableOffset + 96, in: &data)
        word(UInt32(metadataOffset + 48), at: tableOffset + 136, in: &data)
        word(UInt32(metadataOffset + 112), at: tableOffset + 176, in: &data)
        return data
    }
}
