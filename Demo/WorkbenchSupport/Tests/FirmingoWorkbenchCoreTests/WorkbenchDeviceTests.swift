import Foundation
import Testing
@testable import FirmingoWorkbenchCore

/// Inert orchestration fixture; these snapshots never count as physical device evidence.
@MainActor private final class DeviceFixture: WorkbenchDeviceBackend {
    /// Number of explicit device requests, proving compiler/admission gates.
    var calls = 0
    /// Injects an incomplete observation which must never publish a pass.
    var incomplete = false
    /// Optional pending operation for deterministic cancellation tests.
    var pending = false
    /// Produces only typed fixture observations through the real engine journal path.
    func run(_ selection: WorkbenchDeviceSelection, console: Bool,
             save: @escaping @MainActor (WorkbenchDeviceEvidence) throws -> Void) async throws {
        calls += 1
        if pending { try await Task.sleep(for: .seconds(30)) }
        var evidence = try fixtureEvidence(selection)
        if console {
            evidence.consoleOpened = true; evidence.probeAttempted = true
            evidence.consoleClosed = !incomplete
            evidence.sentBytes = selection.consoleProbe == "fms2-command-2-v1" ? 257 : 256
            evidence.received = Data((0...255).map(UInt8.init))
        }
        try save(evidence)
    }
}

/// Compiler dependency must remain untouched throughout a device scenario.
@MainActor private final class DeviceCompilerFixture: WorkbenchCompilerBackend {
    /// Any access is a failure in this hardware-only fixture.
    var calls = 0
    /// Refuses metadata reads instead of fabricating hardware/compiler support.
    func catalogue() async throws -> WorkbenchCatalogue { calls += 1; throw WorkbenchFailure("Compiler must not be used.") }
    /// Refuses compiler-resource verification.
    func verifyResources() async throws { calls += 1; throw WorkbenchFailure("Compiler must not be used.") }
    /// Never emits fixture compiler artifacts.
    func compile(_ input: WorkbenchCompilerInput, buildID: String, probe: WorkbenchCompilerProbe) async throws -> WorkbenchReport.Artifact {
        calls += 1; throw WorkbenchFailure("Compiler must not be used.")
    }
}

/// Exclusive fake journals model production admission/pass failures without filesystem or hardware.
@MainActor private final class DeviceStoreFixture: WorkbenchRunStore {
    /// Existing run IDs cannot be reused.
    var ids: Set<UUID> = []
    /// Injected initial journal rejection.
    var refuse = false
    /// Injected terminal persistence failure.
    var refusePass = false
    /// Reserves exactly once before any connection.
    func begin(_ report: WorkbenchReport) throws {
        guard !refuse, ids.insert(report.id).inserted else { throw WorkbenchFailure("Admission refused.") }
    }
    /// A failed durable pass must not be published.
    func save(_ report: WorkbenchReport) throws {
        if refusePass && report.status == .passed { throw WorkbenchFailure("Pass refused.") }
    }
}

/// Explicit parser-only Nano selection, with console mode added only by the corresponding test.
private func fixtureSelection(console: Bool = false) throws -> WorkbenchDeviceSelection {
    try .init(address: "192.168.77.1", boardID: "nano_rp2040_connect", deviceID: "5031503337360009",
        bootID: console ? "0123456789abcdef" : nil, consoleProbe: console ? "raw-256-v1" : nil)
}

/// Codable projection data is not a claimed SDK network/hello run.
private func fixtureEvidence(_ selection: WorkbenchDeviceSelection) throws -> WorkbenchDeviceEvidence {
    var evidence = WorkbenchDeviceEvidence(selection: selection)
    evidence.connectionAttempted = true; evidence.disconnected = true
    let json = #"{"protocolMajor":1,"firmwareVersion":"fixture","deviceID":"5031503337360009","bootID":"0123456789abcdef","boardID":"nano_rp2040_connect","maximumPayload":4096,"authenticationMode":"open-development","channels":[{"id":1,"backend":"application","controls":[],"receiveQueueBytes":256,"transmitQueueBytes":256,"isOwned":false}],"targets":[]}"#
    evidence.snapshot = try JSONDecoder().decode(WorkbenchDeviceEvidence.Snapshot.self, from: Data(json.utf8))
    return evidence
}

/// Version-one requests remain closed; only version two can carry a checked nested device selection.
@Test func deviceRequestsAreVersionedAndCannotExpandEndpointOrWriteAuthority() throws {
    let selected = try fixtureSelection()
    let request = try WorkbenchRequest(operation: .run, scenarioID: "device.inspect", device: selected)
    #expect(request.schema == 2)
    #expect(try WorkbenchRequest.decode(JSONEncoder().encode(request)) == request)
    #expect(throws: WorkbenchFailure.self) { try WorkbenchRequest(operation: .run, scenarioID: "device.inspect") }
    #expect(throws: WorkbenchFailure.self) { try WorkbenchRequest(operation: .run, scenarioID: "compiler.catalogue", device: selected) }
    #expect(throws: WorkbenchFailure.self) { try WorkbenchRequest(operation: .run, scenarioID: "device.console-binary", device: selected) }
    #expect(throws: WorkbenchFailure.self) { try WorkbenchRequest(operation: .run, scenarioID: "device.inspect", firmwareBuildID: String(repeating: "a", count: 64), device: selected) }
    for address in ["8.8.8.8", "127.0.0.1", "192.168.077.1", "192.168.77.1:22", "example.com", "::1"] {
        #expect(throws: WorkbenchFailure.self) { try WorkbenchDeviceSelection(address: address, boardID: selected.boardID, deviceID: selected.deviceID) }
    }
    var raw = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
    var nested = try #require(raw["device"] as? [String: Any]); nested["upload"] = true; raw["device"] = nested
    #expect(throws: WorkbenchFailure.self) { try WorkbenchRequest.decode(JSONSerialization.data(withJSONObject: raw)) }
}

