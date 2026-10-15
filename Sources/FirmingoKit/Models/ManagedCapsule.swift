import CryptoKit
import Foundation

/// A locally validated experimental Nano FMS1/FMS2 capsule and matching independent build report.
/// Validation checks packaging, digests, entry ranges, and resident binding, not executable behavior
/// or publisher authenticity. Only trusted, independently qualified code belongs on a physical board.
public struct ManagedCapsule: Sendable {
    /// Complete capsule bytes, including the little-endian header and zero padding; never a UF2.
    public let bytes: Data
    /// Whole-capsule SHA-256 used by flash.begin and transaction reconciliation.
    public let sha256: String
    /// Exact host-supplied installed-resident association checked against the build report/header.
    public let resident: ManagedResidentBinding
    /// Source/dependency hashes retained from the build report; source authenticity is host-owned.
    public let sourceSHA256: [String: String]
    /// Reported compiler provenance, retained as text and never executed as a command.
    public let compiler: String
    /// Linked Thumb setup entry point, with its low bit set.
    public let setupAddress: UInt32
    /// Linked Thumb loop entry point, with its low bit set.
    public let loopAddress: UInt32
    /// Digest of linked code only, separate from the whole-capsule digest.
    public let codeSHA256: String

    /// Validates a 257–4096-byte capsule and bounded report against an explicit physical-device association.
    /// This checks structural packaging and declared firmware requirements, not installed bytes, executable
    /// behavior or publisher authenticity. It performs no connection, authorization or device write.
    /// Required report fields include board/format/target, resident/API binding, code/capsule lengths and
    /// hashes, entry points, source_sha256 and compiler. Unknown additive report fields are ignored here;
    /// callers retain the original report when additional provenance is needed.
    public init(bytes: Data, reportJSON: Data, resident: ManagedResidentBinding) throws {
        let payload = try ManagedCapsulePayload(bytes: bytes, reportJSON: reportJSON,
            apiAddress: resident.apiAddress, residentELFSHA256: resident.residentELFSHA256, state: resident.state)
        self.bytes = payload.bytes; sha256 = payload.sha256; self.resident = resident
        sourceSHA256 = payload.sourceSHA256; compiler = payload.compiler
        setupAddress = payload.setupAddress; loopAddress = payload.loopAddress; codeSHA256 = payload.codeSHA256
    }
}
