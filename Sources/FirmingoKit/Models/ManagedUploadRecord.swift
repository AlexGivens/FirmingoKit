import Foundation

/// Persistable identity of one Nano RAM transaction, issued after flash.begin.
/// Save the verified record before requesting commit. It permits read-only reconciliation after an
/// app restart; it does not allow resuming staging, replaying commit, or establish installation success.
public struct ManagedUploadRecord: Codable, Equatable, Sendable {
    /// Persisted schema version; unsupported versions cannot be restored silently.
    public let version: UInt32
    /// Self-reported physical device identity selected for this transaction.
    public let deviceID: String
    /// Boot identity needed because RAM records disappear and IDs can repeat after a reboot.
    public let bootID: String
    /// Exact board identifier, currently the experimental Nano contract only.
    public let boardID: String
    /// Advertised target identity, currently one.
    public let targetID: UInt32
    /// The independently reviewed FMS1 format name.
    public let format: String
    /// Nonzero firmware transaction ID scoped to device and boot.
    public let uploadID: UInt32
    /// Whole capsule byte count, including its header and padding.
    public let size: UInt32
    /// Whole capsule SHA-256, as lowercase hexadecimal.
    public let sha256: String
    /// Host-known exact resident ELF binding retained for inspection/provenance.
    public let residentELFSHA256: String
    /// Host-known complete firmware image digest; not attested by hello/status.
    public let firmwareImageSHA256: String

    /// Stable persistence fields; they are not the firmware's wire schema.
    private enum CodingKeys: String, CodingKey {
        case version, deviceID, bootID, boardID, targetID, format, uploadID, size, sha256
        case residentELFSHA256, firmwareImageSHA256
    }

    /// Creates a record only from a validated begin response and artifact.
    init(device: FirmingoDevice, uploadID: UInt32, capsule: ManagedCapsule) throws {
        try self.init(version: 1, deviceID: device.deviceID, bootID: device.bootID,
                      boardID: device.boardID, targetID: NanoManagedContract.targetID,
                      format: NanoManagedContract.format, uploadID: uploadID,
                      size: UInt32(capsule.bytes.count), sha256: capsule.sha256,
                      residentELFSHA256: capsule.resident.residentELFSHA256,
                      firmwareImageSHA256: capsule.resident.firmwareImageSHA256)
    }
    /// Validates every restored record before it can influence a status query.
    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(version: fields.decode(UInt32.self, forKey: .version),
                      deviceID: fields.decode(String.self, forKey: .deviceID),
                      bootID: fields.decode(String.self, forKey: .bootID),
                      boardID: fields.decode(String.self, forKey: .boardID),
                      targetID: fields.decode(UInt32.self, forKey: .targetID),
                      format: fields.decode(String.self, forKey: .format),
                      uploadID: fields.decode(UInt32.self, forKey: .uploadID),
                      size: fields.decode(UInt32.self, forKey: .size),
                      sha256: fields.decode(String.self, forKey: .sha256),
                      residentELFSHA256: fields.decode(String.self, forKey: .residentELFSHA256),
                      firmwareImageSHA256: fields.decode(String.self, forKey: .firmwareImageSHA256))
    }
    /// Shared validation for issued and restored records; no physical identity inference occurs.
    private init(version: UInt32, deviceID: String, bootID: String, boardID: String,
                 targetID: UInt32, format: String, uploadID: UInt32, size: UInt32,
                 sha256: String, residentELFSHA256: String, firmwareImageSHA256: String) throws {
        guard version == 1, NanoManagedContract.isHex(deviceID, bytes: 8),
              NanoManagedContract.isHex(bootID, bytes: 8),
              boardID == FirmingoBoard.nanoRP2040Connect.rawValue,
              targetID == NanoManagedContract.targetID, format == NanoManagedContract.format,
              uploadID > 0, (257...4096).contains(size),
              NanoManagedContract.isHex(sha256, bytes: 32),
              NanoManagedContract.isHex(residentELFSHA256, bytes: 32),
              NanoManagedContract.isHex(firmwareImageSHA256, bytes: 32) else {
            throw ManagedUploadError.invalidArtifact("Invalid or unsupported saved upload record")
        }
        self.version = version
        self.deviceID = deviceID
        self.bootID = bootID
        self.boardID = boardID
        self.targetID = targetID
        self.format = format
        self.uploadID = uploadID
        self.size = size
        self.sha256 = sha256
        self.residentELFSHA256 = residentELFSHA256
        self.firmwareImageSHA256 = firmwareImageSHA256
    }
}
