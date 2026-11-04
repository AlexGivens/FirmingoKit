import Foundation
import FirmingoKit

/// Version-two, explicitly selected local FMGO endpoint. No discovery, arbitrary port or flash authority.
public struct WorkbenchDeviceSelection: Codable, Sendable, Equatable {
    /// Private numeric IPv4 address; the FMGO test port is fixed at 7420.
    public let address: String
    /// Exact SDK board identifier; a supported selection is not hardware qualification.
    public let boardID: String
    /// Previously selected stable identity, never inferred from the IP address.
    public let deviceID: String
    /// Required for console bytes, observed in a separate successful inspection.
    public let bootID: String?
    /// Explicit authorization for one bounded known application probe; absent for inspection.
    public let consoleProbe: String?
    /// Supported fixed application protocols; never arbitrary data or firmware commands.
    public static let probes = ["raw-256-v1", "fms2-command-2-v1"]
    /// Construction validates selection only and performs no I/O.
    public init(address: String, boardID: String, deviceID: String, bootID: String? = nil, consoleProbe: String? = nil) throws {
        self.address = address; self.boardID = boardID; self.deviceID = deviceID
        self.bootID = bootID; self.consoleProbe = consoleProbe
        try validate()
    }
    /// Restricts networking to selected private IPv4 and declared SDK board identities.
    public func validate() throws {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        let bytes = parts.compactMap { UInt8($0) }
        guard parts.count == 4, bytes.count == 4, zip(parts, bytes).allSatisfy({ String($0.1) == $0.0 }),
              bytes[0] == 10 || (bytes[0] == 172 && (16...31).contains(bytes[1])) || (bytes[0] == 192 && bytes[1] == 168),
              FirmingoBoard(rawValue: boardID) != nil, Self.isID(deviceID), bootID == nil || Self.isID(bootID ?? ""),
              consoleProbe == nil || Self.probes.contains(consoleProbe ?? "") else {
            throw WorkbenchFailure("Select a private IPv4 endpoint, exact board/device identity and a supported probe.")
        }
    }
    /// Stable/boot identity syntax follows the pinned FMGO hello contract.
    public static func isID(_ value: String) -> Bool {
        value.utf8.count == 16 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    /// Closed nested decoding; no hidden endpoint, source or write options can be smuggled through MCP.
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 1024, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["address", "boardID", "deviceID", "bootID", "consoleProbe"]) else {
            throw WorkbenchFailure("Invalid device selection.")
        }
        guard !(object["bootID"] is NSNull), !(object["consoleProbe"] is NSNull) else {
            throw WorkbenchFailure("Optional device fields must be omitted rather than null.")
        }
        let value = try JSONDecoder().decode(Self.self, from: data); try value.validate(); return value
    }
}
