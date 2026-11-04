import Foundation
import FirmingoKit

/// App-wide durable guard and checkpoint boundary; injected fixtures never grant hardware qualification.
@MainActor public protocol WorkbenchManagedStore {
    /// Exclusive original context creation plus durable global deployment guard.
    func begin(_ checkpoint: WorkbenchManagedCheckpoint) async throws -> UUID
    /// Reserves a follow-up against the saved original operation, without restoring write permission.
    func acquire(_ operationID: UUID) async throws -> UUID
    /// Strict bounded restore without executing anything.
    func load(_ operationID: UUID) async throws -> WorkbenchManagedCheckpoint
    /// Saves intent/record before subsequent side effects; any error must stop the driver.
    func save(_ checkpoint: WorkbenchManagedCheckpoint, lease: UUID) async throws
    /// Releases pending deployment context only after coordinator-validated completion/disposal.
    func close(_ checkpoint: WorkbenchManagedCheckpoint, lease: UUID) async throws
    /// Releases only the live lease; unresolved durable context remains blocking.
    func release(_ lease: UUID) async
}

