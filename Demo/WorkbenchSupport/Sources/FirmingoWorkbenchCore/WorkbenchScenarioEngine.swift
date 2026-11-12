import Foundation
import Observation
import FirmingoKit

/// Shared UI/automation runner; owns one cancellable offline scenario and never constructs a device API.
@Observable @MainActor public final class WorkbenchScenarioEngine {
    /// Latest durable snapshot; a persistence failure cannot leave a published passed report.
    public private(set) var report: WorkbenchReport?
    /// Exclusive admission across every Test Lab window in this app process.
    public private(set) var isRunning = false
    /// Most recently verified static metadata for explicit UI selection.
    public private(set) var catalogue: WorkbenchCatalogue?
    /// Owned SDK boundary, injectable only for deterministic orchestration tests.
    private let backend: any WorkbenchCompilerBackend
    /// Optional host-owned SDK device boundary; absence blocks hardware without compiler work.
    private let deviceBackend: (any WorkbenchDeviceBackend)?
    /// Shared managed coordinator; restored context never recreates live commit authority.
    private let managedBackend: (any WorkbenchManagedBackend)?
    /// Durable per-request admission and history boundary.
    private let store: any WorkbenchRunStore
    /// Current owned asynchronous work; restoration never recreates this value.
    private var task: Task<WorkbenchReport, Error>?
    /// Actual run start used only for monotonic host timings.
    private var started = 0.0
    /// Active compiler exercise, never reconstructed from saved reports.
    private var exercise: WorkbenchCompilerExercise?
    /// Actual aggregate app scene delivered by the interactive host only.
    private var scene = "unknown"
    /// Whether this host supplies real iOS/iPadOS scene delivery.
    public let supportsSceneTransitions: Bool
    /// True only after a lifecycle baseline/calibration is complete.
    public var awaitingLifecycleStart: Bool { exercise?.ready ?? false }
    /// Optional bounded progress observer, invoked only after persistence succeeds.
    public var observation: ((WorkbenchReport) -> Void)?
    /// Captures boundaries without SDK I/O or automatic work.
    public init(backend: any WorkbenchCompilerBackend, store: any WorkbenchRunStore, supportsSceneTransitions: Bool = false, deviceBackend: (any WorkbenchDeviceBackend)? = nil, managedBackend: (any WorkbenchManagedBackend)? = nil) {
        self.backend = backend; self.deviceBackend = deviceBackend; self.managedBackend = managedBackend; self.store = store; self.supportsSceneTransitions = supportsSceneTransitions
    }
    /// Unpairing invalidates only the controller's selected live managed operation.
    public func disconnectManaged(operationID: UUID) { Task { await managedBackend?.disconnect(operationID: operationID) } }
    /// Loads metadata for UI/CLI selection; no descriptor is automatically chosen.
    public func inspectCatalogue() async throws -> WorkbenchCatalogue {
        guard !isRunning else { throw WorkbenchFailure("A Workbench scenario is already running.") }
        isRunning = true
        defer { isRunning = false }
        let result = try await backend.catalogue(); catalogue = result; return result
    }
    /// Runs one explicit request; validates and durably reserves its UUID before any backend operation.
    public func run(_ request: WorkbenchRequest, onAdmission: () -> Void = {}) async throws -> WorkbenchReport {
        try request.validate()
        try Task.checkCancellation()
        guard request.operation == .run, !isRunning else { throw WorkbenchFailure("A run command requires an idle Workbench.") }
        let initial = WorkbenchReport(request: request)
        try store.begin(initial)
        isRunning = true; report = initial; started = ProcessInfo.processInfo.systemUptime
        observation?(initial); onAdmission()
        let pending = Task { try await self.perform(request) }
        task = pending
        defer { task = nil; exercise = nil; isRunning = false }
        return try await withTaskCancellationHandler {
            try await pending.value
        } onCancel: {
            Task { @MainActor in self.cancel(requestID: request.requestID) }
        }
    }
    /// Cancels only the currently selected run; a late caller cannot cancel a later action.
    public func cancel(requestID: UUID) {
        guard report?.id == requestID else { return }
        task?.cancel()
    }
    /// Receives real aggregate app-scene changes; unavailable to version-one launch commands.
    public func recordScene(_ phase: String) {
        guard supportsSceneTransitions, ["active", "inactive", "background"].contains(phase) else { return }
        scene = phase; exercise?.recordScene(phase)
        if phase == "background" {
            if report?.deviceOperations == true, isRunning { task?.cancel() }
            Task { await managedBackend?.disconnect(operationID: nil) }
        }
    }
    /// Explicit second action after lifecycle calibration; failures remain visible in the owning run.
    public func beginLifecycleInterruption(origin: WorkbenchExerciseEvidence.StartOrigin = .manualUI) throws {
        guard let exercise else { throw WorkbenchFailure("No lifecycle scenario is waiting for explicit start.") }
        try exercise.begin(origin: origin)
    }
    /// Publishes bounded progress only after the store confirms durability.
    private func record(_ phase: String, _ detail: String, status: WorkbenchReport.Status? = nil,
                        artifact: WorkbenchReport.Artifact? = nil) throws {
        guard var next = report, next.events.count < 64 else { throw WorkbenchFailure("Missing or excessive run evidence.") }
        if let status { next.status = status }
        if let artifact, !next.artifacts.contains(where: { $0.name == artifact.name }) { next.artifacts.append(artifact) }
        next.events.append(.init(sequence: next.events.count, seconds: ProcessInfo.processInfo.systemUptime - started,
                                 phase: phase, detail: String(decoding: detail.utf8.prefix(1000), as: UTF8.self)))
        try store.save(next); report = next; observation?(next)
    }
    /// Executes only the closed registry; missing resources and unmigrated cases never pass.
    private func perform(_ request: WorkbenchRequest) async throws -> WorkbenchReport {
        var managedStageCompleted = false
        do {
            guard let scenario = WorkbenchScenario.all.first(where: { $0.id == request.scenarioID }) else { throw WorkbenchFailure("Unknown scenario.") }
            if let reason = scenario.unavailableReason {
                try record("prerequisites", reason, status: .blocked)
            } else if scenario.requiresSceneTransitions && !supportsSceneTransitions {
                try record("prerequisites", "Requires interactive iOS/iPadOS scene delivery; CLI cannot synthesize lifecycle events.", status: .blocked)
            } else if scenario.requiresBuild && request.firmwareBuildID != WorkbenchCompilerInput.buildID {
                try record("prerequisites", "Select the exact migrated compiler-vector descriptor; no latest or default build is assumed.", status: .blocked)
            } else if request.managed != nil {
                if let managedBackend {
                    try record("managed-start", "Executing one explicit managed phase; commit and reconciliation remain separate.")
                    try await managedBackend.run(request) { value in
                        guard var next = self.report else { throw WorkbenchFailure("Missing managed run context.") }
                        next.managedEvidence = value; try self.store.save(next); self.report = next; self.observation?(next)
                    }
                    managedStageCompleted = request.scenarioID == "managed.stage"
                    let outcome = report?.managedEvidence?.outcome ?? "not_observed"
                    let status: WorkbenchReport.Status = ["ram_verified", "commit_accepted", "aborted", "disconnected", "boot_confirmed", "retired_precommit", "retired_unissued", "context_restored"].contains(outcome) ? .passed : (outcome == "failed" ? .failed : .outcomeUnknown)
                    try record(status == .passed ? "complete" : "managed-result", "Managed phase: " + outcome + ". Commit acceptance is not startup or useful behavior.", status: status)
                } else { try record("prerequisites", "This host has no managed workflow backend.", status: .blocked) }
            } else if scenario.requiresDevice {
                guard let selected = request.device else { throw WorkbenchFailure("Missing device selection.") }
                if let deviceBackend {
                    try record("device-start", "Selected SDK device operation; no compiler or upload prerequisite.")
                    try await deviceBackend.run(selected, console: scenario.usesConsole) { value in
                        guard var next = self.report else { throw WorkbenchFailure("Missing hardware run context.") }
                        next.deviceEvidence = value; try self.store.save(next); self.report = next; self.observation?(next)
                    }
                    try Task.checkCancellation()
                    guard let observed = report?.deviceEvidence, observed.selection == selected else { throw WorkbenchFailure("Missing selected device evidence.") }
                    try observed.validate(console: scenario.usesConsole)
                    let detail = selected.stateSketch.map { "\($0) startup data, zero BSS and advancing counters verified. Console closed and disconnected." }
                        ?? "Selected device assertions and SDK cleanup completed."
                    try record("complete", detail, status: .passed)
                } else { try record("prerequisites", "This host has no device backend.", status: .blocked) }
            } else {
                try Task.checkCancellation()
                try record("catalogue", "Loading actual SDK-verified catalogue metadata.")
                let loaded = try await backend.catalogue(); catalogue = loaded
                guard var next = report else { throw WorkbenchFailure("Missing run context.") }
                next.catalogueSHA256 = loaded.sha256; try store.save(next); report = next
                if scenario.requiresBuild && !loaded.builds.contains(where: { $0.id == request.firmwareBuildID }) {
                    try record("prerequisites", "The explicitly selected descriptor is absent from this SDK package.", status: .blocked)
                } else {
                    if scenario.id != "compiler.catalogue" {
                        try Task.checkCancellation()
                        try record("resources", "Verifying real bundled compiler/runtime resources.")
                        try await backend.verifyResources()
                    }
                    if scenario.id == "compiler.smoke" {
                        try await compile(.gpio, buildID: request.firmwareBuildID ?? "")
                        try await compile(.console, buildID: request.firmwareBuildID ?? "")
                    } else if scenario.id == "compiler.diagnostics" {
                        try record("frontend-error", "Requiring typed compiler rejection and nonempty diagnostics.")
                        do {
                            _ = try await backend.compile(.invalid, buildID: request.firmwareBuildID ?? "")
                            throw WorkbenchFailure("Invalid source unexpectedly compiled.")
                        } catch ManagedCompilerError.compilationFailed(let diagnostics) {
                            guard diagnostics.contains(where: { $0.severity == .error && $0.filename == "Workbench-invalid.ino" }) else {
                                throw WorkbenchFailure("Expected an error mapped to Workbench-invalid.ino.")
                            }
                            try recordDiagnostics(diagnostics)
                            try record("frontend-rejected", "Observed \(diagnostics.count) source diagnostics.")
                        }
                        try await compile(.gpio, buildID: request.firmwareBuildID ?? "")
                    }
                    if ["compiler.cancellation", "compiler.deadline", "compiler.stress", "host.lifecycle", "host.lifecycle-active", "host.lifecycle-worker"].contains(scenario.id) {
                        let owner = WorkbenchCompilerExercise(kind: scenario.id, backend: backend, buildID: request.firmwareBuildID ?? "", scene: scene, observesScenes: supportsSceneTransitions,
                            now: { ProcessInfo.processInfo.systemUptime - self.started },
                            save: { value in
                                guard var next = self.report else { throw WorkbenchFailure("Missing compiler exercise context.") }
                                next.exercise = value; try self.store.save(next); self.report = next; self.observation?(next)
                            }, emit: { phase, detail, artifact in try self.record(phase, detail, artifact: artifact) })
                        exercise = owner
                        try await owner.run()
                    }
                    try Task.checkCancellation()
                    try record("complete", scenario.id == "compiler.catalogue" ? "Catalogue verified; no WASM or hardware execution claimed." : "All assertions in the selected scenario completed.", status: .passed)
                }
            }
        } catch let error as ManagedUploadError {
            try record("managed-error", error.localizedDescription, status: report?.managedEvidence?.checkpoint?.commitIntent == true ? .outcomeUnknown : .failed)
        } catch is CancellationError {
            try record("cancelled", "Cancellation settled; no fallback artifact or replay.", status: report?.managedEvidence?.checkpoint?.commitIntent == true ? .outcomeUnknown : .cancelled)
        } catch ManagedCompilerError.compilationFailed(let diagnostics) {
            try recordDiagnostics(diagnostics)
            try record("failed", "Unexpected compiler rejection; inspect source diagnostics.", status: .failed)
        } catch let error as ManagedCompilerResourceError {
            let blocked: Bool
            switch error { case .missingBundle, .invalidFile, .serviceApprovalPending: blocked = true; default: blocked = false }
            try record("resources-unavailable", error.localizedDescription, status: blocked ? .blocked : .failed)
        } catch {
            if managedStageCompleted, let operationID = request.managed?.operationID { await managedBackend?.disconnect(operationID: operationID) }
            try record("failed", error.localizedDescription, status: report?.managedEvidence?.checkpoint?.commitIntent == true ? .outcomeUnknown : .failed)
        }
        guard let report, report.status != .running else { throw WorkbenchFailure("Scenario ended without a terminal result.") }
        return report
    }
    /// Retains bounded real source coordinates/messages and makes any presentation omission explicit.
    private func recordDiagnostics(_ diagnostics: [SketchDiagnostic]) throws {
        guard var next = report else { throw WorkbenchFailure("Missing diagnostic run context.") }
        next.diagnostics = diagnostics.prefix(16).map { diagnostic in
            .init(severity: diagnostic.severity.rawValue,
                  message: String(decoding: diagnostic.message.utf8.prefix(1000), as: UTF8.self),
                  filename: diagnostic.filename, line: diagnostic.line, column: diagnostic.column)
        }
        next.diagnosticsOmitted = max(0, diagnostics.count - 16)
        try store.save(next); report = next; observation?(next)
    }
    /// Retains real capsule bytes only after SDK and independent vector assertions pass.
    private func compile(_ input: WorkbenchCompilerInput, buildID: String) async throws {
        try Task.checkCancellation()
        try record("compile-" + input.rawValue, "Executing actual WASM compile/link/package through the SDK.")
        let result = try await backend.compile(input, buildID: buildID)
        try Task.checkCancellation()
        try record("artifact-" + input.rawValue, "Expected and observed capsule SHA-256: " + result.sha256, artifact: result)
    }
}
