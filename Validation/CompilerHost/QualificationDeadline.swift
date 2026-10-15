import Foundation
import CryptoKit
import FirmingoKit

/// Exercises the unchanged public 60-second deadline with real frontend work and same-instance recovery.
@MainActor final class QualificationDeadline {
    /// A native progress observation, without a claim about the worker instruction pointer.
    struct Progress: Encodable {
        /// Public SDK phase, including repeated verification/source-wrapper compile notifications.
        let phase: String
        /// Monotonic time relative to this run's origin.
        let seconds: Double
    }

    /// Separate evidence schema; incomplete or interrupted runs never qualify timeout recovery.
    struct Report: Encodable {
        /// Version of this deadline-only host journal.
        let schema = 6
        /// Distinguishes a real production deadline from injected timeout fixtures.
        let kind = "production-deadline-fresh-recovery"
        /// Exact launch identity selected independently by the runner.
        let runID: String
        /// Anchored prepared SDK and consumer identities.
        let context: QualificationContext
        /// Static target selection, with no installed-image claim.
        let firmwareBuildID: String
        /// Actual runtime OS, separate from deployment minimum.
        let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
        /// Must match the independently launched app process.
        let hostProcessID = ProcessInfo.processInfo.processIdentifier
        /// Passed only after typed timeout and a successful fresh build.
        var status = "running"
        /// Persisted before entering potentially failing work.
        var stage = "waiting-for-active"
        /// Real view-delivered scene phases, bounded at 64.
        var events: [QualificationLifecycle.Event] = []
        /// Known baseline GPIO and fresh console output only.
        var steps: [QualificationStep] = []
        /// Bounded actual progress for the deadline request only.
        var progress: [Progress] = []
        /// Public SDK default; no shortened or injected timeout is used.
        let runtimeDeadlineSeconds = 60
        /// Eligibility bound for this foreground test, not a performance guarantee.
        let observationLimitSeconds = 180
        /// Exact derived source identity, below the existing source cap.
        let workloadSHA256 = "bde5df426deb79fd8277abfd5b406cf1288b28b307646b62bc5ee1028cce26eb"
        /// Bounded source byte count verified before admission.
        let workloadBytes = 227646
        /// Actual public call admission relative to the run origin.
        var deadlineStartedSeconds: Double?
        /// Actual return after typed timeout/cleanup.
        var deadlineSettledSeconds: Double?
        /// Set only by catching ManagedCompilerError.timedOut.
        var outcome = "pending"
        /// Returning any artifact from the deadline request fails the run.
        var artifactReturned = false
        /// A successful foreground rebuild must follow timeout settlement.
        var freshStartedSeconds: Double?
        /// No board API or deployment operation is used.
        let deviceOperations = false
        /// Preserves bounded failure evidence rather than converting failures to passes.
        var error: String?
    }

    /// Shared monotonic origin for all event and operation observations.
    private let start = ProcessInfo.processInfo.systemUptime
    /// New run directory owned by this app.
    private let directory: URL
    /// Atomic running/terminal journal path.
    private let journal: URL
    /// Exact derived frontend workload used only for this qualification mode.
    private let source: String
    /// Current bounded durable observations.
    private var report: Report
    /// Last actual scene phase; unknown is not treated as foreground.
    private var phase = "unknown"
    /// Scene/report failures are checked by the async run owner.
    private var recordingError: Error?
    /// Exact pending timeout request; inactivity cancels it and invalidates the test.
    private var pending: Task<ManagedOfflineCompilationResult, any Error>?

    /// Loads pinned source/provenance and refuses an existing run directory.
    init(id: UUID, phase: String) throws {
        guard let contextURL = Bundle.main.url(forResource: "qualification-context", withExtension: "json"),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let context = try JSONDecoder().decode(QualificationContext.self, from: Data(contentsOf: contextURL))
        source = try Self.workload()
        directory = documents.appendingPathComponent("CompilerQualification-" + id.uuidString, isDirectory: true)
        journal = directory.appendingPathComponent("report.json")
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw CocoaError(.fileWriteFileExists) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        report = Report(runID: id.uuidString, context: context, firmwareBuildID: QualificationChecks.buildID)
        try persist(); record(phase: phase)
    }

    /// Repeats the pinned mix evaluation sixteen times per seed, retaining all expected values and runtime code.
    private static func workload() throws -> String {
        let original = try QualificationActiveLifecycle.loadWorkerSource()
        let old = """
        constexpr unsigned qualification_mix(unsigned x) {
          for (unsigned i = 0; i < 1024; ++i) x = (x * 1664525u + 1013904223u) ^ (x >> 13);
          return x;
        }
        """
        let replacement = """
        constexpr unsigned qualification_mix(unsigned seed) {
          unsigned result = 0;
          for (unsigned repetition = 0; repetition < 16; ++repetition) {
            unsigned x = seed;
            for (unsigned i = 0; i < 1024; ++i) x = (x * 1664525u + 1013904223u) ^ (x >> 13);
            result = x;
          }
          return result;
        }
        """
        guard original.components(separatedBy: old).count == 2 else { throw CocoaError(.fileReadCorruptFile) }
        let result = original.replacingOccurrences(of: old, with: replacement)
        let bytes = Data(result.utf8)
        guard bytes.count == 227646,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == "bde5df426deb79fd8277abfd5b406cf1288b28b307646b62bc5ee1028cce26eb" else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return result
    }

