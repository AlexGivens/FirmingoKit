import Foundation
import FirmingoKit

/// Exact prepared-source provenance embedded by the host generator, separate from physical-device evidence.
struct QualificationContext: Codable {
    /// SHA-256 of the independently selected prepared SDK inventory.
    let preparedManifestSHA256: String
    /// Clean SDK commit recorded by that inventory.
    let sdkCommit: String
    /// Exact compiler package selected during SDK preparation.
    let consumerManifestSHA256: String
}

/// One measured host operation; observed worker memory is separate from total WebKit/app memory.
struct QualificationStep: Encodable {
    /// Stable case name retained in the exported journal.
    let name: String
    /// Actual elapsed monotonic seconds, including SDK verification and host startup for builds.
    let seconds: Double
    /// Exact capsule identity when this step produces an accepted artifact.
    let capsuleSHA256: String?
    /// Observed WASM linear bytes after execution; not peak host/process memory.
    let wasmLinearMemoryBytes: Int?
}

/// Incrementally persisted host-only evidence; running/failed journals never claim completion.
struct QualificationReport: Encodable {
    /// Journal schema, independent of compiler and firmware schemas.
    let schema = 1
    /// Safe unique run identifier and directory name.
    let runID: String
    /// Actual runtime OS, separate from the build deployment minimum.
    let operatingSystem: String
    /// Exact selected SDK/package context, never an inferred installed resident.
    let context: QualificationContext
    /// Exact static build selection used for all requests.
    let firmwareBuildID: String
    /// Last durable state: running, passed or failed.
    var status: String
    /// Current operation persisted before entering potentially failing host work.
    var stage: String
    /// Completed checks only; interrupted work is never appended as passed.
    var steps: [QualificationStep]
    /// Bounded local error for an incomplete run.
    var error: String?
    /// Qualification deliberately performs no device operation.
    let deviceOperations = false
    /// This host records worker bytes only; total process/child peaks require separate instrumentation.
    let memoryScope = "WASM linear bytes after build; no total app/WebKit peak claim"
    /// Public SDK deadline is unchanged; short injected native deadlines are tested separately.
    let deadlineScope = "60-second production deadline retained; deadline expiry not forced by this host"
}

/// Main-actor observer coordinates a real overlapping request and phase cancellation without blocking progress.
@MainActor private final class QualificationCancellation {
    /// Exact primary build to cancel after observing actual compiler progress.
    var task: Task<ManagedOfflineCompilationResult, Error>?
    /// One joined observation checks the shared actor's busy admission before cancellation.
    var observation: Task<Bool, Never>?
    /// Duplicate compiling notifications must not create repeated cancellation attempts.
    var requested = false
}

/// Public SDK checks shared by signed macOS, simulator and physical Apple-host runs; no device APIs are used.
@MainActor enum QualificationChecks {
    /// Exact experimental build from the independently checked Nano CI export.
    static let buildID = "c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f"
    /// Supported GPIO input, identical to separately recorded Node/SDK artifact vectors.
    private static let gpio = "void setup() { pinMode(6, 1); }\nvoid loop() { digitalWrite(6, 1); delay(10); }\n"
    /// A distinct supported console path; its output remains an unbound offline capsule.
    private static let console = "void setup() { Serial.println(\"ready\"); }\nvoid loop() { int c = Serial.read(); if (c >= 0) Serial.write(uint8_t(c)); }\n"
    /// Known exact capsule identities for the selected resident API.
    private static let gpioSHA = "958b861bbc18d4666ed03e6976b39b9fea4812409ad91a3501abbb9685a80d7d"
    /// Independent second capsule identity from the same source-built compiler.
    private static let consoleSHA = "b372c00edf4b60c662f73055685ed8764e9f8798fe9efbbafad04302549174c0"

