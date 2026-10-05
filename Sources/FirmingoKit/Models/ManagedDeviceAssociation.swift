import Foundation

/// Persistable host assertion linking a real device ID to an immutable firmware-build descriptor.
/// This records reviewed evidence, not cryptographic device attestation or permission to upload/replay.
/// Reconnection still requires fresh identity/capability validation and current installed-image association.
public struct ManagedDeviceAssociation: Equatable, Encodable, Sendable {
    /// Local persistence version, separate from firmware and catalogue schemas.
    public let version: UInt32
    /// Actual device ID established during explicit setup; endpoints are not identities.
    public let deviceID: String
    /// Exact content identity, preserved across SDK updates without rebinding to another descriptor.
    public let firmwareBuildID: String
    /// Evidence reviewed by the host; constructing this value does not independently verify it.
    public let evidence: Evidence
    /// Referenced complete-firmware operation when installation context was reviewed; never a write/resume token.
    public let installationOperationID: UUID?

    /// Distinguishes reviewed installation context from explicit existing-device setup, with the same attestation limits.
    public enum Evidence: String, Encodable, Sendable {
        /// Host reviewed exact build metadata and its existing physical-device association.
        case hostConfirmedExistingFirmware
        /// Host reviewed a complete-firmware installation record and its verification limits.
        case reviewedInstallationRecord
    }

    /// Validates identities and evidence shape. Installation-record evidence requires its operation UUID;
    /// existing-device evidence prohibits one. The caller owns actual provenance/association verification.
    public init(deviceID: String, firmwareBuildID: String, evidence: Evidence, installationOperationID: UUID? = nil) throws {
        guard NanoManagedContract.isHex(deviceID, bytes: 8), NanoManagedContract.isHex(firmwareBuildID, bytes: 32),
              (evidence == .reviewedInstallationRecord) == (installationOperationID != nil) else {
            throw ManagedCatalogueError.invalidAssociation
        }
        version = 1; self.deviceID = deviceID; self.firmwareBuildID = firmwareBuildID
        self.evidence = evidence; self.installationOperationID = installationOperationID
    }

    /// Restores at most 2048 bytes using exact keys/types and duplicate-key rejection, without connecting.
    /// Optional installationOperationID is omitted for existing-device evidence and required for installation evidence.
    public init(recordJSON: Data) throws {
        do {
            let value = try WireJSON.parse(recordJSON, maximumBytes: 2048)
            let fields = Set(try value.object().keys)
            let required = Set(["version", "deviceID", "firmwareBuildID", "evidence"].map { Data($0.utf8) })
            guard fields == required || fields == required.union([Data("installationOperationID".utf8)]),
                  try value.required("version").uint32() == 1,
                  let evidence = Evidence(rawValue: try value.required("evidence").string()) else {
                throw ManagedCatalogueError.invalidAssociation
            }
            var operation: UUID?
            if let identifier = value["installationOperationID"] {
                let text = try identifier.string()
                guard let uuid = UUID(uuidString: text), uuid.uuidString == text else { throw ManagedCatalogueError.invalidAssociation }
                operation = uuid
            }
            try self.init(deviceID: value.required("deviceID").string(), firmwareBuildID: value.required("firmwareBuildID").string(),
                          evidence: evidence, installationOperationID: operation)
        } catch { throw ManagedCatalogueError.invalidAssociation }
    }

    /// Serializes bounded deterministic host context; use the strict recordJSON initializer to restore it.
    public func encodeRecord() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
