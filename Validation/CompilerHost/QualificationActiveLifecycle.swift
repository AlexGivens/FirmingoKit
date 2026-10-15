import Foundation
import CryptoKit
import FirmingoKit

/// Explicit host policy test: cancel a pending SDK call on inactivity, observe background/return, then build fresh.
@MainActor final class QualificationActiveLifecycle {
    /// Native cancellation observation; the last progress callback is not a WASM instruction pointer.
    struct Cancellation: Encodable {
        /// One-based attempt whose pending public SDK task was canceled.
        let attempt: Int
        /// Monotonic request time relative to this run's origin.
        let requestedSeconds: Double
        /// Most recent accepted SDK progress, or admitted before the first callback.
        let lastProgress: String
        /// Worker mode requires the first source-compilation notification, before entry-wrapper compilation.
        var compilingNotificationCount: Int?
        /// Native observation time for that attempt's first compiling notification.
        var compilePhaseBeganSeconds: Double?
        /// Pending until the task actually throws CancellationError after its cleanup path.
        var outcome = "pending"
        /// Observation time when the pending SDK task settled.
        var settledSeconds: Double?
        /// Set if the canceled task incorrectly returns a result; such a run fails.
        var artifactReturned = false
    }

    /// Distinct bounded evidence contract; idle and repeated-build schemas remain unchanged.
    struct Report: Encodable {
        /// Version of the active-call cancellation journal only.
        var schema = 4
        /// Cancellation belongs to this test host, not an automatic SDK lifecycle policy.
        var kind = "inactive-cancel-background-return"
        /// Fresh explicitly selected uppercase UUID.
        let runID: String
        /// Exact verified SDK and consumer inputs.
        let context: QualificationContext
        /// Static experimental target, without installed-image evidence.
        let firmwareBuildID: String
        /// Current runtime, independent of deployment minimum.
        let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
        /// Matches the independent launcher before and after the transition.
        let hostProcessID = ProcessInfo.processInfo.processIdentifier
        /// Running, failed or passed; incomplete cancellation cannot pass.
        var status = "running"
        /// Persisted before entering each operation.
        var stage = "waiting-for-active"
        /// Actual scene events, bounded at 64 observations.
        var events: [QualificationLifecycle.Event] = []
        /// Known preflight GPIO and fresh console results only.
        var steps: [QualificationStep] = []
        /// Known GPIO attempts that finished before the inactivity event.
        var completedAttempts: [QualificationStep] = []
        /// Actual cancellation request and typed result; nil if no active call was interrupted.
        var cancellation: Cancellation?
        /// Explicit user start time, separate from automatic launch/preflight.
        var manuallyStartedSeconds: Double?
        /// Fresh build admission after both cancellation settlement and the real active return.
        var freshStartedSeconds: Double?
        /// Exact optional qualification workload; absent in the original active-call mode.
        var workerWorkloadSHA256: String?
        /// Checked source byte count, below the unchanged compiler source cap.
        var workerWorkloadBytes: Int?
        /// Completed preflight interval between first and second compiling notifications.
        var preflightCompilePhaseSeconds: Double?
        /// Manual action admission bound; OS suspension can delay observation.
        let observationLimitSeconds = 600
        /// Finite actual build series; exhaustion without cancellation fails.
        let maximumAttempts = 40
        /// Meaningful observed background-to-active interval.
        let minimumBackgroundSeconds = 3
        /// No installation, upload or other device operation is used.
        let deviceOperations = false
        /// Bounded failure text; cleanup errors retain failure status.
        var error: String?
    }

