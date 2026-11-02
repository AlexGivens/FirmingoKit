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
    /// Durable per-request admission and history boundary.
    private let store: any WorkbenchRunStore
    /// Current owned asynchronous work; restoration never recreates this value.
    private var task: Task<WorkbenchReport, Error>?
    /// Actual run start used only for monotonic host timings.
    private var started = 0.0
    /// Optional bounded progress observer, invoked only after persistence succeeds.
    public var observation: ((WorkbenchReport) -> Void)?
    /// Captures boundaries without SDK I/O or automatic work.
    public init(backend: any WorkbenchCompilerBackend, store: any WorkbenchRunStore) {
        self.backend = backend; self.store = store
    }
    /// Loads metadata for UI/CLI selection; no descriptor is automatically chosen.
    public func inspectCatalogue() async throws -> WorkbenchCatalogue {
        guard !isRunning else { throw WorkbenchFailure("A Workbench scenario is already running.") }
        isRunning = true
        defer { isRunning = false }
        let result = try await backend.catalogue(); catalogue = result; return result
    }
    /// Runs one explicit request; validates and durably reserves its UUID before any backend operation.
    public func run(_ request: WorkbenchRequest) async throws -> WorkbenchReport {
        try request.validate()
        try Task.checkCancellation()
        guard request.operation == .run, !isRunning else { throw WorkbenchFailure("A run command requires an idle Workbench.") }
        let initial = WorkbenchReport(request: request)
        try store.begin(initial)
        isRunning = true; report = initial; started = ProcessInfo.processInfo.systemUptime
        observation?(initial)
        let pending = Task { try await self.perform(request) }
        task = pending
        defer { task = nil; isRunning = false }
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
    /// Publishes bounded progress only after the store confirms durability.
    private func record(_ phase: String, _ detail: String, status: WorkbenchReport.Status? = nil,
                        artifact: WorkbenchReport.Artifact? = nil) throws {
        guard var next = report, next.events.count < 64 else { throw WorkbenchFailure("Missing or excessive run evidence.") }
        if let status { next.status = status }
        if let artifact { next.artifacts.append(artifact) }
        next.events.append(.init(sequence: next.events.count, seconds: ProcessInfo.processInfo.systemUptime - started,
                                 phase: phase, detail: String(decoding: detail.utf8.prefix(1000), as: UTF8.self)))
        try store.save(next); report = next; observation?(next)
    }
    /// Executes only the closed registry; missing resources and unmigrated cases never pass.
    private func perform(_ request: WorkbenchRequest) async throws -> WorkbenchReport {
        do {
            guard let scenario = WorkbenchScenario.all.first(where: { $0.id == request.scenarioID }) else { throw WorkbenchFailure("Unknown scenario.") }
            if let reason = scenario.unavailableReason {
                try record("prerequisites", reason, status: .blocked)
            } else if scenario.requiresBuild && request.firmwareBuildID != WorkbenchCompilerInput.buildID {
                try record("prerequisites", "Select the exact migrated compiler-vector descriptor; no latest or default build is assumed.", status: .blocked)
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
                    try Task.checkCancellation()
                    try record("complete", scenario.id == "compiler.catalogue" ? "Catalogue verified; no WASM or hardware execution claimed." : "All assertions in this offline scenario completed.", status: .passed)
                }
            }
        } catch is CancellationError {
            try record("cancelled", "Cancellation settled; no fallback artifact or replay.", status: .cancelled)
        } catch ManagedCompilerError.compilationFailed(let diagnostics) {
            try recordDiagnostics(diagnostics)
            try record("failed", "Unexpected compiler rejection; inspect source diagnostics.", status: .failed)
        } catch let error as ManagedCompilerResourceError {
            let blocked: Bool
            switch error { case .missingBundle, .invalidFile, .serviceApprovalPending: blocked = true; default: blocked = false }
            try record("resources-unavailable", error.localizedDescription, status: blocked ? .blocked : .failed)
        } catch {
            try record("failed", error.localizedDescription, status: .failed)
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
