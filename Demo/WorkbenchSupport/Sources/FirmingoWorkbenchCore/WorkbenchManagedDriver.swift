import Foundation
import FirmingoKit

/// Narrow public-SDK driver; production owns the actual ephemeral session and compiled capsule.
@MainActor public protocol WorkbenchManagedDriver {
    /// Real fixed source compilation returns exact capsule/receipt evidence before networking.
    func compile(sketch: String, deviceID: String) async throws -> WorkbenchReport.Artifact
    /// Fresh identity/boot/capability checks followed by RAM staging only.
    func stage(_ selection: WorkbenchDeviceSelection) async throws -> ManagedUploadRecord
    /// Consumes only an actual live verified session; cannot be recreated from a record.
    func commit(_ record: ManagedUploadRecord) async throws -> WorkbenchManagedCheckpoint.Snapshot
    /// Disposes a live pre-commit stage without flash writing.
    func abort(_ record: ManagedUploadRecord) async throws -> WorkbenchManagedCheckpoint.Snapshot
    /// Actual disconnect on cancellation, backgrounding, unpairing and errors.
    func disconnect() async
    /// Fresh read-only SDK reconciliation, without write/session restoration.
    func reconcile(_ selection: WorkbenchDeviceSelection, record: ManagedUploadRecord) async throws -> (WorkbenchManagedCheckpoint.Snapshot?, String?)
}