    /// Shared monotonic origin for every observation.
    private let start = ProcessInfo.processInfo.systemUptime
    /// New private results directory; never overwrites an earlier run.
    private let directory: URL
    /// Atomic journal in the app's own Documents container.
    private let journal: URL
    /// Main-actor-owned durable evidence.
    private var report: Report
    /// Last view-delivered scene state.
    private var phase = "unknown"
    /// Current attempt, used to reject late progress from earlier calls.
    private var attempt = 0
    /// Latest observed progress for the current SDK call.
    private var lastProgress = "admitted"
    /// Sole pending build task; scene inactivity cancels this exact task once.
    private var pending: Task<ManagedOfflineCompilationResult, any Error>?
    /// Recording failures are surfaced by the async owner.
    private var recordingError: Error?
    /// Selects stricter first-source-compile eligibility without changing the original mode.
    private let workerCompilation: Bool
    /// Verified fixed C++ workload, used only by the opt-in worker mode.
    private var workerSource: String?
    /// Current attempt's compiling notification ordinal.
    private var compilingNotifications = 0
    /// Current attempt's first compiling observation.
    private var compilingBeganSeconds: Double?
    /// Preflight first compiling observation, kept separate from active attempts.
    private var preflightCompilingBegan: Double?
    /// Bounds/identifies preflight source versus entry-wrapper compilation.
    private var preflightCompilingNotifications = 0

    /// Creates a fresh journal with the same anchored context as other host modes.
    init(id: UUID, phase: String, workerCompilation: Bool = false) throws {
        guard let contextURL = Bundle.main.url(forResource: "qualification-context", withExtension: "json"),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let context = try JSONDecoder().decode(QualificationContext.self, from: Data(contentsOf: contextURL))
        directory = documents.appendingPathComponent("CompilerQualification-" + id.uuidString, isDirectory: true)
        journal = directory.appendingPathComponent("report.json")
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw CocoaError(.fileWriteFileExists) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        report = Report(runID: id.uuidString, context: context, firmwareBuildID: QualificationChecks.buildID)
        self.workerCompilation = workerCompilation
        if workerCompilation {
            workerSource = try Self.loadWorkerSource()
            report.schema = 5; report.kind = "worker-compile-inactive-cancel-return"
            report.workerWorkloadBytes = 227505
            report.workerWorkloadSHA256 = "9a17105b5d17f732435ab81c6bf1083386e5cb5ae8b36569259bac8cf479ec3f"
        }
        try persist(); record(phase: phase)
    }

