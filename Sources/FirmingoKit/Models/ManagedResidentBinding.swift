import Foundation

/// Host-supplied exact resident metadata associated with a selected physical device.
/// The host must verify the ELF/image hashes and API symbol through trusted build/install records.
/// Hello cannot attest to these bytes; constructing this value does not verify the installed image.
public struct ManagedResidentBinding: Equatable, Sendable {
    /// Selected device ID from the host's resident installation record, not an IP address.
    public let deviceID: String
    /// The exact resident ELF for which code was linked, as lowercase SHA-256.
    public let residentELFSHA256: String
    /// The known installed complete Firmingo image, as lowercase SHA-256; retained as host provenance.
    public let firmwareImageSHA256: String
    /// Four-byte-aligned API table address from that exact resident ELF.
    public let apiAddress: UInt32

    /// Present only for ABI-two/FMS2; nil preserves the ABI-one stateless contract.
    public let state: ManagedResidentState?
    /// Explicit artifact profile derived from the reviewed resident contract, never guessed from capsule bytes.
    public var profile: ManagedSketchBuildRequest.Profile { state == nil ? .nanoManagedV1 : .nanoManagedV2 }

    /// Validates metadata syntax/ranges for the Nano resident selected by the optional state contract without claiming remote attestation.
    public init(deviceID: String, residentELFSHA256: String, firmwareImageSHA256: String,
                apiAddress: UInt32, state: ManagedResidentState? = nil) throws {
        guard NanoManagedContract.isHex(deviceID, bytes: 8),
              NanoManagedContract.isHex(residentELFSHA256, bytes: 32),
              NanoManagedContract.isHex(firmwareImageSHA256, bytes: 32),
              (0x10000000..<0x10200000).contains(apiAddress), apiAddress % 4 == 0 else {
            throw ManagedUploadError.invalidArtifact("Invalid Nano resident binding metadata")
        }
        self.deviceID = deviceID
        self.residentELFSHA256 = residentELFSHA256
        self.firmwareImageSHA256 = firmwareImageSHA256
        self.apiAddress = apiAddress; self.state = state
    }
}
