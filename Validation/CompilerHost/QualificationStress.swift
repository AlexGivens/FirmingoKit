import Foundation
import Darwin
import FirmingoKit

/// Finite repeated public-API builds with self-process footprint samples; no board or other-process access.
@MainActor enum QualificationStress {
    /// One observed host-process footprint, which excludes WebKit child processes and missed sampling peaks.
    struct Sample: Encodable {
        /// Monotonic seconds since this run began.
        let seconds: Double
        /// Current process phys_footprint, in bytes, obtained through TASK_VM_INFO.
        let bytes: UInt64
        /// Last entered build or idle stage, without interpreting it as a WebKit execution phase.
        let stage: String
    }

    /// Durable repeated-build journal; interrupted/running journals are never accepted as successful runs.
    struct Report: Encodable {
        /// Separate schema for the stress host, preserving the existing six-check schema.
        let schema = 2
        /// Distinguishes this run from the original six-check qualification.
        let kind = "repeated-builds"
        /// Exact caller-selected correlation identifier.
        let runID: String
        /// Current runtime version, independent of deployment minimum.
        let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
        /// Only this qualification app's process, useful for explicit scoped termination/profiling.
        let hostProcessID = ProcessInfo.processInfo.processIdentifier
        /// Independently anchored prepared SDK/compiler package inputs.
        let context: QualificationContext
        /// Exact static firmware descriptor, without an installed-device association.
        let firmwareBuildID: String
        /// Explicit bounded number of alternating GPIO/console builds.
        let iterations: Int
        /// Running, failed or passed; only completed known artifacts can yield passed.
        var status = "running"
        /// Stage persisted before entering work; it does not prove an instruction-level interruption point.
        var stage = "resources"
        /// Completed, independently pinned artifacts only.
        var steps: [QualificationStep] = []
        /// Bounded self-process observations, copied into the journal at stage boundaries.
        var hostFootprintSamples: [Sample] = []
        /// Requested sampling interval; actor scheduling may delay observations.
        let sampleIntervalSeconds = 0.05
        /// Counts observations omitted after the fixed sample limit.
        var droppedSamples = 0
        /// Bounded error retained for incomplete work.
        var error: String?
        /// No board, association, installation or upload API is used.
        let deviceOperations = false
        /// Host footprint and worker linear memory are separate measurements, not an aggregate peak.
        let memoryScope = "Self-process TASK_VM_INFO phys_footprint samples and post-build WASM linear bytes; excludes WebKit children and unsampled peaks; no leak-free claim"
        /// Each public build retains the production deadline; this loop does not inject timeout behavior.
        let deadlineScope = "60-second production build deadline; 120-second loop admission bound; no forced deadline expiry"
    }

    /// Main-actor periodic recorder has explicit ownership, cancellation and a fixed maximum history.
    @MainActor private final class Recorder {
        /// Common monotonic origin for every sample.
        let start = ProcessInfo.processInfo.systemUptime
        /// Current caller-owned stage, never a private WebKit process identifier.
        var stage = "resources"
        /// At most 4,096 observations, so an interrupted loop cannot grow memory without bound.
        var samples: [Sample] = []
        /// Omitted observations remain observable rather than silently implying exhaustive sampling.
        var dropped = 0
        /// Any unavailable measurement makes the requested measurement run fail explicitly.
        var failure: String?
        /// Owned task canceled on every exit path.
        private var task: Task<Void, Never>?

