import Foundation
import Testing
import FirmingoKit
@testable import FirmingoWorkbenchCore

/// Deterministic app boundary; these injected responses are never hardware/compiler qualification evidence.
@MainActor private final class Backend: WorkbenchCompilerBackend {
    /// Counts metadata work to establish that validation/durability gates precede SDK access.
    var calls = 0
    /// Optional actual typed resource failure, rather than a fake successful compiler.
    var resourceError: ManagedCompilerResourceError?
    /// Explicit test-controlled suspension for busy/cancel ordering.
    var suspended: CheckedContinuation<Void, Never>?
    /// Whether resource verification must await the test's release.
    var wait = false
    /// Returns display metadata only; no synthetic deployable descriptor or device is created.
    func catalogue() async throws -> WorkbenchCatalogue {
        calls += 1
        return .init(sha256: String(repeating: "a", count: 64), builds: [
            .init(id: WorkbenchCompilerInput.buildID, board: "nano_rp2040_connect", profile: "nano-managed-v1")])
    }
    /// Suspends without time-based sleeps; the test always releases the continuation.
    func verifyResources() async throws {
        calls += 1
        if wait { await withCheckedContinuation { suspended = $0 } }
        try Task.checkCancellation()
        if let resourceError { throw resourceError }
    }
    /// Compilation is deliberately unavailable in injected tests, keeping real WASM checks explicit.
    func compile(_ input: WorkbenchCompilerInput, buildID: String) async throws -> WorkbenchReport.Artifact {
        calls += 1; throw WorkbenchFailure("No simulated successful compilation.")
    }
}

/// Synchronous storage failure model proves that evidence is an execution gate.
@MainActor private final class Store: WorkbenchRunStore {
    /// Requests already durably reserved; replay is rejected across later engine calls.
    var ids: Set<UUID> = []
    /// Ordered snapshots actually acknowledged by this fake storage boundary.
    var reports: [WorkbenchReport] = []
    /// Injects admission failure before any backend operation.
    var refuseBegin = false
    /// Injects failure whenever a terminal pass would be published.
    var refusePass = false
    /// Creates one checked reservation or fails closed.
    func begin(_ report: WorkbenchReport) throws {
        guard !refuseBegin, ids.insert(report.id).inserted else { throw WorkbenchFailure("Journal admission failed.") }
        reports.append(report)
    }
    /// A failed save never acknowledges a terminal pass.
    func save(_ report: WorkbenchReport) throws {
        if refusePass && report.status == .passed { throw WorkbenchFailure("Journal pass save failed.") }
        reports.append(report)
    }
}

/// Closed command admission rejects future/device flags before the app constructs a run.
@Test func malformedRequestsCannotExpandTheOperationSurface() throws {
    let id = UUID().uuidString
    for json in ["{\"schema\":2,\"requestID\":\"\(id)\",\"operation\":\"list\"}",
                 "{\"schema\":1,\"requestID\":\"\(id)\",\"operation\":\"commit\"}",
                 "{\"schema\":1,\"requestID\":\"\(id)\",\"operation\":\"list\",\"deviceID\":\"board\"}"] {
        #expect(throws: (any Error).self) { try WorkbenchRequest.decode(Data(json.utf8)) }
    }
    #expect(throws: WorkbenchFailure.self) { try WorkbenchRequest(operation: .run, scenarioID: "unknown") }
    #expect(throws: WorkbenchFailure.self) { try WorkbenchRequest(operation: .list, firmwareBuildID: String(repeating: "a", count: 64)) }
}

/// Failed initial persistence prevents even metadata reads; duplicate actions do not replay.
@Test @MainActor func durableAdmissionAndNoReplayPrecedeSDKWork() async throws {
    let backend = Backend(), store = Store()
    let engine = WorkbenchScenarioEngine(backend: backend, store: store)
    let request = try WorkbenchRequest(operation: .run, scenarioID: "compiler.catalogue")
    store.refuseBegin = true
    await #expect(throws: WorkbenchFailure.self) { try await engine.run(request) }
    #expect(backend.calls == 0)
    store.refuseBegin = false
    #expect(try await engine.run(request).status == .passed)
    let calls = backend.calls
    await #expect(throws: WorkbenchFailure.self) { try await engine.run(request) }
    #expect(backend.calls == calls)
}

