import Foundation
import Testing
import FirmingoKit
@testable import FirmingoWorkbenchCore

/// In-memory checkpoint fixture; no hardware, compiler or filesystem observations are fabricated as passes.
@MainActor private final class ManagedStoreFixture: WorkbenchManagedStore {
    /// Durable data survives construction of a second coordinator in restart tests.
    var values: [UUID: WorkbenchManagedCheckpoint] = [:]
    /// Injects the commit write-gate failure before the driver may commit.
    var rejectCommitSave = false
    /// Injects admission failure before any driver call.
    var rejectBegin = false
    /// Records release/disposal separately from transaction outcomes.
    var closes = 0
    /// Reserves the original operation exactly once.
    func begin(_ value: WorkbenchManagedCheckpoint) async throws -> UUID {
        guard !rejectBegin, values[value.request.requestID] == nil else { throw WorkbenchFailure("Fixture admission refused.") }
        values[value.request.requestID] = value; return UUID()
    }
    /// A read-only reservation is not commit authority.
    func acquire(_ operationID: UUID) async throws -> UUID { _ = try await load(operationID); return UUID() }
    /// Does not restore a live driver session.
    func load(_ operationID: UUID) async throws -> WorkbenchManagedCheckpoint {
        guard let value = values[operationID] else { throw WorkbenchFailure("Fixture context missing.") }; return value
    }
    /// Models the same fail-closed intent gate as the real app store.
    func save(_ value: WorkbenchManagedCheckpoint, lease: UUID) async throws {
        if rejectCommitSave && value.commitIntent { throw WorkbenchFailure("Fixture commit journal failed.") }
        try value.validate(); values[value.request.requestID] = value
    }
    /// Records explicit validated release while keeping history.
    func close(_ value: WorkbenchManagedCheckpoint, lease: UUID) async throws { try value.validate(); closes += 1 }
    /// No real reservation is held by this non-I/O fixture.
    func release(_ lease: UUID) async {}
}

/// Pure call-count fixture; the archived bytes below are never executed or deployed by tests.
@MainActor private final class ManagedDriverFixture: WorkbenchManagedDriver {
    /// Ordered abstract SDK-boundary invocations.
    var calls: [String] = []
    /// Forces uncertainty after the sole abstract commit admission.
    var uncertain = false
    /// Selects the next read-only result independently of command acceptance.
    var queryState = "boot_confirmed"
    /// Supplies original qualified bytes only to test report validation, not to claim compilation.
    func compile(sketch: String, deviceID: String) async throws -> WorkbenchReport.Artifact {
        calls.append("compile")
        let data = try #require(Data(base64Encoded: managedFixtureCapsule))
        return .init(name: "state-a.fms", sha256: WorkbenchManagedCheckpoint.capsuleSHA256("state-a"), bytes: data,
            receiptJSON: Data("{}".utf8), wasmLinearMemoryBytes: 0)
    }
    /// Issues a decoded inert record; it is not network or staging evidence.
    func stage(_ selection: WorkbenchDeviceSelection) async throws -> ManagedUploadRecord { calls.append("stage"); return try managedFixtureRecord() }
    /// Counts the one abstract call; lost replies cannot cause a second one.
    func commit(_ record: ManagedUploadRecord) async throws -> WorkbenchManagedCheckpoint.Snapshot {
        calls.append("commit")
        if uncertain { throw ManagedUploadError.uncertainCommit(record: record, underlying: WorkbenchFailure("Fixture lost reply.")) }
        return try managedFixtureSnapshot("committing")
    }
    /// Returns an inert aborted state for policy tests.
    func abort(_ record: ManagedUploadRecord) async throws -> WorkbenchManagedCheckpoint.Snapshot { calls.append("abort"); return try managedFixtureSnapshot("aborted") }
    /// Proves cleanup happened without emulating hardware state.
    func disconnect() async { calls.append("disconnect") }
    /// Returns a typed fixture snapshot or explicit boot-change uncertainty.
    func reconcile(_ selection: WorkbenchDeviceSelection, record: ManagedUploadRecord) async throws -> (WorkbenchManagedCheckpoint.Snapshot?, String?) {
        calls.append("query")
        return queryState == "bootChanged" ? (nil, "bootChanged") : (try managedFixtureSnapshot(queryState), nil)
    }
}

