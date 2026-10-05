import CryptoKit
import Foundation

/// Shared bounded FMS1/report validation against exact firmware requirements, independent of physical devices.
/// Both offline packaging and legacy device-bound capsules use this gate; it does not prove executable behavior.
struct ManagedCapsulePayload: Sendable {
    /// Complete capsule bytes, including the little-endian header and zero padding; never a UF2.
    let bytes: Data
    /// Whole-capsule SHA-256 used by flash.begin and transaction reconciliation.
    let sha256: String
    /// Source/dependency hashes retained from the build report; source authenticity is host-owned.
    let sourceSHA256: [String: String]
    /// Reported compiler provenance, retained as text and never executed as a command.
    let compiler: String
    /// Linked Thumb setup entry point, with its low bit set.
    let setupAddress: UInt32
    /// Linked Thumb loop entry point, with its low bit set.
    let loopAddress: UInt32
    /// Digest of linked code only, separate from the whole-capsule digest.
    let codeSHA256: String

    /// Validates exact report/header requirements without inventing a device association.
    init(bytes: Data, reportJSON: Data, apiAddress: UInt32, residentELFSHA256: String) throws {
        guard (257...NanoManagedContract.maximumSize).contains(bytes.count) else {
            throw ManagedUploadError.invalidArtifact("FMS1 capsules must contain 257 through 4096 bytes")
        }
        do {
            let report = try WireJSON.parse(reportJSON)
            let data = Array(bytes)
            guard data.prefix(4).elementsEqual([0x46, 0x4d, 0x53, 0x31]),
                  Self.u16(data, at: 4) == 1, Self.u16(data, at: 6) == 64,
                  Self.u32(data, at: 8) == 0x4f4e414e,
                  Self.u32(data, at: 12) == apiAddress,
                  Self.u32(data, at: 16) == NanoManagedContract.codeAddress,
                  data[64..<256].allSatisfy({ $0 == 0 }) else {
                throw ManagedUploadError.invalidArtifact("Invalid FMS1 header, padding, or resident API binding")
            }
            let codeBytes = Self.u32(data, at: 20)
            let setup = Self.u32(data, at: 24)
            let loop = Self.u32(data, at: 28)
            guard codeBytes == bytes.count - 256, codeBytes > 0,
                  Self.validEntry(setup, bytes: codeBytes), Self.validEntry(loop, bytes: codeBytes) else {
                throw ManagedUploadError.invalidArtifact("Invalid FMS1 code length or Thumb entry point")
            }
            let code = Data(data.dropFirst(256))
            let rawDigest = Data(SHA256.hash(data: code))
            let codeHash = NanoManagedContract.digest(code)
            let wholeHash = NanoManagedContract.digest(bytes)
            guard rawDigest.elementsEqual(data[32..<64]),
                  try report.required("board").string() == FirmingoBoard.nanoRP2040Connect.rawValue,
                  try report.required("image_format").string() == NanoManagedContract.format,
                  try report.required("target_id").uint32() == NanoManagedContract.targetID,
                  try report.required("resident_elf_sha256").string() == residentELFSHA256,
                  try Self.address(report.required("api_address")) == apiAddress,
                  try Self.address(report.required("setup_address")) == setup,
                  try Self.address(report.required("loop_address")) == loop,
                  try report.required("code_bytes").uint32() == codeBytes,
                  try report.required("capsule_bytes").uint32() == bytes.count,
                  try report.required("code_sha256").string() == codeHash,
                  try report.required("capsule_sha256").string() == wholeHash else {
                throw ManagedUploadError.invalidArtifact("The capsule and build report do not match the selected resident")
            }
            let compiler = try report.required("compiler").string()
            let sources = try report.required("source_sha256").object()
            if let maximum = report["max_install_bytes"], try maximum.uint32() != NanoManagedContract.maximumSize {
                throw ManagedUploadError.invalidArtifact("The build report names an incompatible install limit")
            }
            guard !compiler.isEmpty, compiler.utf8.count <= 1024, !sources.isEmpty, sources.count <= 64 else {
                throw ManagedUploadError.invalidArtifact("Missing or excessive compiler/source provenance")
            }
            var hashes: [String: String] = [:]
            for (key, value) in sources {
                let path = String(decoding: key, as: UTF8.self)
                let hash = try value.string()
                let segments = path.split(separator: "/", omittingEmptySubsequences: false)
                guard !path.isEmpty, path.utf8.count <= 256, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
                      segments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                      hashes[path] == nil, NanoManagedContract.isHex(hash, bytes: 32) else {
                    throw ManagedUploadError.invalidArtifact("Invalid source hash or relative source path in build report")
                }
                hashes[path] = hash
            }
            self.bytes = bytes
            sha256 = wholeHash
            sourceSHA256 = hashes
            self.compiler = compiler
            setupAddress = setup
            loopAddress = loop
            codeSHA256 = codeHash
        } catch let error as ManagedUploadError {
            throw error
        } catch {
            throw ManagedUploadError.invalidArtifact("Malformed or incomplete managed build report")
        }
    }

    /// Decodes the builder's fixed-width lowercase hexadecimal address strings.
    private static func address(_ value: WireJSON.Value) throws -> UInt32 {
        let text = try value.string()
        guard text.hasPrefix("0x"), NanoManagedContract.isHex(String(text.dropFirst(2)), bytes: 4),
              let address = UInt32(text.dropFirst(2), radix: 16) else { throw WireJSON.invalid }
        return address
    }
    /// Reads a little-endian header u16 after the complete header's bounds check.
    private static func u16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }
    /// Reads a little-endian header u32 without unaligned loads.
    private static func u32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        bytes[offset..<offset + 4].reversed().reduce(0) { ($0 << 8) | UInt32($1) }
    }
    /// Rejects non-Thumb or out-of-range entry points without overflowing address arithmetic.
    private static func validEntry(_ address: UInt32, bytes: UInt32) -> Bool {
        let instruction = address & ~UInt32(1)
        return address & 1 == 1 && instruction >= NanoManagedContract.codeAddress &&
            instruction - NanoManagedContract.codeAddress < bytes
    }
}
