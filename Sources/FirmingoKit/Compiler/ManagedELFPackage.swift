import CryptoKit
import Foundation

/// Shared strict linked-ELF-to-FMS1 packaging, independent of a physical device association.
/// Public converters retain their own input identities; both use these exact format/report checks.
struct ManagedELFPackage {
    /// Shared validated capsule bytes, digests and entry points.
    let payload: ManagedCapsulePayload
    /// Deterministic bounded report matching the source, provenance and resident requirements.
    let reportJSON: Data
    /// Digest of complete linked ELF bytes, including nonloaded metadata.
    let linkedELFSHA256: String

    /// Packages only bounded stateless Nano ELF output against explicit source and firmware requirements.
    init(_ elfData: Data, snapshot: SketchSourceSnapshot, sourceSHA256: String,
         translationUnitSHA256: String, board: FirmingoBoard, profile: ManagedSketchBuildRequest.Profile,
         apiAddress: UInt32, residentELFSHA256: String, provenance: ManagedELFProvenance) throws {
        let image = try ManagedELFImage(elfData)
        var capsule = Data(repeating: 0, count: 256)
        capsule.replaceSubrange(0..<4, with: [0x46, 0x4d, 0x53, 0x31])
        Self.write(0x00400001, to: &capsule, at: 4)
        Self.write(0x4f4e414e, to: &capsule, at: 8)
        Self.write(apiAddress, to: &capsule, at: 12)
        Self.write(NanoManagedContract.codeAddress, to: &capsule, at: 16)
        Self.write(UInt32(image.code.count), to: &capsule, at: 20)
        Self.write(image.setupAddress, to: &capsule, at: 24)
        Self.write(image.loopAddress, to: &capsule, at: 28)
        capsule.replaceSubrange(32..<64, with: Array(SHA256.hash(data: image.code)))
        capsule.append(image.code)
        let capsuleHash = NanoManagedContract.digest(capsule)
        let sources = ["sketch/\(snapshot.filename)": sourceSHA256,
                       "generated/Sketch.cpp": translationUnitSHA256,
                       "recipe/manifest.json": provenance.recipeSHA256,
                       "toolchain/manifest.json": provenance.toolchainSHA256]
        let report: [String: Any] = [
            "status": "structurally validated packaging; compiler/source association is host supplied; no hardware proof",
            "board": board.rawValue, "image_format": profile.rawValue,
            "target_id": NanoManagedContract.targetID, "max_install_bytes": NanoManagedContract.maximumSize,
            "api_address": String(format: "0x%08x", apiAddress), "resident_elf_sha256": residentELFSHA256,
            "setup_address": String(format: "0x%08x", image.setupAddress), "loop_address": String(format: "0x%08x", image.loopAddress),
            "code_bytes": image.code.count, "code_sha256": NanoManagedContract.digest(image.code),
            "capsule_bytes": capsule.count, "capsule_sha256": capsuleHash,
            "source_sha256": sources, "compiler": provenance.compiler,
            "recipe_id": provenance.recipeIdentifier, "linked_elf_sha256": NanoManagedContract.digest(elfData)
        ]
        let reportJSON = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .withoutEscapingSlashes])
        payload = try ManagedCapsulePayload(bytes: capsule, reportJSON: reportJSON,
            apiAddress: apiAddress, residentELFSHA256: residentELFSHA256)
        self.reportJSON = reportJSON
        linkedELFSHA256 = NanoManagedContract.digest(elfData)
    }

    /// Writes fixed-width little-endian header fields into an SDK-owned complete buffer.
    private static func write(_ value: UInt32, to bytes: inout Data, at offset: Int) {
        for index in 0..<4 { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8)) }
    }
}
