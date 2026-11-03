import Foundation
import Observation
import FirmingoKit

/// App-owned finite compiler scenarios; production SDK behavior and timers are never replaced.
@Observable @MainActor final class WorkbenchCompilerExercise {
    /// Explicit second UI action after lifecycle preflight/calibration.
    private(set) var ready = false
    /// Bounded running/terminal observations, persisted through the parent engine's journal gate.
    private var evidence: WorkbenchExerciseEvidence
    /// Exact public SDK boundary shared with all prior scenarios.
    private let backend: any WorkbenchCompilerBackend
    /// Static descriptor selected before admission.
    private let buildID: String
    /// Parent journal callback; throws prevent subsequent work.
    private let save: (WorkbenchExerciseEvidence) throws -> Void
    /// Parent event/artifact callback; all UI and CLI observations share it.
    private let emit: (String, String, WorkbenchReport.Artifact?) throws -> Void
    /// One run-relative monotonic clock; injectable only in deterministic package tests.
    private let now: () -> Double
    /// Fixed conversion from synchronous SDK uptime observations to the run clock.
    private let uptimeOrigin: Double
    /// Actual most recent aggregate app scene, unknown until SwiftUI delivers it.
    private var scene: String
    /// Exact current child call; cancellation must settle before fresh admission.
    private var pending: Task<WorkbenchReport.Artifact, Error>?
    /// Current synchronous SDK callback buffer; replaced for every call.
    private var probe: WorkbenchCompilerProbe?
    /// Whether this host can observe real foreground changes; CLI has process-only deadline scope.
    private let observesScenes: Bool
    /// Scene/sampling/persistence errors invalidate the entire exercise.
    private var recordingError: Error?
    /// Tracks which request is eligible for interruption evidence.
    private var interrupted = false
    /// The first background event after the explicit waiting/interruption boundary.
    private var background: Double?
    /// True only after a later real active event with a sufficient background interval.
    private var returned = false
    /// Scene transitions are accepted only after a known baseline and explicit boundary.
    private var observingReturn = false
    /// Last periodic memory sample time, independent of progress notifications.
    private var sampledAt = -Double.infinity