/// Constructs a valid explicit stage, never selecting hardware from an address alone.
private func managedFixtureStage() throws -> WorkbenchRequest {
    let id = UUID()
    return try .init(requestID: id, operation: .run, scenarioID: "managed.stage",
        device: .init(address: "192.168.77.1", boardID: "nano_rp2040_connect", deviceID: "5031503337360009", bootID: "0123456789abcdef"),
        managed: .init(operationID: id, sketch: "state-a", residentImageSHA256: WorkbenchManagedSelection.imageSHA256,
            evidence: "Parser fixture only; no installed-image claim", authorization: "stage-d2-gnd"))
}

/// Binds follow-up selection to the exact original transaction, not its numeric upload ID alone.
private func managedFixtureAction(_ action: String, original: WorkbenchManagedCheckpoint) throws -> WorkbenchRequest {
    try .init(operation: .run, scenarioID: action, device: original.request.device,
        managed: .init(operationID: original.request.requestID, recordSHA256: try original.recordSHA256,
            authorization: action == "managed.commit" ? "commit-once-d2-gnd" : nil))
}

/// Decodes scalar parser data only; the SDK never sends this test record to a device.
private func managedFixtureRecord() throws -> ManagedUploadRecord {
    let value: [String: Any] = ["version": 1, "deviceID": "5031503337360009", "bootID": "0123456789abcdef", "boardID": "nano_rp2040_connect",
        "targetID": 2, "format": "nano-managed-v2", "uploadID": 7, "size": 544,
        "sha256": WorkbenchManagedCheckpoint.capsuleSHA256("state-a"), "residentELFSHA256": WorkbenchManagedSelection.residentELFSHA256,
        "firmwareImageSHA256": WorkbenchManagedSelection.imageSHA256]
    return try JSONDecoder().decode(ManagedUploadRecord.self, from: JSONSerialization.data(withJSONObject: value))
}

/// Snapshot fixtures preserve installed/startup/aborted distinctions and conservative slot facts.
private func managedFixtureSnapshot(_ state: String) throws -> WorkbenchManagedCheckpoint.Snapshot {
    let value: [String: Any] = ["uploadID": 7, "size": 544, "received": 544,
        "sha256": WorkbenchManagedCheckpoint.capsuleSHA256("state-a"), "state": state,
        "slotTouched": ["installed", "boot_confirmed", "failed"].contains(state), "errorCode": state == "failed" ? "install_failed" : "none"]
    return try JSONDecoder().decode(WorkbenchManagedCheckpoint.Snapshot.self, from: JSONSerialization.data(withJSONObject: value))
}

/// Version-three requests cannot import arbitrary bytes or silently authorize flash commit from stage.
@Test func managedRequestScopesAreClosedAndSeparatelyAuthorized() throws {
    let request = try managedFixtureStage()
    #expect(request.schema == 3)
    #expect(try WorkbenchRequest.decode(JSONEncoder().encode(request)) == request)
    var value = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    var nested = try #require(value["managed"] as? [String: Any]); nested["bytes"] = "firmware"; value["managed"] = nested
    #expect(throws: WorkbenchFailure.self) { try WorkbenchRequest.decode(JSONSerialization.data(withJSONObject: value)) }
    #expect(throws: WorkbenchFailure.self) { try WorkbenchRequest(operation: .run, scenarioID: "managed.commit", device: request.device,
        managed: .init(operationID: request.requestID, recordSHA256: String(repeating: "a", count: 64))) }
}

