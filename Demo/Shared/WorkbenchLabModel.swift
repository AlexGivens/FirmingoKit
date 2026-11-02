import Foundation
import Observation
import FirmingoWorkbenchCore
#if os(macOS)
import AppKit
#endif

/// App-lifetime Test Lab shared by document windows and the explicit CLI launch path.
@Observable @MainActor final class WorkbenchLabModel {
    /// One shared engine; normal launch performs no scenario or device operation.
    let engine: WorkbenchScenarioEngine
    /// Durable app-owned history, exported through UI or correlated stdout rather than container scraping.
    let store: WorkbenchFileRunStore
    /// Explicit descriptor selected by the developer; never defaults to the first choice.
    var selectedBuildID = ""
    /// Host error outside a scenario, separate from assertions inside its report.
    var error: String?
    /// Read-only historical context; loading history never restarts a run.
    var history: [WorkbenchReport] = []
    /// Explicit process mode; this does not change app identity or compiler resources.
    let automationRequested: Bool
    /// Owns manual or automation work until its terminal settlement.
    private var task: Task<Void, Never>?
    /// Creates app-owned boundaries; no metadata, compiler, session or hardware work starts implicitly.
    init() {
        store = WorkbenchFileRunStore(directory: URL.documentsDirectory.appendingPathComponent("FirmingoWorkbench/Runs", isDirectory: true))
        automationRequested = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--workbench-") }
        #if os(iOS)
        let scenes = !automationRequested
        #else
        let scenes = false
        #endif
        engine = WorkbenchScenarioEngine(backend: SDKWorkbenchCompiler(), store: store, supportsSceneTransitions: scenes)
    }
    /// Runs discovery only after an explicit manual action; unavailable resources remain visible.
    func inspectCatalogue() {
        guard task == nil else { return }
        task = Task {
            defer { task = nil }
            do { _ = try await engine.inspectCatalogue(); error = nil }
            catch { self.error = error.localizedDescription }
        }
    }
    /// Captures one fresh request and lets the shared engine handle all prerequisites/assertions.
    func run(_ scenario: WorkbenchScenario) {
        guard task == nil else { return }
        task = Task {
            defer { task = nil }
            do {
                let request = try WorkbenchRequest(operation: .run, scenarioID: scenario.id,
                    firmwareBuildID: scenario.requiresBuild && !selectedBuildID.isEmpty ? selectedBuildID : nil)
                _ = try await engine.run(request); error = nil
                history = try store.history()
            } catch { self.error = error.localizedDescription }
        }
    }
    /// Cancels only the currently displayed run, without clearing its evidence or starting another action.
    func cancel() { if let id = engine.report?.id { engine.cancel(requestID: id) } }
    /// Routes real aggregate scene delivery, never an agent-authored synthetic transition.
    func recordScene(_ phase: String) { engine.recordScene(phase) }
    /// Starts the lifecycle interruption attempt only after its known baseline/calibration.
    func beginLifecycleInterruption() {
        do { try engine.beginLifecycleInterruption(); error = nil }
        catch { self.error = error.localizedDescription }
    }
    /// Loads existing records for explicit review; incomplete prior snapshots remain unknown.
    func refreshHistory() {
        do { history = try store.history(); error = nil }
        catch { self.error = error.localizedDescription }
    }
    /// App-lifetime startup avoids depending on a view task that can disappear before evidence export.
    func startAutomationIfRequested() {
        guard automationRequested, task == nil else { return }
        #if os(macOS)
        task = Task { await automate() }
        #else
        error = "CLI launch automation is macOS-only in this increment. Run Test Lab scenarios manually here."
        #endif
    }
    #if os(macOS)
    /// Accepts one explicit bounded command; no document or device action is requested by the CLI.
    private func automate() async {
        do {
            let args = ProcessInfo.processInfo.arguments
            let flags = args.enumerated().filter { $0.element.hasPrefix("--workbench-") }
            guard flags.count == 1, let flag = flags.first, flag.element == "--workbench-request",
                  flag.offset + 1 < args.count, args[flag.offset + 1].utf8.count <= 6000,
                  let data = Data(base64Encoded: args[flag.offset + 1]) else { throw WorkbenchFailure("Invalid Workbench launch request.") }
            let request = try WorkbenchRequest.decode(data)
            let result: WorkbenchCommandResult
            do {
                if request.operation == .list {
                    let catalogue = try await engine.inspectCatalogue()
                    result = .init(request: request, catalogue: catalogue, report: nil)
                } else {
                    let report = try await engine.run(request)
                    result = .init(request: request, catalogue: engine.catalogue, report: report)
                }
            } catch {
                result = .init(request: request, catalogue: engine.catalogue, report: nil, error: error.localizedDescription)
            }
            try FileHandle.standardOutput.write(contentsOf: result.stdoutEnvelope())
            if result.error != nil { exit(2) }
            switch result.report?.status {
            case .blocked: exit(3)
            case .cancelled: exit(4)
            case .failed, .outcomeUnknown, .running: exit(1)
            case .passed, nil: exit(0)
            }
        } catch {
            do { try FileHandle.standardError.write(contentsOf: Data((error.localizedDescription + "\n").utf8)) }
            catch { exit(2) }
            exit(2)
        }
    }
    #endif
}
