import CryptoKit
import Foundation

/// Constants and lexical validation for the pinned experimental Nano resident contract.
enum NanoManagedContract {
    /// The legacy upload target, preserved as the ABI-one compatibility default.
    static let targetID: UInt32 = 1
    /// Complete FMS1 capsule format, distinct from UF2 firmware images.
    static let format = "nano-managed-v1"
    /// Maximum capsule bytes accepted by the experimental RAM stage and install sector.
    static let maximumSize = 4096
    /// Fixed linked code address after the padded header.
    static let codeAddress: UInt32 = 0x10200100
    /// Validates lowercase SHA-256 or device/boot hexadecimal text without normalization.
    static func isHex(_ value: String, bytes: Int) -> Bool {
        value.utf8.count == bytes * 2 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    /// Computes a lowercase SHA-256 digest for a bounded local artifact.
    static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    /// Checks the selected versioned target and its exact physical authorization policy.
    static func target(in device: FirmingoDevice, profile: ManagedSketchBuildRequest.Profile = .nanoManagedV1) throws -> FirmingoDevice.UploadTarget {
        guard device.boardID == FirmingoBoard.nanoRP2040Connect.rawValue,
              device.channels.first?.backend == .application,
              let target = device.targets.first(where: { $0.id == profile.targetID }),
              target.format == profile.rawValue, target.maximumSize == maximumSize,
              target.maximumChunk == 1024, target.authorization == "physical-d2-gnd" else {
            throw ManagedUploadError.unsupportedTarget
        }
        return target
    }
}
