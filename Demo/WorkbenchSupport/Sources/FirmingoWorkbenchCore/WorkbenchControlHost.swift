import Foundation

/// Paired command dispatcher over the existing engine and app-owned store. Never creates device APIs.
@MainActor public final class WorkbenchControlHost {
    /// Per-process pairing identity; no run authority survives a process restart.
    public let instanceID = UUID()
    /// Same engine used by manual Test Lab and launch-only commands.
    private let engine: WorkbenchScenarioEngine
    /// App-owned report lookup; no external paths are accepted.
    private let store: WorkbenchFileRunStore
    /// Only the controller-admitted operation is owned here; manual runs are not cancelled on unpair.
    private var runTask: Task<Void, Never>?
    /// Exact owned identity protects a later manual run from stale disconnect/cancel.
    private var ownedRunID: UUID?
    /// Captures shared boundaries without executing anything.
    public init(engine: WorkbenchScenarioEngine, store: WorkbenchFileRunStore) { self.engine = engine; self.store = store }
    /// Revocation cancels only a still-active controller-owned request and retains its durable evidence.
    public func disconnect() {
        runTask?.cancel()
        if let ownedRunID { engine.cancel(requestID: ownedRunID) }
    }
    /// Acknowledges run only after durable engine admission; all other commands are finite queries/actions.
    public func handle(_ command: WorkbenchControlCommand) async -> WorkbenchControlReply {
        do {
            switch command.action {
            case .list:
                let catalogue = try await engine.inspectCatalogue()
                return reply(command, catalogue: catalogue, scenarios: WorkbenchScenario.all)
            case .run:
                guard let request = command.request, runTask == nil else { throw WorkbenchFailure("A controller request is already pending.") }
                return await withCheckedContinuation { continuation in
                    var admitted = false
                    runTask = Task {
                        defer { runTask = nil; ownedRunID = nil }
                        do {
                            _ = try await engine.run(request, onAdmission: {
                                admitted = true; self.ownedRunID = request.requestID
                                continuation.resume(returning: self.reply(command))
                            })
                        } catch {
                            if !admitted { continuation.resume(returning: reply(command, error: error.localizedDescription)) }
                        }
                    }
                }
            case .status:
                guard command.runID == engine.report?.id else { throw WorkbenchFailure("Selected run is not the current live context; export its saved report explicitly.") }
            case .cancel, .beginLifecycle:
                guard let id = command.runID, id == engine.report?.id, engine.isRunning else { throw WorkbenchFailure("Selected run is not active.") }
                if command.action == .cancel { engine.cancel(requestID: id) }
                else { try engine.beginLifecycleInterruption(origin: .pairedController) }
            case .report:
                guard let id = command.runID else { throw WorkbenchFailure("Missing run selection.") }
                let report = id == engine.report?.id ? engine.report : try store.load(id: id)
                return reply(command, report: report)
            }
            return reply(command)
        } catch { return reply(command, error: error.localizedDescription) }
    }
    /// Takes only durable state snapshots and bounds rejection text.
    private func reply(_ command: WorkbenchControlCommand, error: String? = nil, catalogue: WorkbenchCatalogue? = nil,
                       scenarios: [WorkbenchScenario]? = nil, report: WorkbenchReport? = nil) -> WorkbenchControlReply {
        .init(command: command, instanceID: instanceID, accepted: error == nil, error: error.map { String($0.prefix(512)) },
              state: .init(isRunning: engine.isRunning, runID: engine.report?.id, status: engine.report?.status,
                           phase: engine.report?.events.last?.phase, awaitingLifecycleStart: engine.awaitingLifecycleStart),
              scenarios: scenarios, catalogue: catalogue, report: report)
    }
}
