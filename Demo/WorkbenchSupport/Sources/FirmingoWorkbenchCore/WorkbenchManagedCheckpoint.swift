import Foundation
import CryptoKit
import FirmingoKit

/// Durable host facts, not a restored session or executable continuation.
public struct WorkbenchManagedCheckpoint: Codable, Sendable {
    /// Rejects silent format migrations.
    public var schema = 1
    /// Original stage request and its reviewed selections.
    public let request: WorkbenchRequest
    /// False until synchronized immediately before the SDK stage call.
    public var stageIntent = false
    /// Saved SDK transaction, present only after actual verified staging.
    public var record: ManagedUploadRecord?
    /// Persisted before a commit can be called; never reset after failure/restart.
    public var commitIntent = false
    /// Actual latest matching transaction snapshot.
    public var snapshot: Snapshot?
    /// Conservative SDK reason when saved transaction evidence is unavailable.
    public var unknownReason: String?
    /// Only validated disposal/terminal reconciliation releases the global pending guard.
    public var released = false
    /// Starts before compilation or device I/O, with no issued record or commit authority.
    public init(request: WorkbenchRequest) { self.request = request }
    /// Stable record digest binds later actions to the exact SDK transaction, including resident evidence.
    public var recordSHA256: String? {
        get throws {
            guard let record else { return Self.digest(Data("null".utf8)) }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return Self.digest(try encoder.encode(record))
        }
    }
    /// Revalidates stored shape and cross-field identities on every load/save.
    public func validate() throws {
        try request.validate()
        guard schema == 1, request.scenarioID == "managed.stage", !commitIntent || record != nil,
              !released || !stageIntent || snapshot?.state == "boot_confirmed" || snapshot?.state == "aborted" || (!commitIntent && unknownReason == "bootChanged") || (!commitIntent && record == nil && unknownReason == "stageFailedNoCommit") else {
            throw WorkbenchFailure("Invalid managed checkpoint intent or release.")
        }
        if let record {
            guard stageIntent, record.deviceID == request.device?.deviceID, record.bootID == request.device?.bootID,
                  record.residentELFSHA256 == WorkbenchManagedSelection.residentELFSHA256, record.targetID == 2, record.format == "nano-managed-v2",
                  record.size == (request.managed?.sketch == "state-a" ? 544 : 548),
                  record.firmwareImageSHA256 == WorkbenchManagedSelection.imageSHA256,
                  record.sha256 == Self.capsuleSHA256(request.managed?.sketch ?? "") else {
                throw WorkbenchFailure("Saved transaction differs from the original selected artifact/device/boot.")
            }
        }
        if let snapshot {
            guard let record, snapshot.uploadID == record.uploadID, snapshot.size == record.size, snapshot.sha256 == record.sha256,
                  snapshot.received <= snapshot.size, Self.states.contains(snapshot.state) else { throw WorkbenchFailure("Foreign transaction snapshot.") }
            try snapshot.validate()
        }
        guard snapshot == nil || unknownReason == nil,
              unknownReason == nil || ["bootChanged", "deviceChanged", "targetUnavailable", "recordMismatch", "stageFailedNoCommit", "recordNotIssued", "recordUnavailable:wrong_target", "recordUnavailable:unsupported", "recordUnavailable:invalid_state"].contains(unknownReason ?? "") else { throw WorkbenchFailure("Ambiguous managed outcome.") }
    }
    /// Fixed independently qualified capsule vectors; no deployable bytes are manufactured here.
    public static func capsuleSHA256(_ sketch: String) -> String {
        sketch == "state-a" ? "537ce260fc33d4b23b2f8829aee6a9b12653236db6baad4c317040dbf087fd89" : "505c723804addf218e9018375c1f63fd036c2e0bf19d0173ae189b04418aa9b0"
    }
    /// Exact firmware state vocabulary; command acceptance is separate from startup.
    static let states = ["accepted", "verified", "committing", "installed", "boot_confirmed", "aborted", "failed"]
    /// SHA-256 over exact bytes; it establishes identity, not installed-image trust.
    static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    /// Codable projection of an actual SDK-validated snapshot.
    public struct Snapshot: Codable, Sendable {
        /// Transaction identity, meaningful only with the saved device/boot record.
        public let uploadID: UInt32
        /// Firmware state, not the FMGO envelope's success flag.
        public let state: String
        /// Expected complete capsule length.
        public let size: UInt32
        /// Actual accepted byte count.
        public let received: UInt32
        /// Exact complete capsule digest.
        public let sha256: String
        /// Conservative firmware indication that an erase was attempted.
        public let slotTouched: Bool
        /// Firmware machine error code.
        public let errorCode: String
        /// Copies actual SDK fields without inferring successful execution.
        public init(_ value: ManagedUploadSnapshot) {
            uploadID = value.uploadID; state = value.state.rawValue; size = value.size; received = value.received
            sha256 = value.sha256; slotTouched = value.slotTouched; errorCode = value.errorCode
        }
        /// Independent saved-evidence checks preserve the firmware's state/slot/error distinctions.
        func validate() throws {
            guard uploadID > 0, (257...4096).contains(size), received <= size,
                  WorkbenchRequest.isDigest(sha256), (1...32).contains(errorCode.utf8.count), errorCode.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }) else { throw WorkbenchFailure("Invalid saved snapshot.") }
            switch state {
            case "accepted": guard !slotTouched, errorCode == "none" else { throw WorkbenchFailure("Invalid accepted state.") }
            case "verified": guard !slotTouched, received == size, errorCode == "none" else { throw WorkbenchFailure("Invalid verified state.") }
            case "committing": guard received == size, errorCode == "none" else { throw WorkbenchFailure("Invalid committing state.") }
            case "installed", "boot_confirmed": guard slotTouched, received == size, errorCode == "none" else { throw WorkbenchFailure("Invalid installed/startup state.") }
            case "aborted": guard !slotTouched else { throw WorkbenchFailure("Aborted snapshot touched flash.") }
            case "failed": guard errorCode != "none" else { throw WorkbenchFailure("Failed snapshot lacks its error.") }
            default: throw WorkbenchFailure("Unsupported saved transaction state.")
            }
        }
    }
}
