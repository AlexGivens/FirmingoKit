import Foundation

/// A process-local one-shot execution token bound to an inspected target and validated image.
/// A saved record cannot reconstruct this value; prepare a new action after uncertainty or restart.
public struct PreparedFirmwareInstallation: Sendable {
    /// SDK guidance describing artifact effects, physical steps, and verification limitations.
    public let plan: FirmingoInstallationPlan
    /// Prepared record available for durable saving before the separate execute call.
    public let record: FirmwareInstallationRecord
    /// Exact current ROM attachment that must survive revalidation before any write.
    public let volume: FirmwareBootloaderVolume
    /// Originating installer identity prevents tokens from being used with another backend/runtime.
    let installerID: UUID
}
