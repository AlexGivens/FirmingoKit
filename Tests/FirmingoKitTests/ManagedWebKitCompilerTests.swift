#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import FirmingoKit

/// Opt-in actual SDK/WebKit/WASI tests use an explicitly supplied local service and synthetic resident metadata.
/// Ordinary package tests skip these, never locate a sibling checkout, and never communicate with a board.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["FIRMINGOKIT_WASM_MODULE"].map { !$0.isEmpty } ?? false))
@MainActor struct ManagedWebKitCompilerTests {
    /// Defines exact source bytes for independently recorded development artifact hashes.
    private let blink = "void setup() { pinMode(LED_BUILTIN, OUTPUT); }\nvoid loop() { digitalWrite(LED_BUILTIN, HIGH); delay(100); digitalWrite(LED_BUILTIN, LOW); delay(100); }\n"
    /// Different source verifies a fresh revision cannot return a previous artifact.
    private let console = "void setup() { Serial.begin(115200); Serial.println(\"ready\"); }\nvoid loop() { const int value = Serial.read(); if(value >= 0) Serial.write(uint8_t(value)); }\n"
    /// Obtains only the explicit opt-in capability and initializes the command-line host's AppKit environment.
    private func serviceURL() throws -> URL {
        _ = NSApplication.shared
        let path = try #require(ProcessInfo.processInfo.environment["FIRMINGOKIT_WASM_MODULE"])
        guard !path.isEmpty else { throw ManagedCompilerError.unavailable("Select a nonempty explicit service path") }
        return URL(fileURLWithPath: path)
    }
    /// Synthetic record is structural offline evidence only; none of these capsules may be uploaded.
    private func request(source: String, name: String, revision: UInt64 = 1) throws -> ManagedSketchBuildRequest {
        let binding = try ManagedResidentBinding(deviceID: "0102030405060708", residentELFSHA256: String(repeating:"0",count:64),
            firmwareImageSHA256: String(repeating:"1",count:64), apiAddress:0x10022ca0)
        return try CompilerFixtures.request(source:source,revision:revision,filename:name,resident:binding)
    }
    /// Exercises only an internal test-anchored approved inventory; production resources retain reviewed metadata and remain service-free.
    /// Loads identical verified toolchain identities and compiles the known offline Blink vector through real WebKit.
    @Test func resourceInventoryRuntimeParity() async throws {
        let source = try #require(ManagedCompilerBundle.root())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FirmingoRuntimeResources-" + UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: root)
        defer {
            do { try FileManager.default.removeItem(at: root) }
            catch { Issue.record(error, "Test resource cleanup failed") }
        }
        let copiedService = root.appendingPathComponent("compiler.wasm")
        if FileManager.default.fileExists(atPath: copiedService.path) { try FileManager.default.removeItem(at: copiedService) }
        try FileManager.default.copyItem(at: serviceURL(), to: copiedService)
        var inventory = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("inventory.json"))) as? [String: Any])
        var service = try #require(inventory["service"] as? [String: Any])
        service["distributionReview"] = "approved"; inventory["service"] = service
        let bytes = try JSONSerialization.data(withJSONObject: inventory)
        try bytes.write(to: root.appendingPathComponent("inventory.json"))
        let resources = try await VerifiedManagedResources.load(root: root, expectedSHA256: NanoManagedContract.digest(bytes))
        let toolchain = try await resources.toolchain()
        #expect(toolchain.toolchainSHA256 == "3eda5778fdc515f974d683570a6d6d8e1891ec9a64d0285e473401ebae14dd86")
        #expect(toolchain.recipeSHA256 == ManagedCompilerResourceInventory.recipeSHA256)
        let selected = try await OfflineCompilerFixtures.request(source: blink, revision: 1, filename: "Blink.ino")
        let portable = try ManagedPortableRequest(selected)
        let output = try await ManagedPortableOutput.decode(ManagedWebKitHost().run(request: portable, toolchain: toolchain, progress: { _ in }), request: portable)
        #expect(NanoManagedContract.digest(output.bytes) == "018c94a4a49b71880d6f04aecbe08e809c8ecf49e4278261c45dad3ead205720")
        let receipt = try WireJSON.parse(output.executionReceiptJSON)
        #expect(try receipt.required("firmwareBuildID").string() == selected.firmwareBuild.id)
    }
    /// Actual portable receipts survive the native boundary; stale hashes, correlation and byte substitutions fail.
    @Test func portableReceiptsAndTampering() async throws {
        let selected = try await OfflineCompilerFixtures.request(source: "\u{feff}// café 🎵\r\n" + blink, revision: .max, filename: "Unicode.ino")
        let portable = try ManagedPortableRequest(selected)
        let toolchain = try await VerifiedManagedToolchain.load(serviceURL: serviceURL())
        let json = try await ManagedWebKitHost().run(request: portable, toolchain: toolchain, progress: { _ in })
        let output = try await ManagedPortableOutput.decode(json, request: portable)
        #expect(output.sourceBOMBytes == 3)
        #expect(output.sourceSHA256 == NanoManagedContract.digest(Data(selected.snapshot.source.utf8)))
        let valid = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        for mutation in ["requestSHA256", "sourceRevision", "firmwareBuildID", "buildInputSHA256", "service", "bytes", "buildID", "sequence"] {
            var root = valid
            var event = try #require(root["event"] as? [String: Any])
            var artifact = try #require(event["artifact"] as? [String: Any])
            var receipt = try #require(artifact["receipt"] as? [String: Any])
            switch mutation {
            case "bytes": artifact["bytes"] = Data(repeating: 0, count: 316).base64EncodedString()
            case "buildID": event["buildID"] = "stale"
            case "sequence": event["sequence"] = 1
            case "service":
                var service = try #require(receipt["service"] as? [String: Any]); service["serviceABI"] = 1; receipt["service"] = service
            default: receipt[mutation] = String(repeating: "0", count: 64)
            }
            artifact["receipt"] = receipt; event["artifact"] = artifact; root["event"] = event
            let changed = String(decoding: try ManagedPortableRequest.canonical(root), as: UTF8.self)
            await #expect(throws: FirmingoError.self) { _ = try await ManagedPortableOutput.decode(changed, request: portable) }
        }
        let legacy = try await ManagedSketchCompiler(serviceURL: serviceURL()).build(request(source: blink, name: "Legacy.ino", revision: .max))
        let raw = try #require(legacy.artifact.compilerReceiptJSON)
        let receipt = try WireJSON.parse(raw)
        #expect(try receipt.required("residentBindingID").string().count == 64)
        #expect(!String(decoding: raw, as: UTF8.self).contains("deviceID"))
        #expect(legacy.artifact.receipt.sourceRevision == .max)
    }
    /// Real WebKit compiles distinct source revisions to independently recorded FMS1 outputs and maps syntax errors.
    @Test func realBuildsAndDiagnostics() async throws {
        let compiler = ManagedSketchCompiler(serviceURL: try serviceURL())
        let first = try await compiler.build(request(source:blink,name:"Blink.ino"))
        #expect(first.artifact.capsule.sha256 == "018c94a4a49b71880d6f04aecbe08e809c8ecf49e4278261c45dad3ead205720")
        let second = try await compiler.build(request(source:console,name:"Console.ino",revision:2))
        #expect(second.artifact.capsule.sha256 == "8d8ff53e0ab800a4f68eb6c62b00e001bc8304b2dee2fdf0f815b2e503c5aeff")
        #expect(second.artifact.receipt.sourceRevision == 2)
        do {
            _ = try await compiler.build(request(source:"void setup() { missingFunction(); }\nvoid loop() {}\n",name:"Syntax.ino"))
            Issue.record("Syntax errors must not return artifacts")
        } catch ManagedCompilerError.compilationFailed(let diagnostics) {
            #expect(diagnostics.contains { $0.severity == .error && $0.filename == "Syntax.ino" && $0.line == 1 })
        }
    }

    /// Real device-independent builds preserve known FMS1 output and exact catalogue/revision identities.
    @Test func realOfflineBuildsAndDiagnostics() async throws {
        let compiler = ManagedSketchCompiler(serviceURL: try serviceURL())
        try await compiler.verifyResources()
        let selected = try await OfflineCompilerFixtures.request(source: blink, revision: 1, filename: "Blink.ino")
        let first = try await compiler.build(selected)
        #expect(first.artifact.sha256 == "018c94a4a49b71880d6f04aecbe08e809c8ecf49e4278261c45dad3ead205720")
        #expect(first.artifact.receipt.firmwareBuildID == selected.firmwareBuild.id)
        #expect(first.artifact.receipt.catalogueSHA256 == selected.catalogueSHA256)
        #expect(first.artifact.receipt.provenance.recipeSHA256 == selected.firmwareBuild.recipeSHA256)
        let bound = try first.artifact.bind(to: ManagedDeviceAssociation(deviceID: "0102030405060708",
            firmwareBuildID: selected.firmwareBuild.id, evidence: .hostConfirmedExistingFirmware))
        #expect(bound.sha256 == first.artifact.sha256)
        let second = try await compiler.build(OfflineCompilerFixtures.request(source: console, revision: 2, filename: "Console.ino"))
        #expect(second.artifact.sha256 == "8d8ff53e0ab800a4f68eb6c62b00e001bc8304b2dee2fdf0f815b2e503c5aeff")
        #expect(second.artifact.receipt.sourceRevision == 2)
        #expect(second.artifact.receipt.buildInputSHA256 != first.artifact.receipt.buildInputSHA256)
        do {
            _ = try await compiler.build(OfflineCompilerFixtures.request(
                source: "void setup() { missingFunction(); }\nvoid loop() {}\n", filename: "Syntax.ino"))
            Issue.record("Offline syntax errors must not return artifacts")
        } catch ManagedCompilerError.compilationFailed(let diagnostics) {
            #expect(diagnostics.contains { $0.severity == .error && $0.filename == "Syntax.ino" && $0.line == 1 })
        }
    }

    /// Cancelling actual offline compilation disposes its runtime and releases the shared actor for a legacy build.
    @Test func offlineCancellationAndLegacyReentry() async throws {
        let compiler = ManagedSketchCompiler(serviceURL: try serviceURL())
        let selected = try await OfflineCompilerFixtures.request(source: blink, filename: "Blink.ino")
        let probe = OfflineCancellationProbe()
        let task = Task {
            try await compiler.build(selected) { phase in
                if phase == .compiling { Task { @MainActor in probe.task?.cancel() } }
            }
        }
        probe.task = task
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        probe.task = nil
        let fresh = try await compiler.build(request(source: console, name: "Console.ino", revision: 4))
        #expect(fresh.artifact.receipt.sourceRevision == 4)
        #expect(fresh.artifact.capsule.sha256 == "8d8ff53e0ab800a4f68eb6c62b00e001bc8304b2dee2fdf0f815b2e503c5aeff")
    }

    /// Both overloads share one reservation; mixed requests cannot bypass isolation in either direction.
    @Test func mixedOfflineAndLegacyBuildsAreExclusive() async throws {
        let compiler = ManagedSketchCompiler(serviceURL: try serviceURL())
        let offline = try await OfflineCompilerFixtures.request(source: blink, filename: "Blink.ino")
        let legacy = try request(source: console, name: "Console.ino")
        let firstProbe = BusyProbe()
        let first = Task {
            try await compiler.build(offline) { phase in
                if phase == .verifying { Task { @MainActor in firstProbe.started = true } }
            }
        }
        defer { first.cancel() }
        try await waitForStart(firstProbe)
        do {
            try await compiler.verifyResources()
            Issue.record("Resource verification must not overlap an active build")
        } catch ManagedCompilerError.busy { /* Verification shares the runtime reservation. */ }
        do {
            _ = try await compiler.build(legacy)
            Issue.record("Offline reservation must exclude a legacy build")
        } catch ManagedCompilerError.busy { /* Same actor gate across overloads. */ }
        #expect(try await first.value.artifact.sha256 == "018c94a4a49b71880d6f04aecbe08e809c8ecf49e4278261c45dad3ead205720")
        let secondProbe = BusyProbe()
        let second = Task {
            try await compiler.build(legacy) { phase in
                if phase == .verifying { Task { @MainActor in secondProbe.started = true } }
            }
        }
        defer { second.cancel() }
        try await waitForStart(secondProbe)
        do {
            _ = try await compiler.build(offline)
            Issue.record("Legacy reservation must exclude an offline build")
        } catch ManagedCompilerError.busy { /* Same actor gate across overloads. */ }
        #expect(try await second.value.artifact.capsule.sha256 == "8d8ff53e0ab800a4f68eb6c62b00e001bc8304b2dee2fdf0f815b2e503c5aeff")
    }

    /// Bounds waiting for real runtime reservation; it never assumes an arbitrary delay grants ownership.
    private func waitForStart(_ probe: BusyProbe) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !probe.started {
            guard ContinuousClock.now < deadline else { throw ManagedCompilerError.timedOut }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    /// Main-actor task handoff for the new result type, with no unsafe shared progress capture.
    @MainActor private final class OfflineCancellationProbe {
        /// Exact offline build canceled when its actual worker compilation phase begins.
        var task: Task<ManagedOfflineCompilationResult, any Error>?
    }
    /// Cancellation during real worker execution returns no artifact; the next source revision uses fresh state.
    @Test func cancellationAndFreshBuild() async throws {
        let compiler = ManagedSketchCompiler(serviceURL: try serviceURL())
        let selected = try request(source:blink,name:"Blink.ino")
        let probe = CancellationProbe()
        let task = Task {
            try await compiler.build(selected) { phase in
                if phase == .compiling { Task { @MainActor in probe.task?.cancel() } }
            }
        }
        probe.task = task
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        probe.task = nil
        let fresh = try await compiler.build(request(source:console,name:"Console.ino",revision:3))
        #expect(fresh.artifact.receipt.sourceRevision == 3)
        #expect(fresh.artifact.capsule.sha256 == "8d8ff53e0ab800a4f68eb6c62b00e001bc8304b2dee2fdf0f815b2e503c5aeff")
    }
    /// Actor reentrancy cannot admit a second source while the first build is suspended in real runtime startup.
    @Test func overlappingBuildIsRejected() async throws {
        let compiler = ManagedSketchCompiler(serviceURL:try serviceURL())
        let selected = try request(source:blink,name:"Blink.ino")
        let probe = BusyProbe()
        let first = Task {
            try await compiler.build(selected) { phase in
                if phase == .verifying { Task { @MainActor in probe.started = true } }
            }
        }
        defer { first.cancel() }
        let deadline = ContinuousClock.now.advanced(by:.seconds(5))
        while !probe.started {
            guard ContinuousClock.now < deadline else { throw ManagedCompilerError.timedOut }
            try await Task.sleep(for:.milliseconds(1))
        }
        do {
            _ = try await compiler.build(request(source:console,name:"Console.ino",revision:2))
            Issue.record("Overlapping build should be rejected")
        } catch ManagedCompilerError.busy { /* First build retains exclusive runtime ownership. */ }
        let result = try await first.value
        #expect(result.artifact.capsule.sha256 == "018c94a4a49b71880d6f04aecbe08e809c8ecf49e4278261c45dad3ead205720")
    }
    /// Main-actor signal tracks startup without unsafely sharing mutable captures across progress isolation.
    @MainActor private final class BusyProbe {
        /// Set only after the first build reserves the compiler actor.
        var started = false
    }

    /// A native page deadline disposes the pending context; a subsequent real SDK build remains independent.
    @Test func deadlineAndFreshBuild() async throws {
        let url = try serviceURL()
        let selected = try request(source:blink,name:"Blink.ino")
        let prepared = try await ManagedSketchPreprocessor.prepare(selected)
        let toolchain = try await VerifiedManagedToolchain.load(serviceURL:url)
        let host = ManagedWebKitHost()
        do {
            _ = try await host.run(prepared:prepared,toolchain:toolchain,progress:{ _ in },timeout:.milliseconds(1))
            Issue.record("Expected native host deadline")
        } catch ManagedCompilerError.timedOut { /* Expected bounded host failure. */ }
        let fresh = try await ManagedSketchCompiler(serviceURL:url).build(selected)
        #expect(fresh.artifact.capsule.sha256 == "018c94a4a49b71880d6f04aecbe08e809c8ecf49e4278261c45dad3ead205720")
    }
    /// Main-actor handoff avoids unsafe shared captures when a worker progress callback requests cancellation.
    @MainActor private final class CancellationProbe {
        /// The exact task canceled after the actual compilation phase begins.
        var task: Task<ManagedCompilationResult, any Error>?
    }
}
#endif