/// Stage and commit remain separate; repeated commit cannot be recovered by choosing a fresh command UUID.
@Test @MainActor func managedStageCommitAndReconciliationHaveDistinctOutcomes() async throws {
    let store = ManagedStoreFixture(), driver = ManagedDriverFixture()
    let coordinator = WorkbenchManagedCoordinator(driver: driver, store: store), request = try managedFixtureStage()
    var last: WorkbenchManagedEvidence?
    try await coordinator.run(request) { last = $0 }
    #expect(driver.calls == ["compile", "stage"])
    try #require(last).validate(scenario: "managed.stage", runID: request.requestID, passed: true)
    await #expect(throws: WorkbenchFailure.self) { try await coordinator.run(managedFixtureStage()) { _ in } }
    #expect(driver.calls == ["compile", "stage"])
    await coordinator.disconnect(operationID: UUID())
    let checkpoint = try await store.load(request.requestID), commit = try managedFixtureAction("managed.commit", original: checkpoint)
    try await coordinator.run(commit) { last = $0 }
    #expect(driver.calls.filter { $0 == "commit" }.count == 1)
    #expect(last?.outcome == "commit_accepted")
    await #expect(throws: WorkbenchFailure.self) { try await coordinator.run(commit) { _ in } }
    let query = try managedFixtureAction("managed.reconcile", original: checkpoint)
    try await coordinator.run(query) { last = $0 }
    #expect(last?.outcome == "boot_confirmed"); #expect(store.closes == 1)
    try #require(last).validate(scenario: "managed.reconcile", runID: query.requestID, passed: true)
}

/// Recreating the coordinator restores only query context, even while saved RAM verification exists.
@Test @MainActor func managedRestartCannotRestoreCommitCapability() async throws {
    let store = ManagedStoreFixture(), first = ManagedDriverFixture(), request = try managedFixtureStage()
    let original = WorkbenchManagedCoordinator(driver: first, store: store)
    try await original.run(request) { _ in }; await original.disconnect(operationID: request.requestID)
    let checkpoint = try await store.load(request.requestID), second = ManagedDriverFixture()
    let restored = WorkbenchManagedCoordinator(driver: second, store: store)
    await #expect(throws: WorkbenchFailure.self) { try await restored.run(managedFixtureAction("managed.commit", original: checkpoint)) { _ in } }
    #expect(second.calls.isEmpty)
    second.queryState = "aborted"
    try await restored.run(managedFixtureAction("managed.reconcile", original: checkpoint)) { _ in }
    #expect(!second.calls.contains("commit")); #expect(store.closes == 1)
}

/// Durable admission and commit-intent failures must precede driver side effects.
@Test @MainActor func managedPersistenceFailuresPreventDriverAdmissionOrCommit() async throws {
    let store = ManagedStoreFixture(), driver = ManagedDriverFixture(), request = try managedFixtureStage()
    let coordinator = WorkbenchManagedCoordinator(driver: driver, store: store)
    store.rejectBegin = true
    await #expect(throws: WorkbenchFailure.self) { try await coordinator.run(request) { _ in } }
    #expect(driver.calls.isEmpty)
    store.rejectBegin = false; try await coordinator.run(request) { _ in }
    let checkpoint = try await store.load(request.requestID); store.rejectCommitSave = true
    await #expect(throws: WorkbenchFailure.self) { try await coordinator.run(managedFixtureAction("managed.commit", original: checkpoint)) { _ in } }
    #expect(!driver.calls.contains("commit")); #expect(store.closes == 0)
}

/// A real typed uncertainty never permits commit replay or pre-commit retirement.
@Test @MainActor func managedLostReplyRemainsQueryOnlyAndCannotRetireAsPrecommit() async throws {
    let store = ManagedStoreFixture(), driver = ManagedDriverFixture(), request = try managedFixtureStage()
    let coordinator = WorkbenchManagedCoordinator(driver: driver, store: store)
    try await coordinator.run(request) { _ in }; let checkpoint = try await store.load(request.requestID)
    driver.uncertain = true
    await #expect(throws: ManagedUploadError.self) { try await coordinator.run(managedFixtureAction("managed.commit", original: checkpoint)) { _ in } }
    driver.queryState = "bootChanged"; var last: WorkbenchManagedEvidence?
    try await coordinator.run(managedFixtureAction("managed.reconcile", original: checkpoint)) { last = $0 }
    #expect(last?.outcome == "unknown"); #expect(last?.checkpoint?.commitIntent == true)
    await #expect(throws: WorkbenchFailure.self) { try await coordinator.run(managedFixtureAction("managed.retire", original: checkpoint)) { _ in } }
    #expect(driver.calls.filter { $0 == "commit" }.count == 1)
}

