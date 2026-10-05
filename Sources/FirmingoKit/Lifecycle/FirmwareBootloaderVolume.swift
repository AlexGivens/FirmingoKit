import Foundation

/// A backend-inspected ROM volume instance, never evidence of the physical board model.
/// The instance token expires across USB re-enumeration; restored context cannot authorize writing.
public struct FirmwareBootloaderVolume: Equatable, Sendable {
    /// Backend namespace to prevent mixing incompatible discovery and programming implementations.
    public let backendID: String
    /// Opaque current attachment identity supplied by the backend, not a persistent board identity.
    public let instanceID: String
    /// Explicit selected local mount root; no board is selected from its label.
    public let mountURL: URL
    /// Digest of bounded INFO_UF2.TXT bytes, checked again before a write.
    public let infoSHA256: String

    /// Constructs a bounded backend observation; host adapters must implement equivalent revalidation.
    public init(backendID: String, instanceID: String, mountURL: URL, infoSHA256: String) throws {
        guard Self.validToken(backendID, limit: 64), Self.validToken(instanceID, limit: 128),
              mountURL.isFileURL, mountURL.path.utf8.count <= 2048, !mountURL.path.utf8.contains(0),
              mountURL.user == nil, mountURL.password == nil, mountURL.query == nil, mountURL.fragment == nil,
              mountURL.host == nil || mountURL.host == "" || mountURL.host == "localhost",
              FirmwareReleaseContract.isDigest(infoSHA256) else {
            throw FirmwareInstallationError.invalidRequest("invalid bootloader volume observation")
        }
        self.backendID = backendID
        self.instanceID = instanceID
        self.mountURL = mountURL.standardizedFileURL
        self.infoSHA256 = infoSHA256
    }
    /// Restricts opaque identity text to bounded ASCII, without interpreting it as a device model.
    static func validToken(_ text: String, limit: Int) -> Bool {
        !text.isEmpty && text.utf8.count <= limit && text.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 58, 95].contains($0)
        }
    }
}