/// Device checks require no compiler binary/catalogue; failed reservations and reused UUIDs prevent backend access.
@Test @MainActor func deviceAdmissionAndCompilerIndependenceUseTheSharedEngine() async throws {
    let device = DeviceFixture(), compiler = DeviceCompilerFixture(), store = DeviceStoreFixture()
    let engine = WorkbenchScenarioEngine(backend: compiler, store: store, deviceBackend: device)
    let request = try WorkbenchRequest(operation: .run, scenarioID: "device.inspect", device: fixtureSelection())
    store.refuse = true
    await #expect(throws: WorkbenchFailure.self) { try await engine.run(request) }
    #expect(device.calls == 0 && compiler.calls == 0)
    store.refuse = false
    let report = try await engine.run(request)
    #expect(report.schema == 2 && report.status == .passed && report.deviceOperations)
    #expect(report.artifacts.isEmpty && report.catalogueSHA256 == nil)
    #expect(device.calls == 1 && compiler.calls == 0)
    await #expect(throws: WorkbenchFailure.self) { try await engine.run(request) }
    #expect(device.calls == 1)
}

/// Every byte and cleanup assertion matters; truncation, extra data and CR/LF transformations cannot pass.
@Test func binaryEvidenceRejectsMismatchIncompleteCleanupAndChangedBoot() throws {
    let selection = try fixtureSelection(console: true)
    var valid = try fixtureEvidence(selection)
    valid.consoleOpened = true; valid.probeAttempted = true; valid.consoleClosed = true
    valid.sentBytes = 256; valid.received = Data((0...255).map(UInt8.init))
    try valid.validate(console: true)
    for count in [0, 1, 255, 257] {
        var value = valid; value.received = Data(repeating: 0, count: count)
        #expect(throws: WorkbenchFailure.self) { try value.validate(console: true) }
    }
    for offset in [0, 10, 13, 128, 255] {
        var value = valid; value.received[offset] ^= 1
        #expect(throws: WorkbenchFailure.self) { try value.validate(console: true) }
    }
    var unclosed = valid; unclosed.consoleClosed = false
    #expect(throws: WorkbenchFailure.self) { try unclosed.validate(console: true) }
    var changed = valid
    changed.selection = try .init(address: selection.address, boardID: selection.boardID, deviceID: selection.deviceID,
        bootID: "1123456789abcdef", consoleProbe: selection.consoleProbe)
    #expect(throws: WorkbenchFailure.self) { try changed.validate(console: true) }
    #expect(throws: WorkbenchFailure.self) { try valid.validate(console: false) }
}

/// Incomplete observations cannot become passes, and unavailable backends are blocked without compiler work.
@Test @MainActor func incompleteHardwareAndMissingBackendNeverPass() async throws {
    let compiler = DeviceCompilerFixture(), store = DeviceStoreFixture(), device = DeviceFixture()
    let request = try WorkbenchRequest(operation: .run, scenarioID: "device.console-binary", device: fixtureSelection(console: true))
    let absent = WorkbenchScenarioEngine(backend: compiler, store: store)
    #expect(try await absent.run(request).status == .blocked)
    device.incomplete = true
    let engine = WorkbenchScenarioEngine(backend: compiler, store: store, deviceBackend: device)
    let other = try WorkbenchRequest(operation: .run, scenarioID: "device.console-binary", device: fixtureSelection(console: true))
    #expect(try await engine.run(other).status == .failed)
    #expect(compiler.calls == 0)
    store.refusePass = true; device.incomplete = false
    let final = try WorkbenchRequest(operation: .run, scenarioID: "device.inspect", device: fixtureSelection())
    #expect(try await engine.run(final).status != .passed)
}

/// Real-host background delivery cancels the owned device task without replay or compiler fallback.
@Test @MainActor func deviceBackgroundCancellationUsesExistingOwnership() async throws {
    let compiler = DeviceCompilerFixture(), store = DeviceStoreFixture(), device = DeviceFixture()
    device.pending = true
    let engine = WorkbenchScenarioEngine(backend: compiler, store: store, supportsSceneTransitions: true, deviceBackend: device)
    let request = try WorkbenchRequest(operation: .run, scenarioID: "device.inspect", device: fixtureSelection())
    let run = Task { try await engine.run(request) }
    for _ in 0..<1000 { if device.calls > 0 { break }; await Task.yield() }
    #expect(device.calls == 1)
    engine.recordScene("background")
    #expect(try await run.value.status == .cancelled)
    #expect(compiler.calls == 0)
}