        /// Starts finite-interval observation; samples never read another process or payload.
        func startSampling() {
            sample()
            task = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                    guard !Task.isCancelled else { return }
                    self?.sample()
                }
            }
        }

        /// Cancels observation without retaining a background operation after the run.
        func stop() { task?.cancel(); task = nil }

        /// Reads only this process's footprint; kernel failures are recorded rather than converted to zero.
        func sample() {
            guard failure == nil else { return }
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            guard let footprintOffset = MemoryLayout<task_vm_info_data_t>.offset(of: \.phys_footprint) else {
                failure = "Self-process footprint field layout unavailable"; return
            }
            let requiredCount = (footprintOffset + MemoryLayout<UInt64>.size) / MemoryLayout<integer_t>.size
            let capacity = Int(count)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            guard result == KERN_SUCCESS, Int(count) >= requiredCount, info.phys_footprint > 0 else {
                failure = "Self-process footprint unavailable: kernel result \(result), returned count \(count)"
                return
            }
            guard samples.count < 4096 else { dropped += 1; return }
            samples.append(Sample(seconds: ProcessInfo.processInfo.systemUptime - start, bytes: info.phys_footprint, stage: stage))
        }
    }

    /// Atomically records stage/observations; missing or partial output never becomes a passed journal.
    private static func persist(_ report: Report, at url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: url, options: .atomic)
    }

    /// Runs two to forty real builds, preserving immutable sources/receipts and a failed/running interruption journal.
    static func run(id: UUID, iterations: Int, status: (String) -> Void) async throws -> URL {
        guard (2...40).contains(iterations),
              let contextURL = Bundle.main.url(forResource: "qualification-context", withExtension: "json"),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let context = try JSONDecoder().decode(QualificationContext.self, from: Data(contentsOf: contextURL))
        let directory = documents.appendingPathComponent("CompilerQualification-" + id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let journal = directory.appendingPathComponent("report.json")
        guard !FileManager.default.fileExists(atPath: journal.path) else { throw CocoaError(.fileWriteFileExists) }
        var report = Report(runID: id.uuidString, context: context, firmwareBuildID: QualificationChecks.buildID, iterations: iterations)
        try persist(report, at: journal)
        let recorder = Recorder(); recorder.startSampling(); defer { recorder.stop() }
        do {
            let catalogue = try await ManagedCompilerCatalogue.loadBundled()
            guard catalogue.manifestSHA256 == "e341bfc0385fea9b2b026dc624daa26cdeac33286f4bb07243b37c1c31837d0e",
                  catalogue.firmwareBuilds.count == 1, try catalogue.build(id: QualificationChecks.buildID).apiAddress == 0x10022c9c else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let compiler = ManagedSketchCompiler(); try await compiler.verifyResources()
            for index in 1...iterations {
                try Task.checkCancellation()
                guard ProcessInfo.processInfo.systemUptime - recorder.start < 120 else { throw ManagedCompilerError.timedOut }
                let gpio = index % 2 == 1, name = "build-\(index)-" + (gpio ? "gpio" : "console")
                report.stage = name; recorder.stage = name
                report.hostFootprintSamples = recorder.samples; report.droppedSamples = recorder.dropped
                try persist(report, at: journal); status("Repeated compiler check \(index)/\(iterations)")
                let start = ProcessInfo.processInfo.systemUptime
                let request = try QualificationChecks.request(gpio ? QualificationChecks.gpio : QualificationChecks.console,
                    name: name, revision: UInt64(index), catalogue: catalogue)
                let result = try await compiler.build(request)
                guard result.artifact.sha256 == (gpio ? QualificationChecks.gpioSHA : QualificationChecks.consoleSHA),
                      result.artifact.receipt.firmwareBuildID == QualificationChecks.buildID,
                      result.artifact.receipt.catalogueSHA256 == catalogue.manifestSHA256,
                      result.artifact.compilerReceiptJSON != nil else { throw CocoaError(.fileReadCorruptFile) }
                report.steps.append(QualificationStep(name: name, seconds: ProcessInfo.processInfo.systemUptime - start,
                    capsuleSHA256: result.artifact.sha256, wasmLinearMemoryBytes: result.linearMemoryBytes))
                recorder.sample()
                if let failure = recorder.failure { throw NSError(domain: "CompilerQualification.Memory", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: failure]) }
            }
            report.stage = "idle-after-builds"; recorder.stage = report.stage
            report.hostFootprintSamples = recorder.samples; report.droppedSamples = recorder.dropped
            try persist(report, at: journal)
            try await Task.sleep(for: .seconds(1)); recorder.sample()
            if let failure = recorder.failure { throw NSError(domain: "CompilerQualification.Memory", code: 1,
                userInfo: [NSLocalizedDescriptionKey: failure]) }
            report.status = "passed"; report.stage = "complete"
            report.hostFootprintSamples = recorder.samples; report.droppedSamples = recorder.dropped
            try persist(report, at: journal); status("Repeated compiler checks passed")
        } catch {
            report.status = "failed"; report.error = String(error.localizedDescription.prefix(2048))
            report.hostFootprintSamples = recorder.samples; report.droppedSamples = recorder.dropped
            try persist(report, at: journal); status("Repeated compiler checks failed")
        }
        return journal
    }
}
