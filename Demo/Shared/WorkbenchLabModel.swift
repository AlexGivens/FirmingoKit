import Foundation
import Observation
import FirmingoWorkbenchCore
import FirmingoKit
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// App-lifetime Test Lab shared by document windows and the explicit CLI launch path.
@Observable @MainActor final class WorkbenchLabModel {
    /// One shared engine; normal launch performs no scenario or device operation.
    let engine: WorkbenchScenarioEngine
    /// Durable app-owned history, exported through UI or correlated stdout rather than container scraping.
    let store: WorkbenchFileRunStore
    /// Optional outbound paired controller; ordinary app launch leaves it disconnected.
    let pairing: WorkbenchPairedClient
    /// Manual developer invitation input, cleared immediately after validation.
    var pairingText = ""
    /// Explicit descriptor selected by the developer; never defaults to the first choice.
    var selectedBuildID = ""
    /// Explicit test-only device selection; no board is contacted when editing these fields.
    var deviceAddress = "192.168.77.1" { didSet { if deviceAddress != oldValue { expireDeviceSelection() } } }
    /// Stable device identity must be supplied by the developer, never defaulted from an address.
    var deviceID = "" { didSet { if deviceID != oldValue { expireDeviceSelection() } } }
    /// Exact board selection; hardware qualification remains per board/host/image.
    var deviceBoard = FirmingoBoard.nanoRP2040Connect.rawValue { didSet { if deviceBoard != oldValue { expireDeviceSelection() } } }
    /// Boot copied only after a successful explicit inspection of the same selection.
    var deviceBootID = ""
    /// Fixed application probe selected independently of compiler/firmware installation.
    var consoleProbe = "raw-256-v1"
    /// Explicit manual consent to send the fixed binary probe; MCP requests carry their own explicit mode.
    var allowConsoleProbe = false
    /// Original managed stage identity, explicitly selected for follow-up and restart recovery.
    var managedOperationID = ""
    /// Exact saved SDK record hash returned by staging, not a commit capability.
    var managedRecordSHA256 = ""
    /// Fixed FMS2 source vector for a new stage.
    var managedSketch = "state-a"
    /// Operator-reviewed installed resident digest; no default association is inferred.
    var managedResidentImage = ""
    /// Actual reviewed evidence for the installed resident.
    var managedEvidenceNote = ""
    /// Stage and flash commit have separate manual authorizations.
    var allowManagedStage = false
    /// Consumed after every explicit commit request, regardless of result.
    var allowManagedCommit = false
    /// Host error outside a scenario, separate from assertions inside its report.
    var error: String?
    /// Read-only historical context; loading history never restarts a run.
    var history: [WorkbenchReport] = []
    /// Explicit process mode; this does not change app identity or compiler resources.
    let automationRequested: Bool
    /// Owns manual or automation work until its terminal settlement.
    private var task: Task<Void, Never>?
    #if os(iOS)
    /// Restorable idle prevention belongs to this test host, never the reusable SDK or paired transport.
    private var idleTimerPolicy = WorkbenchIdleTimerPolicy()
    /// Real scene delivery determines whether the host may keep a running test awake.
    private var isForeground = false
    #endif
    /// Creates app-owned boundaries; no metadata, compiler, session or hardware work starts implicitly.
    init() {
        store = WorkbenchFileRunStore(directory: URL.documentsDirectory.appendingPathComponent("FirmingoWorkbench/Runs", isDirectory: true))
        automationRequested = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--workbench-") && $0 != "--workbench-pair" }
        #if os(iOS)
        let scenes = !automationRequested
        #else
        let scenes = false
        #endif
        engine = WorkbenchScenarioEngine(backend: SDKWorkbenchCompiler(), store: store, supportsSceneTransitions: scenes,
            deviceBackend: SDKWorkbenchDevice(acquire: { console in
                try await InstallationRecordStore.shared.beginWorkbenchDeviceOperation(console: console)
            }, release: { id in await InstallationRecordStore.shared.finishDeviceOperation(id) }),
            managedBackend: WorkbenchManagedCoordinator(driver: SDKWorkbenchManagedDriver(), store: WorkbenchManagedPersistence(records: .shared)))
        pairing = WorkbenchPairedClient(host: WorkbenchControlHost(engine: engine, store: store),
            diagnosticURL: store.directory.deletingLastPathComponent().appendingPathComponent("controller.json"))
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
    /// Presents action-specific prerequisites without treating a UI toggle as device authorization.
    func canRun(_ scenario: WorkbenchScenario) -> Bool {
        guard !engine.isRunning, scenario.unavailableReason == nil,
              !scenario.requiresSceneTransitions || engine.supportsSceneTransitions,
              !scenario.requiresBuild || !selectedBuildID.isEmpty else { return false }
        guard scenario.requiresDevice else { return true }
        guard !deviceID.isEmpty, !deviceAddress.isEmpty else { return false }
        if scenario.usesConsole {
            return allowConsoleProbe && !deviceBootID.isEmpty &&
                WorkbenchDeviceSelection.acceptsProbe(consoleProbe, for: scenario.id, boardID: deviceBoard)
        }
        if WorkbenchManagedSelection.scenarios.contains(scenario.id) {
            guard !deviceBootID.isEmpty else { return false }
            if scenario.id == "managed.stage" { return allowManagedStage && !managedResidentImage.isEmpty && !managedEvidenceNote.isEmpty }
            return !managedOperationID.isEmpty && (scenario.id == "managed.restore" || !managedRecordSHA256.isEmpty) && (scenario.id != "managed.commit" || allowManagedCommit)
        }
        return true
    }
    /// Captures one fresh request and lets the shared engine handle all prerequisites/assertions.
    func run(_ scenario: WorkbenchScenario) {
        guard task == nil else { return }
        task = Task {
            defer { task = nil }
            do {
                let id = UUID()
                let managed = try managedSelection(scenario: scenario.id, id: id)
                let selected: WorkbenchDeviceSelection?
                if managed != nil {
                    selected = try .init(address: deviceAddress, boardID: deviceBoard, deviceID: deviceID, bootID: deviceBootID)
                } else { selected = try scenario.requiresDevice ? selectedDevice(console: scenario.usesConsole) : nil }
                let request = try WorkbenchRequest(requestID: id, operation: .run, scenarioID: scenario.id,
                    firmwareBuildID: scenario.requiresBuild && !selectedBuildID.isEmpty ? selectedBuildID : nil,
                    device: selected, managed: managed)
                if managed != nil { allowManagedStage = false; allowManagedCommit = false }
                let result = try await engine.run(request); error = nil
                if result.scenarioID == "device.inspect", result.status == .passed,
                   let value = result.deviceEvidence, value.selection.address == deviceAddress,
                   value.selection.deviceID == deviceID, value.selection.boardID == deviceBoard {
                    deviceBootID = value.snapshot?.bootID ?? ""; allowConsoleProbe = false
                }
                if let value = result.managedEvidence?.checkpoint, let digest = try value.recordSHA256 {
                    managedOperationID = value.request.requestID.uuidString; managedRecordSHA256 = digest
                }
                history = try store.history()
            } catch { self.error = error.localizedDescription }
        }
    }
    /// Manual actions build exactly the same closed selections as MCP; restoring context grants no authority.
    private func managedSelection(scenario: String, id: UUID) throws -> WorkbenchManagedSelection? {
        guard WorkbenchManagedSelection.scenarios.contains(scenario) else { return nil }
        if scenario == "managed.stage" {
            guard allowManagedStage else { throw WorkbenchFailure("Review resident evidence and authorize RAM staging with D2 connected.") }
            return .init(operationID: id, sketch: managedSketch, residentImageSHA256: managedResidentImage,
                         evidence: managedEvidenceNote, authorization: "stage-d2-gnd")
        }
        guard let operation = UUID(uuidString: managedOperationID), scenario != "managed.commit" || allowManagedCommit else {
            throw WorkbenchFailure("Select the saved operation and record hash; commit needs its separate explicit authorization.")
        }
        if scenario == "managed.restore" { return .init(operationID: operation) }
        return .init(operationID: operation, recordSHA256: managedRecordSHA256,
                     authorization: scenario == "managed.commit" ? "commit-once-d2-gnd" : nil)
    }
    /// Selects historical query context without opening a session or restoring commit permission.
    func selectManagedContext(_ report: WorkbenchReport) {
        do {
            guard let checkpoint = report.managedEvidence?.checkpoint, let device = checkpoint.request.device,
                  let digest = try checkpoint.recordSHA256 else { throw WorkbenchFailure("Saved report has no issued managed transaction.") }
            deviceAddress = device.address; deviceBoard = device.boardID; deviceID = device.deviceID
            deviceBootID = device.bootID ?? ""; managedOperationID = checkpoint.request.requestID.uuidString
            managedRecordSHA256 = digest; allowManagedStage = false; allowManagedCommit = false
        } catch { self.error = error.localizedDescription }
    }
    /// Explicit fields become one immutable request; inspection never acquires console permission.
    private func selectedDevice(console: Bool) throws -> WorkbenchDeviceSelection {
        guard !console || allowConsoleProbe else { throw WorkbenchFailure("Authorize the fixed binary probe after inspecting the device.") }
        return try .init(address: deviceAddress, boardID: deviceBoard, deviceID: deviceID,
            bootID: console ? deviceBootID : nil, consoleProbe: console ? consoleProbe : nil)
    }
    /// Selection edits expire the observed boot and local console consent.
    func expireDeviceSelection() { deviceBootID = ""; allowConsoleProbe = false; allowManagedStage = false; allowManagedCommit = false }
    /// Cancels only the currently displayed run, without clearing its evidence or starting another action.
    func cancel() { if let id = engine.report?.id { engine.cancel(requestID: id) } }
    /// Routes real aggregate scene delivery, never an agent-authored synthetic transition.
    func recordScene(_ phase: String) {
        #if os(iOS)
        isForeground = phase == "active"
        #endif
        engine.recordScene(phase); pairing.recordScene(phase)
        updateIdleTimerPolicy()
    }
    /// Keeps only an active foreground test awake and restores the previous UIKit setting on completion or backgrounding.
    func updateIdleTimerPolicy() {
        #if os(iOS)
        let application = UIApplication.shared
        application.isIdleTimerDisabled = idleTimerPolicy.update(isForeground: isForeground,
            isRunning: engine.isRunning, currentValue: application.isIdleTimerDisabled)
        #endif
    }
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
    /// Explicit manual pairing uses the same bounded invitation decoder as development launch.
    func connectPairing() {
        do {
            guard pairingText.utf8.count <= 3000, let data = Data(base64Encoded: pairingText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw WorkbenchFailure("Paste one bounded base64 pairing invitation.")
            }
            let invitation = try WorkbenchPairingInvitation.decode(data)
            pairingText = ""; pairing.connect(invitation); error = nil
        } catch { self.error = error.localizedDescription }
    }
    /// One explicit launch invitation, usable on either Apple platform without a document/view dependency.
    func startPairingIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--workbench-pair") else { return }
        do {
            let flags = args.enumerated().filter { $0.element.hasPrefix("--workbench-") }
            guard flags.count == 1, let flag = flags.first, flag.element == "--workbench-pair", flag.offset + 1 < args.count,
                  args[flag.offset + 1].utf8.count <= 3000, let data = Data(base64Encoded: args[flag.offset + 1]) else {
                throw WorkbenchFailure("Invalid explicit pairing launch.")
            }
            pairing.connect(try WorkbenchPairingInvitation.decode(data))
        } catch { self.error = error.localizedDescription }
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
                guard !["managed.stage", "managed.commit", "managed.abort", "managed.disconnect"].contains(request.scenarioID ?? "") else { throw WorkbenchFailure("Use Test Lab or paired CLI/MCP for phases that need a live app session.") }
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