/// Missing bytes block, integrity failures fail, and neither outcome is a compiler success.
@Test @MainActor func unavailableAndCorruptResourcesStayDistinct() async throws {
    let backend = Backend(), store = Store()
    let engine = WorkbenchScenarioEngine(backend: backend, store: store)
    backend.resourceError = .invalidFile("compiler.wasm")
    #expect(try await engine.run(WorkbenchRequest(operation: .run, scenarioID: "compiler.resources")).status == .blocked)
    backend.resourceError = .resourceIntegrityMismatch("compiler.wasm")
    #expect(try await engine.run(WorkbenchRequest(operation: .run, scenarioID: "compiler.resources")).status == .failed)
    #expect(engine.report?.artifacts.isEmpty == true)
}

/// Unmigrated hardware and missing exact selection are blocked before SDK work.
@Test @MainActor func hardwareAndMissingSelectionsNeverReachBackend() async throws {
    let backend = Backend(), store = Store()
    let engine = WorkbenchScenarioEngine(backend: backend, store: store)
    #expect(try await engine.run(WorkbenchRequest(operation: .run, scenarioID: "device.upload-recovery")).status == .blocked)
    #expect(try await engine.run(WorkbenchRequest(operation: .run, scenarioID: "compiler.smoke")).status == .blocked)
    #expect(backend.calls == 0)
}

/// Busy admission, cancellation and fresh execution share one engine and retain earlier terminal reports.
@Test @MainActor func busyCancellationSettlesBeforeFreshWork() async throws {
    let backend = Backend(), store = Store()
    let engine = WorkbenchScenarioEngine(backend: backend, store: store)
    backend.wait = true
    let request = try WorkbenchRequest(operation: .run, scenarioID: "compiler.resources")
    let pending = Task { try await engine.run(request) }
    for _ in 0..<1000 { if backend.suspended != nil { break }; await Task.yield() }
    #expect(backend.suspended != nil)
    await #expect(throws: WorkbenchFailure.self) { try await engine.run(WorkbenchRequest(operation: .run, scenarioID: "compiler.catalogue")) }
    engine.cancel(requestID: UUID())
    #expect(engine.isRunning)
    engine.cancel(requestID: request.requestID)
    backend.suspended?.resume(); backend.suspended = nil
    #expect(try await pending.value.status == .cancelled)
    #expect(!engine.isRunning)
    backend.wait = false
    #expect(try await engine.run(WorkbenchRequest(operation: .run, scenarioID: "compiler.catalogue")).status == .passed)
    #expect(store.reports.contains { $0.status == .cancelled })
}

/// A failed final save cannot publish a passed UI/CLI result.
@Test @MainActor func finalPersistenceFailureCannotPublishPassed() async throws {
    let backend = Backend(), store = Store(); store.refusePass = true
    let engine = WorkbenchScenarioEngine(backend: backend, store: store)
    #expect(try await engine.run(WorkbenchRequest(operation: .run, scenarioID: "compiler.catalogue")).status == .failed)
    #expect(!store.reports.contains { $0.status == .passed })
}

/// Actual exclusive directories prevent replay, while incomplete context is loaded unknown without modifying bytes.
@Test @MainActor func fileHistoryNeverReplaysOrRewritesInterruptedRuns() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("workbench-store-" + UUID().uuidString)
    defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
    let store = WorkbenchFileRunStore(directory: root)
    let request = try WorkbenchRequest(operation: .run, scenarioID: "compiler.catalogue")
    let report = WorkbenchReport(request: request)
    try store.begin(report)
    let file = root.appendingPathComponent(request.requestID.uuidString + "/report.json")
    let original = try Data(contentsOf: file)
    #expect(throws: (any Error).self) { try store.begin(report) }
    #expect(try store.history().first?.status == .outcomeUnknown)
    #expect(try Data(contentsOf: file) == original)
}

/// Parent cancellation reaches the owned SDK task; no fresh run is admitted until cancellation settles.
@Test @MainActor func parentCancellationPropagatesIntoTheScenario() async throws {
    let backend = Backend(), store = Store(); backend.wait = true
    let engine = WorkbenchScenarioEngine(backend: backend, store: store)
    let request = try WorkbenchRequest(operation: .run, scenarioID: "compiler.resources")
    let pending = Task { try await engine.run(request) }
    for _ in 0..<1000 { if backend.suspended != nil { break }; await Task.yield() }
    #expect(backend.suspended != nil)
    pending.cancel()
    for _ in 0..<100 { await Task.yield() }
    backend.suspended?.resume(); backend.suspended = nil
    #expect(try await pending.value.status == .cancelled)
    #expect(!engine.isRunning)
}
