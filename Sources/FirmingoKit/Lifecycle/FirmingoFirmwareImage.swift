import Foundation

/// A complete Firmingo UF2 whose exact release metadata, digest, and flash layout were checked.
/// This type cannot be supplied to the managed uploader and does not prove executable behavior,
/// publisher authenticity, physical board identity, or successful installation.
public struct FirmingoFirmwareImage: Sendable {
    /// Immutable complete UF2 bytes acquired by the host; no bundled firmware or remote fallback.
    public let bytes: Data
    /// Exact validated release entry, including board/profile and independent build-report digest.
    public let entry: FirmingoReleaseManifest.Entry
    /// Host-declared trusted source retained from the manifest, never contacted by this validator.
    public let releaseSource: URL
    /// Digest of the manifest bytes binding this local acquisition to its index.
    public let manifestSHA256: String
    /// End-exclusive mapped flash payload range, measured from every UF2 block.
    public let payloadRange: Range<UInt32>
    /// Conservative end-exclusive four-KiB erase extent, separate from bytes explicitly written.
    public let affectedFlashRange: Range<UInt32>
    /// Validated count of unique complete UF2 blocks.
    public let blockCount: Int

    /// Validates host-acquired bytes against an exact manifest board/profile selection.
    /// Checks size before hashing/allocation, then SHA-256 before decoding the UF2 layout.
    /// This synchronous CPU operation should run off the main actor for UI hosts. It performs no
    /// filesystem, network, or board I/O and throws ``FirmwareLifecycleError`` on mismatch.
    public init(bytes: Data, manifest: FirmingoReleaseManifest,
                board: FirmingoBoard, profile: FirmingoDevice.Backend) throws {
        let entry = try manifest.entry(for: board, profile: profile)
        guard bytes.count == entry.byteCount else {
            throw FirmwareLifecycleError.invalidImage("byte count does not match the release manifest")
        }
        guard FirmwareReleaseContract.digest(bytes) == entry.sha256 else {
            throw FirmwareLifecycleError.invalidImage("SHA-256 does not match the release manifest")
        }
        let layout = try UF2ImageLayout(bytes: bytes, board: board)
        self.bytes = bytes
        self.entry = entry
        releaseSource = manifest.source
        manifestSHA256 = manifest.sha256
        payloadRange = layout.payloadRange
        affectedFlashRange = layout.eraseRange
        blockCount = layout.blockCount
    }
}