/// A known RAM-only context can be retired after an observed boot change without claiming a device abort.
@Test @MainActor func managedPrecommitDisconnectAndChangedBootPermitOnlyHostRetirement() async throws {
    let store = ManagedStoreFixture(), driver = ManagedDriverFixture(), request = try managedFixtureStage()
    let coordinator = WorkbenchManagedCoordinator(driver: driver, store: store)
    try await coordinator.run(request) { _ in }; let checkpoint = try await store.load(request.requestID)
    try await coordinator.run(managedFixtureAction("managed.disconnect", original: checkpoint)) { _ in }
    driver.queryState = "bootChanged"
    try await coordinator.run(managedFixtureAction("managed.reconcile", original: checkpoint)) { _ in }
    try await coordinator.run(managedFixtureAction("managed.retire", original: checkpoint)) { value in
        #expect(value.checkpoint?.unknownReason == "bootChanged")
    }
    #expect(store.closes == 1); #expect(!driver.calls.contains("commit"))
}

/// A crash before a transaction was issued can be retired without fabricating an abort or contacting hardware.
@Test @MainActor func managedUnissuedRestartCanBeQueriedAndExplicitlyRetired() async throws {
    let store = ManagedStoreFixture(), driver = ManagedDriverFixture(), request = try managedFixtureStage()
    var checkpoint = WorkbenchManagedCheckpoint(request: request); checkpoint.stageIntent = true
    store.values[request.requestID] = checkpoint
    let coordinator = WorkbenchManagedCoordinator(driver: driver, store: store)
    var last: WorkbenchManagedEvidence?
    let restore = try WorkbenchRequest(operation: .run, scenarioID: "managed.restore", device: request.device, managed: .init(operationID: request.requestID))
    try await coordinator.run(restore) { last = $0 }
    #expect(last?.outcome == "context_restored"); #expect(last?.recordSHA256 == WorkbenchManagedCheckpoint.digest(Data("null".utf8)))
    try #require(last).validate(scenario: "managed.restore", runID: restore.requestID, passed: true)
    try await coordinator.run(managedFixtureAction("managed.reconcile", original: checkpoint)) { last = $0 }
    #expect(last?.outcome == "unknown"); #expect(last?.checkpoint?.unknownReason == "recordNotIssued")
    let retire = try managedFixtureAction("managed.retire", original: checkpoint)
    try await coordinator.run(retire) { last = $0 }
    try #require(last).validate(scenario: "managed.retire", runID: retire.requestID, passed: true)
    #expect(last?.outcome == "retired_unissued"); #expect(store.closes == 1); #expect(driver.calls.isEmpty)
}

/// Refuses compiler access: managed compilation belongs to the separately injected managed driver.
@MainActor private final class ManagedCompilerFixture: WorkbenchCompilerBackend {
    /// No generic catalogue lookup is needed for fixed managed actions.
    func catalogue() async throws -> WorkbenchCatalogue { throw WorkbenchFailure("Unexpected generic compiler lookup.") }
    /// No generic resource path is invoked by these policy fixtures.
    func verifyResources() async throws { throw WorkbenchFailure("Unexpected generic resource lookup.") }
    /// Produces no fabricated generic compiler output.
    func compile(_ input: WorkbenchCompilerInput, buildID: String, probe: WorkbenchCompilerProbe) async throws -> WorkbenchReport.Artifact { throw WorkbenchFailure("Unexpected generic compiler call.") }
}

/// Journal fixture validates real schema rules and can reject the final pass gate.
@MainActor private final class ManagedRunStoreFixture: WorkbenchRunStore {
    /// Injects failure only at terminal success publication.
    var rejectPass = false
    /// Exclusive request identities prevent duplicate phase admission.
    var ids: Set<UUID> = []
    /// Reserves before any injected driver side effect.
    func begin(_ report: WorkbenchReport) throws {
        guard ids.insert(report.id).inserted else { throw WorkbenchFailure("Repeated fixture run.") }
        try report.validateScope()
    }
    /// Refuses invalid/incomplete phase passes before publication.
    func save(_ report: WorkbenchReport) throws {
        try report.validateScope()
        if rejectPass && report.status == .passed { throw WorkbenchFailure("Terminal fixture gate failed.") }
    }
}

