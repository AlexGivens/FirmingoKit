import Foundation
import Testing
@testable import FirmingoWorkbenchCore

/// Controlled metadata/resource boundary; no synthetic successful compilation or device work.
@MainActor private final class ControlBackend: WorkbenchCompilerBackend {
    /// SDK accesses counted to prove rejection/admission order.
    var calls = 0
    /// Optional controlled resource suspension for cancellation/busy tests.
    var continuation: CheckedContinuation<Void, Never>?
    /// Whether resources wait for a deterministic test release.
    var suspended = false
    /// Returns display metadata only.
    func catalogue() async throws -> WorkbenchCatalogue { calls += 1; return .init(sha256: String(repeating: "a", count: 64), builds: []) }
    /// Models an owned pending resource request, with actual Swift cancellation propagation.
    func verifyResources() async throws {
        calls += 1
        if suspended { await withCheckedContinuation { continuation = $0 } }
        try Task.checkCancellation()
    }
    /// Always refuses fixture compilation.
    func compile(_ input: WorkbenchCompilerInput, buildID: String, probe: WorkbenchCompilerProbe) async throws -> WorkbenchReport.Artifact {
        throw WorkbenchFailure("No executable compiler fixture.")
    }
}

/// Builds closed command data so unknown extensions are tested at the actual decoder.
private func controlCommand(_ action: String, runID: UUID? = nil, request: WorkbenchRequest? = nil) throws -> WorkbenchControlCommand {
    var object: [String: Any] = ["schema": 1, "commandID": UUID().uuidString, "action": action]
    if let runID { object["runID"] = runID.uuidString }
    if let request { object["request"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) }
    return try WorkbenchControlCommand.decode(JSONSerialization.data(withJSONObject: object))
}

/// Network authority requires exact bounded private HTTPS pin/token data, never public URLs or paths.
@Test func pairingInvitationRejectsExpandedNetworkAuthority() throws {
    let base: [String: Any] = ["schema": 1,"sessionID":UUID().uuidString,"endpoint":"https://192.168.1.2:8443/",
                              "certificateSHA256":String(repeating:"a",count:64),"token":String(repeating:"b",count:64),"label":"Fixture"]
    #expect(try WorkbenchPairingInvitation.decode(JSONSerialization.data(withJSONObject: base)).label == "Fixture")
    for url in ["http://192.168.1.2:8443/","https://example.com:8443/","https://8.8.8.8:8443/", "https://192.168.1.2:8443/path", "https://user@192.168.1.2:8443/"] {
        var value = base; value["endpoint"] = url
        #expect(throws: WorkbenchFailure.self) { try WorkbenchPairingInvitation.decode(JSONSerialization.data(withJSONObject: value)) }
    }
    var extra = base; extra["serviceURL"] = "file:///fixture"
    #expect(throws: WorkbenchFailure.self) { try WorkbenchPairingInvitation.decode(JSONSerialization.data(withJSONObject: extra)) }
}

/// Paired controls cannot invent scenes, paths, shell or device operations.
@Test func controlDecoderRetainsTheClosedScenarioSurface() throws {
    for action in ["commit", "scene", "shell", "reset", "device.upload"] {
        #expect(throws: (any Error).self) { try controlCommand(action) }
    }
    #expect(throws: WorkbenchFailure.self) { try controlCommand("cancel") }
    #expect(throws: WorkbenchFailure.self) { try controlCommand("list", runID: UUID()) }
    let request = try WorkbenchRequest(operation: .run, scenarioID: "compiler.catalogue")
    var object: [String: Any] = ["schema":1,"commandID":UUID().uuidString,"action":"run"]
    var raw = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String:Any])
    raw["sourcePath"] = "/not-accepted"; object["request"] = raw
    #expect(throws: WorkbenchFailure.self) { try WorkbenchControlCommand.decode(JSONSerialization.data(withJSONObject: object)) }
}

/// Durable engine admission precedes the remote acknowledgement, while exact saved context can be exported later.
@Test @MainActor func controlAdmissionAndSavedReportUseTheSharedEngine() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
    let backend = ControlBackend(), store = WorkbenchFileRunStore(directory: directory)
    let engine = WorkbenchScenarioEngine(backend: backend, store: store), host = WorkbenchControlHost(engine: engine, store: store)
    let request = try WorkbenchRequest(operation: .run, scenarioID: "compiler.resources")
    backend.suspended = true
    let reply = await host.handle(try controlCommand("run", request: request))
    #expect(reply.accepted && reply.state.runID == request.requestID)
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(request.requestID.uuidString+"/report.json").path))
    for _ in 0..<1000 { if backend.continuation != nil { break }; await Task.yield() }
    let stale = await host.handle(try controlCommand("cancel", runID: UUID()))
    #expect(!stale.accepted && engine.isRunning)
    host.disconnect(); backend.continuation?.resume(); backend.continuation = nil
    for _ in 0..<1000 { if !engine.isRunning { break }; await Task.yield() }
    #expect(engine.report?.status == .cancelled)
    let exported = await host.handle(try controlCommand("report", runID: request.requestID))
    #expect(exported.accepted && exported.report?.status == .cancelled)
    let replay = await host.handle(try controlCommand("run", request: request))
    #expect(!replay.accepted)
}

/// An unusable journal cannot acknowledge admission or reach the SDK.
@Test @MainActor func controlCannotAcknowledgeFailedDurableAdmission() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("not a directory".utf8).write(to: directory)
    defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
    let backend = ControlBackend(), store = WorkbenchFileRunStore(directory: directory)
    let engine = WorkbenchScenarioEngine(backend: backend, store: store), host = WorkbenchControlHost(engine: engine, store: store)
    let request = try WorkbenchRequest(operation: .run, scenarioID: "compiler.catalogue")
    let reply = await host.handle(try controlCommand("run", request: request))
    #expect(!reply.accepted && backend.calls == 0 && !engine.isRunning)
}
