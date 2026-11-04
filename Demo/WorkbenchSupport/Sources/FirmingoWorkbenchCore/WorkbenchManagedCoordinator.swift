import Foundation

/// One-shot managed workflow shared by Test Lab and MCP; only live verified staging may commit.
@MainActor public final class WorkbenchManagedCoordinator: WorkbenchManagedBackend {
    /// Actual SDK operations, replaceable only by deterministic host fixtures.
    private let driver: any WorkbenchManagedDriver
    /// Shared demo deployment guard and durable checkpoints.
    private let store: any WorkbenchManagedStore
    /// Process-local authority; no decoder or saved record can recreate this tuple.
    private var live: (id: UUID, lease: UUID)?
    /// Main-actor reentrancy gate across asynchronous driver/storage calls.
    private var busy = false
    /// Captures dependencies without restoring or executing anything.
    public init(driver: any WorkbenchManagedDriver, store: any WorkbenchManagedStore) { self.driver = driver; self.store = store }
    /// Invalidates authority before awaiting cleanup; idle staged sessions cannot survive background/unpair.
    public func disconnect(operationID: UUID? = nil) async {
        guard let active = live, operationID == nil || operationID == active.id else { return }
        live = nil; await driver.disconnect(); await store.release(active.lease)
    }
    /// Executes one explicit finite phase; query never restores a connection capable of commit.
    public func run(_ request: WorkbenchRequest, save: @escaping @MainActor (WorkbenchManagedEvidence) throws -> Void) async throws {
        try request.validate(); try Task.checkCancellation()
        guard !busy, let selection = request.managed, let device = request.device, let action = request.scenarioID else {
            throw WorkbenchFailure("A managed action is already pending or lacks selection.")
        }
        busy = true; defer { busy = false }
        var evidence = WorkbenchManagedEvidence(selection: selection)
        var lease: UUID?
        var checkpoint: WorkbenchManagedCheckpoint?
        do {
            if action == "managed.stage" {
                guard live == nil else { throw WorkbenchFailure("Dispose the existing live stage first.") }
                var value = WorkbenchManagedCheckpoint(request: request)
                lease = try await store.begin(value); checkpoint = value
                evidence.checkpoint = value; try publish(evidence, to: save)
                evidence.artifact = try await driver.compile(sketch: selection.sketch ?? "", deviceID: device.deviceID)
                try Task.checkCancellation()
                var checked = evidence; checked.recordSHA256 = try checked.checkpoint?.recordSHA256
                try checked.validate(scenario: action, runID: request.requestID, passed: false); try publish(evidence, to: save)
                value.stageIntent = true; checkpoint = value
                try await store.save(value, lease: require(lease)); evidence.checkpoint = value; try publish(evidence, to: save)
                value.record = try await driver.stage(device); checkpoint = value
                try value.validate(); try await store.save(value, lease: require(lease)); try Task.checkCancellation()
                evidence.checkpoint = value; evidence.outcome = "ram_verified"; try publish(evidence, to: save)
                live = (selection.operationID, try require(lease)); lease = nil
            } else {
                var value = try await store.load(selection.operationID); try value.validate(); checkpoint = value
                let expectedHash = try value.recordSHA256
                guard value.request.device == device, action == "managed.restore" || expectedHash == selection.recordSHA256 else {
                    throw WorkbenchFailure("Selected endpoint/identity/boot or saved transaction changed.")
                }
                if action == "managed.restore" {
                    evidence.checkpoint = value; evidence.outcome = "context_restored"; try publish(evidence, to: save); return
                }
                guard let record = value.record else {
                    guard live == nil, !value.commitIntent, ["managed.reconcile", "managed.retire"].contains(action) else {
                        throw WorkbenchFailure("No issued transaction or live stage exists; only query or host retirement is available.")
                    }
                    lease = try await store.acquire(selection.operationID)
                    value.unknownReason = action == "managed.retire" || value.released ? "stageFailedNoCommit" : "recordNotIssued"
                    value.released = action == "managed.retire" || value.released
                    checkpoint = value; try await store.save(value, lease: require(lease))
                    if value.released { try await store.close(value, lease: require(lease)) }
                    evidence.checkpoint = value; evidence.outcome = action == "managed.retire" ? "retired_unissued" : "unknown"
                    try publish(evidence, to: save); await store.release(try require(lease)); return
                }
                if ["managed.commit", "managed.abort", "managed.disconnect"].contains(action) {
                    guard let active = live, active.id == selection.operationID, !value.commitIntent, !value.released else {
                        throw WorkbenchFailure("No live pre-commit capability. Restored context permits status queries only.")
                    }
                    lease = active.lease; live = nil
                } else {
                    guard live == nil else { throw WorkbenchFailure("Disconnect the live stage before a fresh status query.") }
                    lease = try await store.acquire(selection.operationID)
                }
                evidence.checkpoint = value; try publish(evidence, to: save)
                switch action {
                case "managed.commit":
                    value.commitIntent = true; checkpoint = value
                    try await store.save(value, lease: require(lease)); evidence.checkpoint = value; try publish(evidence, to: save)
                    try Task.checkCancellation()
                    value.snapshot = try await driver.commit(record); checkpoint = value
                    evidence.outcome = value.snapshot?.state == "failed" ? "failed" : "commit_accepted"
                case "managed.abort":
                    value.snapshot = try await driver.abort(record)
                    guard value.snapshot?.state == "aborted", value.snapshot?.slotTouched == false, value.snapshot?.errorCode == "none" else { throw WorkbenchFailure("Abort was not confirmed.") }
                    value.released = true; evidence.outcome = "aborted"
                case "managed.disconnect":
                    await driver.disconnect(); evidence.outcome = "disconnected"
                case "managed.reconcile":
                    let observed = try await driver.reconcile(device, record: record)
                    value.snapshot = observed.0; value.unknownReason = observed.1
                    evidence.outcome = observed.1 == nil ? (observed.0?.state ?? "unknown") : "unknown"
                    if ["boot_confirmed", "aborted"].contains(observed.0?.state ?? "") { value.released = true }
                case "managed.retire":
                    guard !value.commitIntent, value.unknownReason == "bootChanged", !value.released else {
                        throw WorkbenchFailure("Only a known no-commit context with an observed changed boot may be retired.")
                    }
                    value.released = true; evidence.outcome = "retired_precommit"
                default: throw WorkbenchFailure("Unsupported managed action.")
                }
                checkpoint = value; try value.validate()
                try await store.save(value, lease: require(lease))
                if value.released { try await store.close(value, lease: require(lease)) }
                await driver.disconnect(); evidence.checkpoint = value; try publish(evidence, to: save)
            }
            if let lease { await store.release(lease) }
        } catch {
            if lease != nil { await driver.disconnect() }
            if var value = checkpoint, let lease {
                if value.record == nil, !value.commitIntent {
                    value.unknownReason = "stageFailedNoCommit"; value.released = true
                    // Releasing a failed pre-commit stage grants no claim about a device transaction.
                    do { try await store.save(value, lease: lease); try await store.close(value, lease: lease) }
                    catch let cleanup { await store.release(lease); throw WorkbenchFailure("Managed checkpoint cleanup failed: \(cleanup); original: \(error)") }
                }
                evidence.checkpoint = value
                evidence.outcome = value.commitIntent ? "commit_uncertain" : "failed"
            }
            if let lease { await store.release(lease) }
            try publish(evidence, to: save); throw error
        }
    }
    /// Publishes a hash derived from the exact current checkpoint, so agents need not reconstruct Swift encoding.
    private func publish(_ value: WorkbenchManagedEvidence, to save: (WorkbenchManagedEvidence) throws -> Void) throws {
        var observed = value; observed.recordSHA256 = try value.checkpoint?.recordSHA256; try save(observed)
    }
    /// Missing reservations are internal failures, never a reason to skip durable gates.
    private func require(_ value: UUID?) throws -> UUID {
        guard let value else { throw WorkbenchFailure("Missing managed operation reservation.") }; return value
    }
}