    /// Records real phases; losing foreground after work starts invalidates this deadline-only test.
    func record(phase: String) {
        guard report.status == "running", ["active", "inactive", "background"].contains(phase), self.phase != phase else { return }
        self.phase = phase
        do {
            guard report.events.count < 64 else { throw CocoaError(.coderInvalidValue) }
            report.events.append(QualificationLifecycle.Event(seconds: elapsed, phase: phase, stage: report.stage))
            if report.stage != "waiting-for-active", phase != "active" {
                recordingError = CocoaError(.userCancelled)
                pending?.cancel()
            }
            try persist()
        } catch { recordingError = error; pending?.cancel() }
    }

    /// Relative uptime never depends on wall-clock/date changes.
    private var elapsed: Double { ProcessInfo.processInfo.systemUptime - start }

    /// Writes a complete atomic journal; no successful prefix substitutes for the terminal result.
    private func persist() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: journal, options: .atomic)
    }

    /// Validates bounded foreground admission after any asynchronous work.
    private func check() throws {
        if let recordingError { throw recordingError }
        guard phase == "active", elapsed <= 180 else { throw CocoaError(.userCancelled) }
        try Task.checkCancellation()
    }

    /// Accepts only finite current-call progress and records it before another phase can arrive.
    private func progress(_ value: ManagedCompilationPhase) {
        guard report.status == "running", report.stage == "deadline", pending != nil else { return }
        do {
            guard report.progress.count < 8 else { throw CocoaError(.coderInvalidValue) }
            report.progress.append(Progress(phase: value.rawValue, seconds: elapsed)); try persist()
        } catch { recordingError = error; pending?.cancel() }
    }

    /// Builds and independently checks known bytes/receipts through the same public compiler instance.
    private func known(_ text: String, name: String, revision: UInt64, expected: String,
                       catalogue: ManagedCompilerCatalogue, compiler: ManagedSketchCompiler) async throws {
        try check(); report.stage = name; try persist()
        let began = elapsed
        let result = try await compiler.build(QualificationChecks.request(text, name: name, revision: revision, catalogue: catalogue))
        try check()
        guard result.artifact.sha256 == expected, result.artifact.receipt.firmwareBuildID == QualificationChecks.buildID,
              result.artifact.receipt.catalogueSHA256 == catalogue.manifestSHA256,
              result.artifact.compilerReceiptJSON != nil else { throw CocoaError(.fileReadCorruptFile) }
        try result.artifact.bytes.write(to: directory.appendingPathComponent(name + ".fms"), options: .withoutOverwriting)
        report.steps.append(QualificationStep(name: name, seconds: elapsed - began,
            capsuleSHA256: result.artifact.sha256, wasmLinearMemoryBytes: result.linearMemoryBytes)); try persist()
    }

    /// Requires actual timedOut without cancellation or artifact, then a fresh known build after cleanup.
    func run(status: (String) -> Void) async throws -> URL {
        do {
            while phase != "active", elapsed < 30 { try await Task.sleep(for: .milliseconds(100)) }
            try check(); status("Checking deadline baseline")
            let catalogue = try await ManagedCompilerCatalogue.loadBundled()
            guard catalogue.manifestSHA256 == "e341bfc0385fea9b2b026dc624daa26cdeac33286f4bb07243b37c1c31837d0e" else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let compiler = ManagedSketchCompiler()
            try await known(QualificationChecks.gpio, name: "before-deadline-gpio", revision: 1,
                expected: QualificationChecks.gpioSHA, catalogue: catalogue, compiler: compiler)
            try check(); report.stage = "deadline"; report.deadlineStartedSeconds = elapsed; try persist()
            status("Testing the 60-second deadline; keep this app open")
            let request = try QualificationChecks.request(source, name: "Deadline", revision: 2, catalogue: catalogue)
            let task = Task { [weak self] in
                try await compiler.build(request) { [weak self] value in
                    Task { @MainActor [weak self] in self?.progress(value) }
                }
            }
            pending = task
            do {
                _ = try await task.value
                report.artifactReturned = true
                throw CocoaError(.fileReadCorruptFile)
            } catch ManagedCompilerError.timedOut {
                report.outcome = "timedOut"; report.deadlineSettledSeconds = elapsed
            }
            pending = nil
            try check()
            guard report.progress.last?.phase == "compiling", report.progress.filter({ $0.phase == "compiling" }).count == 1,
                  let began = report.deadlineStartedSeconds, let settled = report.deadlineSettledSeconds,
                  (60...75).contains(settled - began) else { throw CocoaError(.fileReadCorruptFile) }
            report.stage = "after-timeout"; try persist()
            report.freshStartedSeconds = elapsed; status("Checking fresh build after timeout")
            try await known(QualificationChecks.console, name: "fresh-after-deadline-console", revision: 3,
                expected: QualificationChecks.consoleSHA, catalogue: catalogue, compiler: compiler)
            report.status = "passed"; report.stage = "complete"; try persist()
            status("Deadline and fresh-build checks passed")
        } catch {
            pending?.cancel(); pending = nil
            report.status = "failed"; report.error = String(error.localizedDescription.prefix(2048)); try persist()
            status("Deadline check failed: " + (report.error ?? "Unknown error"))
        }
        return journal
    }
}
