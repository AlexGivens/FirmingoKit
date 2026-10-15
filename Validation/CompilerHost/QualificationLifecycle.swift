import Foundation
import FirmingoKit

/// Opt-in idle background/foreground observation through real scene events, with known builds on either side.
@MainActor final class QualificationLifecycle {
    /// One scene observation, never a claim that the OS actually suspended this process.
    struct Event: Encodable {
        /// Monotonic seconds since this run began, including time away from the foreground.
        let seconds: Double
        /// Active, inactive or background as delivered by the host's SwiftUI scene.
        let phase: String
        /// Durable test stage at observation time.
        let stage: String
    }

    /// Separate schema so original six-check and repeated-build journals retain their meaning.
    struct Report: Encodable {
        /// Version of the idle lifecycle journal only.
        let schema = 3
        /// Does not claim interruption of active compilation or memory-pressure recovery.
        let kind = "idle-background-return"
        /// Fresh caller-selected uppercase UUID, never reused on disk.
        let runID: String
        /// Exact source/package identities supplied by the anchored generator.
        let context: QualificationContext
        /// Experimental static resident descriptor; no installed-device evidence.
        let firmwareBuildID: String
        /// Current runtime, independent of declared deployment minimum.
        let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
        /// Identifies the same app process before and after the observed transition.
        let hostProcessID = ProcessInfo.processInfo.processIdentifier
        /// Running, failed or passed; only two known builds and real scene events can pass.
        var status = "running"
        /// Written before work so interrupted runs remain incomplete.
        var stage = "waiting-for-active"
        /// At most 64 scene observations; excess events fail rather than truncate evidence.
        var events: [Event] = []
        /// Completed known artifacts only.
        var steps: [QualificationStep] = []
        /// Fixed manual-action admission bound; production build deadlines remain unchanged.
        let observationLimitSeconds = 600
        /// Requires a meaningful interval between background and return observations.
        let minimumBackgroundSeconds = 3
        /// No background execution assertion, extension, task grant or board workflow is requested.
        let deviceOperations = false
        /// Bounded failure text; a missing event or relaunch can never become success.
        var error: String?
    }

    /// Shared monotonic origin for phase and build observations.
    private let start = ProcessInfo.processInfo.systemUptime
    /// This run's new private results directory.
    private let directory: URL
    /// Atomic journal within this app's own Documents container.
    private let journal: URL
    /// Main-actor-owned evidence, updated synchronously on scene changes.
    private var report: Report
    /// Last real scene phase; unknown until the view supplies an observation.
    private var phase: String
    /// Preserve recording errors for the owning async operation to surface.
    private var recordingError: Error?

    /// Creates a fresh correlated journal; existing results are never overwritten.
    init(id: UUID, phase: String) throws {
        guard let contextURL = Bundle.main.url(forResource: "qualification-context", withExtension: "json"),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let context = try JSONDecoder().decode(QualificationContext.self, from: Data(contentsOf: contextURL))
        directory = documents.appendingPathComponent("CompilerQualification-" + id.uuidString, isDirectory: true)
        journal = directory.appendingPathComponent("report.json")
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw CocoaError(.fileWriteFileExists) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        report = Report(runID: id.uuidString, context: context, firmwareBuildID: QualificationChecks.buildID); self.phase = "unknown"
        try persist()
        record(phase: phase)
    }

    /// Records actual view-delivered scene changes, including background events before suspension is possible.
    func record(phase: String) {
        guard report.status == "running", ["active", "inactive", "background"].contains(phase), self.phase != phase else { return }
        self.phase = phase
        do {
            guard report.events.count < 64 else { throw CocoaError(.coderInvalidValue) }
            report.events.append(Event(seconds: ProcessInfo.processInfo.systemUptime - start, phase: phase, stage: report.stage))
            try persist()
        } catch { recordingError = error }
    }

    /// Persists only complete JSON, without requesting extended background execution.
    private func persist() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: journal, options: .atomic)
    }

    /// Checks real event progress with bounded polling; sleeping does not keep an iOS app running in the background.
    private func waitForReturn(after index: Int) async throws {
        while true {
            try Task.checkCancellation()
            if let recordingError { throw recordingError }
            guard ProcessInfo.processInfo.systemUptime - start < 600 else { throw ManagedCompilerError.timedOut }
            let events = Array(report.events.dropFirst(index))
            if let background = events.firstIndex(where: { $0.phase == "background" }),
               let active = events.dropFirst(background + 1).first(where: { $0.phase == "active" }) {
                guard active.seconds - events[background].seconds >= 3, phase == "active" else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Uses one public compiler instance for both sides of an idle transition; active-build interruption stays untested.
    func run(status: (String) -> Void) async throws -> URL {
        do {
            while phase != "active" {
                if let recordingError { throw recordingError }
                guard ProcessInfo.processInfo.systemUptime - start < 10 else { throw ManagedCompilerError.timedOut }
                try await Task.sleep(for: .milliseconds(100))
            }
            let catalogue = try await ManagedCompilerCatalogue.loadBundled()
            guard catalogue.manifestSHA256 == "e341bfc0385fea9b2b026dc624daa26cdeac33286f4bb07243b37c1c31837d0e",
                  catalogue.firmwareBuilds.count == 1, try catalogue.build(id: QualificationChecks.buildID).apiAddress == 0x10022c9c else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let compiler = ManagedSketchCompiler(); try await compiler.verifyResources()
            try await build(compiler, catalogue: catalogue, before: true)
            guard phase == "active" else { throw CocoaError(.fileReadCorruptFile) }
            report.stage = "waiting-for-background"; try persist()
            let index = report.events.count
            status("Idle lifecycle check ready. Go Home, wait five seconds, then return to this app.")
            try await waitForReturn(after: index)
            try await build(compiler, catalogue: catalogue, before: false)
            if let recordingError { throw recordingError }
            guard phase == "active" else { throw CocoaError(.fileReadCorruptFile) }
            report.status = "passed"; report.stage = "complete"; try persist()
            status("Idle background/return compiler checks passed")
        } catch {
            report.status = "failed"; report.error = String(error.localizedDescription.prefix(2048))
            try persist(); status("Idle background/return compiler checks failed")
        }
        return journal
    }

    /// Builds and exports a pinned artifact with an independently meaningful source before/after the transition.
    private func build(_ compiler: ManagedSketchCompiler, catalogue: ManagedCompilerCatalogue, before: Bool) async throws {
        let name = before ? "before-background-gpio" : "after-foreground-console"
        report.stage = name; try persist()
        let began = ProcessInfo.processInfo.systemUptime
        let request = try QualificationChecks.request(before ? QualificationChecks.gpio : QualificationChecks.console,
            name: name, revision: before ? 1 : 2, catalogue: catalogue)
        let result = try await compiler.build(request)
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
