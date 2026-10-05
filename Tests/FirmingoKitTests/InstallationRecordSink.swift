import Foundation
@testable import FirmingoKit

/// Ordered in-memory durable-record stand-in, with failure injection at a selected boundary.
actor InstallationRecordSink {
    /// Successfully acknowledged records, never silently dropped.
    private(set) var records: [FirmwareInstallationRecord] = []
    /// Optional state that fails before acknowledgement.
    let failState: FirmwareInstallationRecord.State?
    /// Whether only nonzero progress updates should fail.
    let failProgress: Bool
    /// Selects one meaningful persistence failure rather than simulating a file writer.
    init(failState: FirmwareInstallationRecord.State? = nil, failProgress: Bool = false) {
        self.failState = failState; self.failProgress = failProgress
    }
    /// Fails selected acknowledgement before recording it; callers cannot proceed through a failed gate.
    func save(_ record: FirmwareInstallationRecord) throws {
        if record.state == failState || (failProgress && record.state == .writeStarted && record.transferredBytes > 0) {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        records.append(record)
    }
}