    /// Serializes a complete atomic journal after each state change; partial writes cannot become successful JSON.
    private static func persist(_ report: QualificationReport, at url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: url, options: .atomic)
    }

    /// Creates one immutable request without inventing a physical-device identity or upload association.
    private static func request(_ source: String, name: String, revision: UInt64,
                                catalogue: ManagedCompilerCatalogue) throws -> ManagedOfflineBuildRequest {
        let snapshot = try SketchSourceSnapshot(documentID: UUID(), revision: revision, filename: name + ".ino", source: source)
        return try ManagedOfflineBuildRequest(snapshot: snapshot, catalogue: catalogue, firmwareBuildID: buildID)
    }

    /// Runs finite checks, persisting the last reached stage for crashes/termination and bounded error evidence for throws.
    static func run(id: UUID, status: (String) -> Void) async throws -> URL {
        guard let contextURL = Bundle.main.url(forResource: "qualification-context", withExtension: "json"),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let context = try JSONDecoder().decode(QualificationContext.self, from: Data(contentsOf: contextURL))
        let directory = documents.appendingPathComponent("CompilerQualification-" + id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let journal = directory.appendingPathComponent("report.json")
        guard !FileManager.default.fileExists(atPath: journal.path) else { throw CocoaError(.fileWriteFileExists) }
        var report = QualificationReport(runID: id.uuidString, operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            context: context, firmwareBuildID: buildID, status: "running", stage: "resources", steps: [])
        try persist(report, at: journal)
        do {
            status("Verifying bundled compiler")
            let catalogue = try await ManagedCompilerCatalogue.loadBundled()
            guard catalogue.manifestSHA256 == "e341bfc0385fea9b2b026dc624daa26cdeac33286f4bb07243b37c1c31837d0e",
                  catalogue.firmwareBuilds.count == 1, try catalogue.build(id: buildID).apiAddress == 0x10022c9c else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let compiler = ManagedSketchCompiler()
            let resourceStart = ProcessInfo.processInfo.systemUptime
            try await compiler.verifyResources()
            report.steps.append(QualificationStep(name: "resources", seconds: ProcessInfo.processInfo.systemUptime - resourceStart,
                capsuleSHA256: nil, wasmLinearMemoryBytes: nil))
            for (revision, name, source, expected) in [(UInt64(1), "cold-gpio", gpio, gpioSHA), (2, "warm-console", console, consoleSHA)] {
                report.stage = name; try persist(report, at: journal); status("Compiling " + name)
                let start = ProcessInfo.processInfo.systemUptime
                let result = try await compiler.build(request(source, name: name, revision: revision, catalogue: catalogue))
                guard result.artifact.sha256 == expected, result.artifact.receipt.firmwareBuildID == buildID,
                      result.artifact.receipt.catalogueSHA256 == catalogue.manifestSHA256,
                      result.artifact.compilerReceiptJSON != nil else { throw CocoaError(.fileReadCorruptFile) }
                report.steps.append(QualificationStep(name: name, seconds: ProcessInfo.processInfo.systemUptime - start,
                    capsuleSHA256: result.artifact.sha256, wasmLinearMemoryBytes: result.linearMemoryBytes))
                try result.artifact.bytes.write(to: directory.appendingPathComponent(name + ".fms"), options: .withoutOverwriting)
            }
            report.stage = "frontend-error"; try persist(report, at: journal); status("Checking compiler diagnostics")
            let errorStart = ProcessInfo.processInfo.systemUptime
            do {
                _ = try await compiler.build(request("void setup() { missingFunction(); }\nvoid loop() {}\n", name: "Syntax", revision: 3, catalogue: catalogue))
                throw CocoaError(.fileReadCorruptFile)
            } catch ManagedCompilerError.compilationFailed(let diagnostics) {
                guard diagnostics.contains(where: { $0.severity == .error && $0.filename == "Syntax.ino" }) else { throw CocoaError(.fileReadCorruptFile) }
            }
            report.steps.append(QualificationStep(name: "frontend-error", seconds: ProcessInfo.processInfo.systemUptime - errorStart,
                capsuleSHA256: nil, wasmLinearMemoryBytes: nil))

            report.stage = "busy-cancellation"; try persist(report, at: journal); status("Checking cancellation and busy admission")
            let cancelledRequest = try request(gpio, name: "Cancel", revision: 4, catalogue: catalogue)
            let control = QualificationCancellation(), cancelStart = ProcessInfo.processInfo.systemUptime
            let pending = Task {
                try await compiler.build(cancelledRequest) { phase in
                    if phase == .compiling {
                        Task { @MainActor in
                            guard !control.requested else { return }
                            control.requested = true
                            control.observation = Task { @MainActor in
                                var busy = false
                                do { _ = try await compiler.build(cancelledRequest) }
                                catch ManagedCompilerError.busy { busy = true }
                                catch { /* Any other outcome fails this check below. */ }
                                control.task?.cancel()
                                return busy
                            }
                        }
                    }
                }
            }
            control.task = pending
            var cancelled = false
            do { _ = try await pending.value }
            catch is CancellationError { cancelled = true }
            guard let observation = control.observation, await observation.value, cancelled else { throw CocoaError(.fileReadCorruptFile) }
            report.steps.append(QualificationStep(name: "busy-cancellation", seconds: ProcessInfo.processInfo.systemUptime - cancelStart,
                capsuleSHA256: nil, wasmLinearMemoryBytes: nil))
            report.stage = "fresh-after-cancellation"; try persist(report, at: journal); status("Checking fresh build")
            let freshStart = ProcessInfo.processInfo.systemUptime
            let fresh = try await compiler.build(request(gpio, name: "Fresh", revision: 5, catalogue: catalogue))
            guard fresh.artifact.sha256 == gpioSHA else { throw CocoaError(.fileReadCorruptFile) }
            report.steps.append(QualificationStep(name: "fresh-after-cancellation", seconds: ProcessInfo.processInfo.systemUptime - freshStart,
                capsuleSHA256: fresh.artifact.sha256, wasmLinearMemoryBytes: fresh.linearMemoryBytes))
            report.status = "passed"; report.stage = "complete"; try persist(report, at: journal)
            status("All compiler checks passed")
            return journal
        } catch {
            report.status = "failed"; report.error = String(error.localizedDescription.prefix(2048))
            try persist(report, at: journal)
            status("Compiler checks failed: " + (report.error ?? "Unknown error"))
            return journal
        }
    }
}
