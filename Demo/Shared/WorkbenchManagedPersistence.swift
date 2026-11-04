import Foundation
import FirmingoWorkbenchCore

/// Bridges the shared engine to the demo's existing app-wide durable deployment guard.
@MainActor struct WorkbenchManagedPersistence: WorkbenchManagedStore {
    /// All document windows and Test Lab share this actor.
    let records: InstallationRecordStore
    /// Rejects stale/corrupt checkpoint bytes before their global reservation is used.
    func load(_ operationID: UUID) async throws -> WorkbenchManagedCheckpoint {
        let value = try JSONDecoder().decode(WorkbenchManagedCheckpoint.self, from: await records.loadWorkbenchManaged(id: operationID))
        try value.validate()
        guard value.request.managed?.operationID == operationID else { throw WorkbenchFailure("Changed managed context identity.") }; return value
    }
    /// Exclusive original context admission, without a device or compiler side effect.
    func begin(_ checkpoint: WorkbenchManagedCheckpoint) async throws -> UUID {
        try await records.beginWorkbenchManaged(id: checkpoint.request.requestID, checkpoint: encode(checkpoint))
    }
    /// Acquires only the exact saved operation; no executable authority is restored.
    func acquire(_ operationID: UUID) async throws -> UUID { try await records.acquireWorkbenchManaged(id: operationID) }
    /// Both checkpoint and shared SDK record must synchronize before later side effects.
    func save(_ checkpoint: WorkbenchManagedCheckpoint, lease: UUID) async throws {
        try await records.saveWorkbenchManaged(id: checkpoint.request.requestID, checkpoint: encode(checkpoint), record: checkpoint.record, lease: lease)
    }
    /// Only validated released contexts may remove their pending pointer.
    func close(_ checkpoint: WorkbenchManagedCheckpoint, lease: UUID) async throws {
        try checkpoint.validate(); guard checkpoint.released else { throw WorkbenchFailure("Managed context is unresolved.") }
        try await records.closeWorkbenchManaged(id: checkpoint.request.requestID, record: checkpoint.record, lease: lease)
    }
    /// Releases exactly the acquired process-local lease; pending context survives.
    func release(_ lease: UUID) async { await records.finishDeviceOperation(lease) }
    /// Validates before writing; encoded records never include sessions or commit capabilities.
    private func encode(_ value: WorkbenchManagedCheckpoint) throws -> Data {
        try value.validate(); let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
    }
}