    /// Loads only the pinned test fixture; no asset/recipe modification or arbitrary source provider is introduced.
    private static func loadWorkerSource() throws -> String {
        guard let url = Bundle.main.url(forResource: "worker-compile-workload", withExtension: "txt"),
              try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == 227505 else { throw CocoaError(.fileReadCorruptFile) }
        let bytes = try Data(contentsOf: url)
        guard bytes.count == 227505,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == "9a17105b5d17f732435ab81c6bf1083386e5cb5ae8b36569259bac8cf479ec3f",
              let source = String(data: bytes, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        return source
    }

    /// Called only by the explicit start button after preflight; no synthesized scene transition occurs.
    func begin() {
        guard report.status == "running", report.stage == "waiting-for-start", phase == "active",
              report.manuallyStartedSeconds == nil else { return }
        report.manuallyStartedSeconds = ProcessInfo.processInfo.systemUptime - start
        do { try persist() } catch { recordingError = error }
    }

    /// Inactivity requests cancellation while work is pending; background and return must still actually occur.
    func record(phase: String) {
        guard report.status == "running", ["active", "inactive", "background"].contains(phase), self.phase != phase else { return }
        self.phase = phase
        do {
            guard report.events.count < 64 else { throw CocoaError(.coderInvalidValue) }
            let seconds = ProcessInfo.processInfo.systemUptime - start
            report.events.append(QualificationLifecycle.Event(seconds: seconds, phase: phase, stage: report.stage))
            if phase == "inactive", report.stage == "active-builds", let pending, report.cancellation == nil {
                report.cancellation = Cancellation(attempt: attempt, requestedSeconds: seconds, lastProgress: lastProgress)
                if workerCompilation {
                    report.cancellation?.compilingNotificationCount = compilingNotifications
                    report.cancellation?.compilePhaseBeganSeconds = compilingBeganSeconds
                }
                report.stage = "awaiting-cancellation"
                pending.cancel()
            }
            try persist()
        } catch { recordingError = error }
    }

    /// Late progress cannot change cancellation evidence or a later attempt's phase.
    private func progress(_ value: ManagedCompilationPhase, attempt: Int) {
        guard self.attempt == attempt, pending != nil, report.cancellation == nil else { return }
        lastProgress = value.rawValue
        if value == .compiling {
            compilingNotifications += 1
            if compilingNotifications == 1 { compilingBeganSeconds = ProcessInfo.processInfo.systemUptime - start }
        }
    }

    /// Measures a genuine complete source compile before asking the user to interrupt another one.
    private func preflightProgress(_ value: ManagedCompilationPhase) {
        guard workerCompilation, report.stage == "before-active-gpio", value == .compiling else { return }
        preflightCompilingNotifications += 1
        if preflightCompilingNotifications == 1 { preflightCompilingBegan = ProcessInfo.processInfo.systemUptime - start }
        if preflightCompilingNotifications == 2, let preflightCompilingBegan {
            report.preflightCompilePhaseSeconds = ProcessInfo.processInfo.systemUptime - start - preflightCompilingBegan
        }
    }

    /// Writes complete evidence without a background task grant or extension.
    private func persist() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: journal, options: .atomic)
    }

    /// Bounds admission/waiting and surfaces durable-recording errors.
    private func check() throws {
        try Task.checkCancellation()
        if let recordingError { throw recordingError }
        guard ProcessInfo.processInfo.systemUptime - start < 600 else { throw ManagedCompilerError.timedOut }
    }

    /// Requires real background and return after cancellation, without inferring OS suspension.
    private func waitForReturn() async throws {
        while true {
            try check()
            guard let cancellation = report.cancellation else { throw CocoaError(.fileReadCorruptFile) }
            if let background = report.events.firstIndex(where: { $0.phase == "background" && $0.seconds >= cancellation.requestedSeconds }),
               let active = report.events.dropFirst(background + 1).first(where: { $0.phase == "active" }) {
                guard active.seconds - report.events[background].seconds >= 3, phase == "active" else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Arms after real preflight, awaits a manual start, then exercises cancellation and same-instance fresh reentry.
    func run(status: (String) -> Void, ready: (Bool) -> Void) async throws -> URL {
        defer { pending?.cancel(); pending = nil; ready(false) }
        do {
            while phase != "active" { try check(); try await Task.sleep(for: .milliseconds(100)) }
            let catalogue = try await ManagedCompilerCatalogue.loadBundled()
            guard catalogue.manifestSHA256 == "e341bfc0385fea9b2b026dc624daa26cdeac33286f4bb07243b37c1c31837d0e",
                  catalogue.firmwareBuilds.count == 1, try catalogue.build(id: QualificationChecks.buildID).apiAddress == 0x10022c9c else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let compiler = ManagedSketchCompiler(); try await compiler.verifyResources()
            try await build(compiler, catalogue: catalogue, before: true)
            guard phase == "active" else { throw CocoaError(.fileReadCorruptFile) }
            if workerCompilation {
                guard let seconds = report.preflightCompilePhaseSeconds, (4...55).contains(seconds) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
            report.stage = "waiting-for-start"; try persist(); ready(true)
            status("Ready. Start the active check, wait one second, then go Home for five seconds and return.")
            while report.manuallyStartedSeconds == nil { try check(); try await Task.sleep(for: .milliseconds(100)) }
            ready(false)
            for index in 1...40 {
                try check(); guard phase == "active" else { throw CocoaError(.fileReadCorruptFile) }
                attempt = index; lastProgress = "admitted"; compilingNotifications = 0; compilingBeganSeconds = nil
                report.stage = "active-builds"; try persist()
                let request = try QualificationChecks.request(workerSource ?? QualificationChecks.gpio, name: "active-\(index)-gpio", revision: UInt64(index + 1), catalogue: catalogue)
                let began = ProcessInfo.processInfo.systemUptime
                let task = Task { [weak self] in
                    try await compiler.build(request) { [weak self] value in
                        Task { @MainActor in self?.progress(value, attempt: index) }
                    }
                }
                pending = task
                do {
                    let result = try await task.value; pending = nil
                    if report.cancellation != nil {
                        report.cancellation?.artifactReturned = true
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    guard result.artifact.sha256 == QualificationChecks.gpioSHA,
                          result.artifact.receipt.firmwareBuildID == QualificationChecks.buildID,
                          result.artifact.receipt.catalogueSHA256 == catalogue.manifestSHA256,
                          result.artifact.compilerReceiptJSON != nil else { throw CocoaError(.fileReadCorruptFile) }
                    report.completedAttempts.append(QualificationStep(name: "active-\(index)-gpio", seconds: ProcessInfo.processInfo.systemUptime - began,
                        capsuleSHA256: result.artifact.sha256, wasmLinearMemoryBytes: result.linearMemoryBytes))
                    try persist()
                } catch is CancellationError {
                    pending = nil
                    guard report.cancellation?.attempt == index else { throw CancellationError() }
                    report.cancellation?.outcome = "cancelled"
                    report.cancellation?.settledSeconds = ProcessInfo.processInfo.systemUptime - start
                    report.stage = "waiting-for-return"; try persist()
                    break
                }
            }
            guard report.cancellation?.outcome == "cancelled", report.cancellation?.lastProgress != "admitted" else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if workerCompilation {
                guard report.cancellation?.lastProgress == "compiling", report.cancellation?.compilingNotificationCount == 1,
                      report.cancellation?.compilePhaseBeganSeconds != nil else { throw CocoaError(.fileReadCorruptFile) }
            }
            status("Build cancellation settled. Return to this app after five seconds on Home.")
            try await waitForReturn()
            try await build(compiler, catalogue: catalogue, before: false)
            try check(); guard phase == "active" else { throw CocoaError(.fileReadCorruptFile) }
            report.status = "passed"; report.stage = "complete"; try persist()
            status("Active-call cancellation and foreground recovery checks passed")
        } catch {
            report.status = "failed"; report.error = String(error.localizedDescription.prefix(2048))
            try persist(); status("Active-call lifecycle check failed")
        }
        return journal
    }

    /// Exports only known baseline/fresh results; a canceled task's bytes are never exported.
    private func build(_ compiler: ManagedSketchCompiler, catalogue: ManagedCompilerCatalogue, before: Bool) async throws {
        let name = before ? "before-active-gpio" : "fresh-after-active-cancel-console"
        if !before { report.freshStartedSeconds = ProcessInfo.processInfo.systemUptime - start }
        report.stage = name; try persist()
        let began = ProcessInfo.processInfo.systemUptime
        let request = try QualificationChecks.request(before ? (workerSource ?? QualificationChecks.gpio) : QualificationChecks.console,
            name: name, revision: before ? 1 : 100, catalogue: catalogue)
        let result = try await compiler.build(request) { [weak self] value in
            if before { Task { @MainActor in self?.preflightProgress(value) } }
        }
        guard result.artifact.sha256 == (before ? QualificationChecks.gpioSHA : QualificationChecks.consoleSHA),
              result.artifact.receipt.firmwareBuildID == QualificationChecks.buildID,
              result.artifact.receipt.catalogueSHA256 == catalogue.manifestSHA256,
              result.artifact.compilerReceiptJSON != nil else { throw CocoaError(.fileReadCorruptFile) }
        try result.artifact.bytes.write(to: directory.appendingPathComponent(name + ".fms"), options: .withoutOverwriting)
        report.steps.append(QualificationStep(name: name, seconds: ProcessInfo.processInfo.systemUptime - began,
            capsuleSHA256: result.artifact.sha256, wasmLinearMemoryBytes: result.linearMemoryBytes))
        try persist()
    }
}
