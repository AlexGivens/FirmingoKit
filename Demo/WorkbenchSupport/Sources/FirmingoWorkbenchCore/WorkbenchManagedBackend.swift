import Foundation

/// Shared scenario boundary implemented by the same coordinator for manual and MCP actions.
@MainActor public protocol WorkbenchManagedBackend {
    /// Executes one separately authorized phase and publishes only durable observations.
    func run(_ request: WorkbenchRequest, save: @escaping @MainActor (WorkbenchManagedEvidence) throws -> Void) async throws
    /// Invalidates live stage authority; stored context remains query-only.
    func disconnect(operationID: UUID?) async
}