    /// Captures pure orchestration boundaries; creates no web host or SDK operation.
    init(kind: String, backend: any WorkbenchCompilerBackend, buildID: String, scene: String, observesScenes: Bool,
         now: @escaping () -> Double, save: @escaping (WorkbenchExerciseEvidence) throws -> Void,
         emit: @escaping (String, String, WorkbenchReport.Artifact?) throws -> Void) {
        evidence = .init(kind: kind); self.backend = backend; self.buildID = buildID
        self.scene = scene; self.observesScenes = observesScenes; self.now = now; self.save = save; self.emit = emit
        uptimeOrigin = ProcessInfo.processInfo.systemUptime - now()
        evidence.sceneObservationScope = observesScenes ? "Actual aggregate SwiftUI app scenes; no suspension claim" : "Launch process only; no foreground/background claim"
    }
    /// Called only by an explicit UI button; normal activation never starts the interruption attempt.
    func begin(origin: WorkbenchExerciseEvidence.StartOrigin = .manualUI) throws {
        guard ready, scene == "active", evidence.manuallyStartedSeconds == nil else {
            throw WorkbenchFailure("The lifecycle check is not ready for explicit start.")
        }
        var next = evidence; next.manuallyStartedSeconds = now(); next.startOrigin = origin
        try save(next); evidence = next; ready = false
    }
    /// Accepts only actual app-scene delivery; CLI requests have no scene injection command.
    func recordScene(_ phase: String) {
        guard ["active", "inactive", "background"].contains(phase), phase != scene else { return }
        scene = phase
        do {
            guard evidence.scenes.count < 32 else { throw WorkbenchFailure("Scene observation bound exceeded.") }
            evidence.scenes.append(.init(seconds: now(), phase: phase))
            if observingReturn {
                if phase == "background", background == nil { background = now() }
                if phase == "active", let background {
                    guard now() - background >= 3 else { throw WorkbenchFailure("Background interval was shorter than three seconds.") }
                    returned = true
                }
            }
            if interrupted, phase == "inactive", evidence.kind.hasPrefix("host.lifecycle"), pending != nil,
               evidence.cancelRequestedSeconds == nil {
                try captureProgress()
                evidence.cancelRequestedSeconds = now(); try save(evidence); pending?.cancel()
            } else if evidence.kind == "compiler.deadline", phase != "active" {
                throw WorkbenchFailure("Foreground changed during the deadline check; cancellation cannot qualify timeout.")
            } else if evidence.kind.hasPrefix("host.lifecycle"), !observingReturn, phase != "active" {
                throw WorkbenchFailure("Lifecycle preflight lost foreground before it was ready.")
            }
            try save(evidence)
        } catch { recordingError = error; pending?.cancel() }
    }
    /// Executes the closed scenario using the same compiler instance and bounded app-owned evidence.
    func run() async throws {
        try save(evidence)
        if evidence.kind == "compiler.stress" {
            for index in 0..<20 {
                try check(limit: 120)
                _ = try await build(index.isMultiple(of: 2) ? .gpio : .console)
                try check(limit: 120)
            }
            try emit("idle-after-builds", "Twenty exact builds completed; sampling one second of idle host footprint.", nil)
            try await Task.sleep(for: .seconds(1)); try check(limit: 120); try sample(); try save(evidence)
            return
        }
        let lifecycle = evidence.kind.hasPrefix("host.lifecycle")
        let worker = evidence.kind == "host.lifecycle-worker"
        if lifecycle || (evidence.kind == "compiler.deadline" && observesScenes) {
            guard scene == "active" else { throw WorkbenchFailure("A real active app scene is required before this scenario starts.") }
            evidence.scenes.append(.init(seconds: now(), phase: scene))
        }
        let baseline = try await build(worker ? .worker : .gpio)
        if worker {
            let compiling = baseline.filter { $0.phase == "compiling" }
            guard compiling.count == 2, (4...55).contains(compiling[1].seconds - compiling[0].seconds) else {
                throw WorkbenchFailure("The pinned worker workload needs a four-to-fifty-five-second source calibration.")
            }
            evidence.calibratedCompileSeconds = compiling[1].seconds - compiling[0].seconds
        }
        if evidence.kind == "host.lifecycle" {
            observingReturn = true
            try emit("waiting-for-background", "Go Home, wait five seconds, then reopen Workbench. No OS suspension is inferred.", nil)
            try await waitForReturn()
        } else {
            if lifecycle {
                try save(evidence)
                ready = true
                try emit("waiting-for-start", "Tap Start lifecycle interruption, wait one second, then go Home for five seconds and return.", nil)
                while evidence.manuallyStartedSeconds == nil { try check(); try await Task.sleep(for: .milliseconds(50)) }
                observingReturn = true
            }
            let input: WorkbenchCompilerInput = evidence.kind == "compiler.deadline" ? .deadline : (lifecycle ? .worker : .gpio)
            if input == .deadline || input == .worker {
                evidence.workloadSHA256 = input == .deadline ? WorkbenchWorkload.deadlineSHA256 : WorkbenchWorkload.workerSHA256
                evidence.workloadBytes = input == .deadline ? 227646 : 227505
            }
            if input == .deadline { evidence.runtimeDeadlineSeconds = 60 }
            interrupted = true; evidence.startedSeconds = now(); try save(evidence)
            do {
                _ = try await build(input)
                evidence.outcome = "artifactReturned"; try save(evidence)
                throw WorkbenchFailure("The interrupted request returned an artifact; this scenario cannot pass.")
            } catch ManagedCompilerError.timedOut {
                evidence.outcome = "timedOut"
                guard evidence.kind == "compiler.deadline" else { throw ManagedCompilerError.timedOut }
            } catch is CancellationError {
                evidence.outcome = "cancelled"
                guard evidence.cancelRequestedSeconds != nil, evidence.kind != "compiler.deadline" else { throw CancellationError() }
            }
            evidence.settledSeconds = now(); interrupted = false; try save(evidence)
            try check()
            let compiling = evidence.progress.filter { $0.phase == "compiling" }
            guard !evidence.progress.isEmpty else { throw WorkbenchFailure("Inactivity preceded all actual SDK progress.") }
            if evidence.kind != "host.lifecycle-active" {
                guard evidence.progress.last?.phase == "compiling", compiling.count == 1 else {
                throw WorkbenchFailure("Interruption must occur in the first observed source-compilation interval.")
                }
            }
            if evidence.kind == "compiler.deadline" {
                guard let began = evidence.startedSeconds, let settled = evidence.settledSeconds,
                      (60...75).contains(settled - began), evidence.cancelRequestedSeconds == nil else {
                    throw WorkbenchFailure("Expected typed expiry of the unchanged sixty-second runtime deadline.")
                }
            } else if evidence.kind == "compiler.cancellation" {
                guard evidence.busyObserved else { throw WorkbenchFailure("The overlapping SDK request did not return typed busy.") }
            } else {
                guard let requested = evidence.cancelRequestedSeconds, let last = evidence.progress.last, requested >= last.seconds else {
                    throw WorkbenchFailure("Inactivity preceded observed SDK work; rerun explicitly.")
                }
                try emit("waiting-for-return", "Cancellation settled. Return after five seconds on Home; no commit or build is replayed.", nil)
                try await waitForReturn()
            }
        }
        evidence.freshStartedSeconds = now(); try save(evidence)
        _ = try await build(.console)
        try check()
        if lifecycle || (evidence.kind == "compiler.deadline" && observesScenes) {
            guard scene == "active" else { throw WorkbenchFailure("The final known build must finish in the foreground.") }
        }
    }
    /// Checks a finite observation window and propagates parent cancellation/recording failures.
    private func check(limit: Double = 600) throws {
        if let recordingError { throw recordingError }
        try Task.checkCancellation()
        guard now() <= limit else { throw WorkbenchFailure("Workbench scenario observation deadline exceeded.") }
    }
    /// Waits for actual scene delivery, not an artificial delay standing in for backgrounding.
    private func waitForReturn() async throws {
        while !returned { try check(); try await Task.sleep(for: .milliseconds(50)) }
        guard scene == "active" else { throw WorkbenchFailure("The app has not returned active.") }
        observingReturn = false
    }
    /// Converts synchronous per-call progress to the shared monotonic origin; stale probes never cross calls.
    private func captureProgress() throws {
        guard let probe else { return }
        evidence.progress = try probe.snapshot().map { .init(phase: $0.phase, seconds: max(0, $0.seconds - uptimeOrigin)) }
    }
    /// Bounds optional self-process measurements and makes omitted samples explicit.
    private func sample() throws {
        guard evidence.kind == "compiler.stress", now() - sampledAt >= 0.25 else { return }
        sampledAt = now()
        let bytes = try WorkbenchFootprint.bytes()
        if evidence.samples.count < 128 { evidence.samples.append(.init(seconds: now(), bytes: bytes)) }
        else { evidence.droppedSamples += 1 }
    }
    /// Performs one owned SDK call, settles its monitor on every path and never exports interrupted bytes.
    @discardableResult private func build(_ input: WorkbenchCompilerInput) async throws -> [WorkbenchCompilerProbe.Point] {
        try check(); try emit("compile-" + input.rawValue, "Executing the exact SDK compiler input: " + input.rawValue, nil)
        let probe = WorkbenchCompilerProbe(); self.probe = probe
        let began = now(), qualifying = interrupted
        let call = Task { try await backend.compile(input, buildID: buildID, probe: probe) }; pending = call
        let cancellationObserver = Task { @MainActor in
            guard qualifying, evidence.kind == "compiler.cancellation" else { return }
            do {
                try await probe.waitForSourceCompilation()
                try captureProgress()
                do { try await backend.verifyResources(); throw WorkbenchFailure("An overlapping SDK operation unexpectedly succeeded.") }
                catch ManagedCompilerError.busy { evidence.busyObserved = true }
                evidence.cancelRequestedSeconds = now(); try save(evidence); call.cancel()
            } catch is CancellationError { return }
            catch { recordingError = error; call.cancel() }
        }
        let monitor = Task { @MainActor in
            do {
                while !Task.isCancelled {
                    let previous = (evidence.progress.count, evidence.samples.count, evidence.droppedSamples)
                    if qualifying {
                        try captureProgress()
                    }
                    try sample()
                    if previous != (evidence.progress.count, evidence.samples.count, evidence.droppedSamples) { try save(evidence) }
                    try await Task.sleep(for: .milliseconds(50))
                }
            } catch is CancellationError { return }
            catch { recordingError = error; call.cancel() }
        }
        let result: Result<WorkbenchReport.Artifact, Error> = await withTaskCancellationHandler {
            await call.result
        } onCancel: { call.cancel() }
        probe.finish(); cancellationObserver.cancel(); monitor.cancel()
        await cancellationObserver.value; await monitor.value; pending = nil
        if qualifying { try captureProgress() }
        self.probe = nil
        try save(evidence)
        if let recordingError { throw recordingError }
        let artifact = try result.get()
        try Task.checkCancellation()
        if qualifying { return try probe.snapshot() }
        guard evidence.builds.count < 40 else { throw WorkbenchFailure("Build observation bound exceeded.") }
        evidence.builds.append(.init(index: evidence.builds.count + 1, input: input.rawValue, sha256: artifact.sha256,
            receiptSHA256: WorkbenchWorkload.digest(artifact.receiptJSON), seconds: now() - began,
            wasmLinearMemoryBytes: artifact.wasmLinearMemoryBytes))
        try save(evidence)
        try emit("artifact-" + input.rawValue, "Expected and observed capsule SHA-256: " + artifact.sha256, artifact)
        return try probe.snapshot()
    }
}
