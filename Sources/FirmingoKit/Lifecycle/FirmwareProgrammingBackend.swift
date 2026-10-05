import Foundation

/// Trusted, injectable programming boundary; consumers execute through ``FirmingoInstaller``.
/// Implementations must bind writes to the inspected attachment, not a reusable mount path alone.
public protocol FirmwareProgrammingBackend: Sendable {
    /// Stable backend namespace, matched against every inspected volume.
    var identifier: String { get }
    /// Inspects an explicitly selected mount without writing or identifying the physical board model.
    func inspect(volumeURL: URL) async throws -> FirmwareBootloaderVolume
    /// Revalidates the exact attachment and transfers the validated image without retry or rollback.
    /// Call `willWrite` exactly once, and await its successful return before creating/writing any file.
    /// A failed callback must prevent all writes.
    /// Revalidate the attachment again after this awaited gate and before creating the output file.
    /// Report monotonically increasing locally accepted bytes through the awaited `progress` callback;
    /// its failure/cancellation stops further transfer.
    /// Return only after all bytes, synchronization, and resource close succeed. This does not prove
    /// reboot or installation; failures after the write gate are conservatively uncertain.
    func write(image: FirmingoFirmwareImage, to volume: FirmwareBootloaderVolume,
               willWrite: @escaping @Sendable () async throws -> Void,
               progress: @escaping @Sendable (Int) async throws -> Void) async throws
}
