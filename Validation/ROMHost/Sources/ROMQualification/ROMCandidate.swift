import Foundation
import CryptoKit
import FirmingoKit

/// One real, previously pinned 0.1.0 application candidate; no generated parser fixture is deployable here.
enum ROMCandidate {
    /// Observed release index already independently pinned by SDK lifecycle provenance.
    static let manifestSHA = "39b5fd642579137ae813ca00d498d4115fa532c3cda4718e5d4f925728861aa8"
    /// Exact executable Nano application image; no implicit current/latest image selection.
    static let imageSHA = "2e2d6082d07fd25257664918de02737ce77585451f3945add56cdcf99643f0a6"
    /// Extent of that complete UF2, distinct from flash payload bytes.
    static let imageBytes = 288256
    /// Independently retained build report identity; its bytes are not bundled by the host.
    static let reportSHA = "31c2ad970b73e3c7d3c8eaab588b0a97b88068e8aeaae4791ff384f6746a2cea"
    /// Identifies explicitly acquired bytes without authenticating their publisher.
    static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    /// Acquires bounded regular files and validates one immutable manifest/image pair through public SDK APIs.
    static func load(_ arguments: ROMArguments) throws -> FirmingoFirmwareImage {
        let manifestURL = try arguments.url("--manifest")
        let manifestBytes = try ROMJournal.read(manifestURL, maximum: 16384)
        guard digest(manifestBytes) == manifestSHA else { throw ROMFailure("Manifest differs from the reviewed candidate.") }
        let manifest = try FirmingoReleaseManifest(data: manifestBytes, trustedSource: manifestURL)
        let image = try FirmingoFirmwareImage(bytes: ROMJournal.read(arguments.url("--image"), maximum: imageBytes),
            manifest: manifest, board: .nanoRP2040Connect, profile: .application)
        guard image.entry.sha256 == imageSHA, image.bytes.count == imageBytes,
              image.entry.buildReportSHA256 == reportSHA else { throw ROMFailure("Image differs from the reviewed candidate.") }
        return image
    }
    /// Restores only candidate-matching context; no mount, session or execution token is restored.
    static func record(_ url: URL) throws -> FirmwareInstallationRecord {
        let record = try JSONDecoder().decode(FirmwareInstallationRecord.self, from: ROMJournal.read(url, maximum: 16384))
        guard record.boardID == "nano_rp2040_connect", record.profile == "application",
              record.imageSHA256 == imageSHA, record.manifestSHA256 == manifestSHA,
              record.imageBytes == imageBytes, record.buildReportSHA256 == reportSHA else { throw ROMFailure("Saved record differs from the reviewed candidate.") }
        return record
    }
}