/// Backgrounding an idle verified stage and failed success publication both invalidate process-local authority.
@Test @MainActor func managedEngineBackgroundAndPassGateFailureDiscardLiveStage() async throws {
    for refusePass in [false, true] {
        let store = ManagedStoreFixture(), driver = ManagedDriverFixture(), journal = ManagedRunStoreFixture()
        journal.rejectPass = refusePass
        let coordinator = WorkbenchManagedCoordinator(driver: driver, store: store)
        let engine = WorkbenchScenarioEngine(backend: ManagedCompilerFixture(), store: journal, supportsSceneTransitions: true, managedBackend: coordinator)
        let request = try managedFixtureStage(), report = try await engine.run(request)
        #expect(report.status == (refusePass ? .failed : .passed))
        #expect(report.schema == 3); #expect(report.deviceOperations)
        if !refusePass {
            let bad = try WorkbenchRequest(operation: .run, scenarioID: "managed.commit", device: request.device,
                managed: .init(operationID: request.requestID, recordSHA256: String(repeating: "0", count: 64), authorization: "commit-once-d2-gnd"))
            let rejected = try await engine.run(bad)
            #expect(rejected.status == .failed); #expect(!driver.calls.contains("disconnect"))
            engine.recordScene("background")
            for _ in 0..<32 { if driver.calls.contains("disconnect") { break }; await Task.yield() }
        }
        #expect(driver.calls.contains("disconnect"))
        let checkpoint = try await store.load(request.requestID)
        let result = try await engine.run(managedFixtureAction("managed.commit", original: checkpoint))
        #expect(result.status == .failed); #expect(!driver.calls.contains("commit"))
    }
}

/// Explicit prepared-package check uses real default SDK resources but never connects or stages a device.
@Test(.enabled(if: ProcessInfo.processInfo.environment["WORKBENCH_MANAGED_RUNTIME"] == "1"))
@MainActor func managedFixedVectorsCompileThroughTheActualSDKDriver() async throws {
    let driver = SDKWorkbenchManagedDriver()
    for sketch in ["state-a", "state-b"] {
        let artifact = try await driver.compile(sketch: sketch, deviceID: "0102030405060708")
        #expect(artifact.sha256 == WorkbenchManagedCheckpoint.capsuleSHA256(sketch))
        #expect(WorkbenchManagedCheckpoint.digest(artifact.bytes) == artifact.sha256)
        #expect(!artifact.receiptJSON.isEmpty)
    }
    await driver.disconnect()
}

/// Historical SDK/native-validated state-A capsule (docs/nano-fms2-ipad.json); parser data only, never executed.
private let managedFixtureCapsule = "Rk1TMgIAgABOQU5PdDACEAABIBAcAQAAAQEgEAkBIBA8iQAgBAAAAECJACAUAAAAHAIAACACAAAAAAAAAAAAAMnXutgyHlYeDWXAuswBTKY/MfargxUwAkJk51qnHLWZ5tuSU/AwXfypqEwderP4zNpzd0tGvwtAZAAST+LRceYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIC1APAP+IC9gLUA8CP4gL0AIiAqBdALRtNAA3BAHAgy9+dwR7C1CEgAaAhJCmhIYIpgB00qaAYkASEgRpBHamgAISBGkEewvTyJACBAiQAgfDACEPC1h7AsTzhoQBw4YCtOMGhAHDBgKk2oaIBHGCg72+hogEcAKDfUAUbwaAIoJdABKDbRAaxBIOBwMiCgcFEgYHBGICBwIB0fSpBHcWggRggwHEqQR7FoIEYMMBpKkEc5aCBGEDAXT7hHMWggRhQwuEdqaBghIEaQRwvgAagBcGpoASQhRpBHMGlAHDBhIQKIQgHRACDwYCloASCIRwew8L0CKQPQASn20QEg8+cAIAIh8WAwYe/nwEY8iQAgQIkAIIgwAhARASAQBwAAAA=="
