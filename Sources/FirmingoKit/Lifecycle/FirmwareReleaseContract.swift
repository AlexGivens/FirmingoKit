import CryptoKit
import Foundation

/// Explicit complete-image policy for the pinned schema-one Firmingo 0.1.0 beta release.
/// This is independent of FMGO managed targets and does not infer recipes for later releases.
enum FirmwareReleaseContract {
    /// RP2040 mapped flash base shared by these two independently mapped board recipes.
    static let flashStart: UInt32 = 0x10000000
    /// SDK complete-image limit: one MiB of payload in two MiB of UF2 blocks.
    static let maximumImageBytes = 2 * 1024 * 1024
    /// Selected engineering static RAM budget from both pinned baselines.
    static let maximumStaticRAM: UInt32 = 196608
    /// Selected engineering flash budget from both pinned baselines.
    static let maximumFlash: UInt32 = 1048576

    /// Matches the full board/core/options identity rather than a filename or chip family.
    static func fqbn(for board: FirmingoBoard) -> String {
        let selection: String
        switch board {
        case .nanoRP2040Connect: selection = "arduino_nano_connect:usbstack=picosdk,flash=16777216_0"
        case .raspberryPiPico: selection = "rpipico:usbstack=picosdk,flash=2097152_0"
        }
        return "rp2040:rp2040:\(selection),freq=125,ipbtstack=ipv4only,opt=Small,rtti=Disabled,exceptions=Disabled"
    }
    /// End-exclusive permitted flash address, leaving the pinned four-KiB EEPROM reservation out.
    static func flashEnd(for board: FirmingoBoard) -> UInt32 {
        let capacity: UInt32 = board == .nanoRP2040Connect ? 16777216 : 2097152
        return flashStart + capacity - 4096
    }
    /// Computes a lowercase SHA-256 without relying on a managed-sketch contract.
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    /// Checks the manifest's canonical lowercase digest spelling.
    static func isDigest(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    /// Checks self-reported FMGO device/boot identities without treating them as attestation.
    static func isIdentity(_ text: String) -> Bool {
        text.utf8.count == 16 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
