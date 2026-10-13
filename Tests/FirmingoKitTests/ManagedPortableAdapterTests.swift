import Foundation
import Testing
@testable import FirmingoKit

/// Native adapter contracts remain testable without a service, browser or sibling checkout.
struct ManagedPortableAdapterTests {
    /// Legacy requests keep physical identity out of JSON and preserve the entire UInt64 revision as a token.
    @Test func legacyStaticSelection() throws {
        let selected = try CompilerFixtures.request(source: "\u{feff}// café 🎵\r\nvoid setup() {}\r\nvoid loop() {}", revision: .max)
        let request = try ManagedPortableRequest(selected)
        let root = try WireJSON.parse(request.json)
        #expect(try root.required("source").required("revision").string() == CompilerFixtures.documentID.uuidString + ":18446744073709551615")
        #expect(try root.required("source").required("text").string() == selected.snapshot.source)
        let target = try root.required("target").required("residentBinding")
        #expect(try target.object().count == 9)
        #expect(!String(decoding: request.json, as: UTF8.self).contains("deviceID"))
        #expect(!String(decoding: request.json, as: UTF8.self).contains("firmwareVersion"))
        #expect(request.targetIdentityKey == "residentBindingID")
        #expect(request.requestSHA256 == NanoManagedContract.digest(request.json))
    }
    /// Exact catalogue descriptors remain selected without inventing a device association.
    @Test func offlineStaticSelection() async throws {
        let selected = try await OfflineCompilerFixtures.request(revision: .max)
        let request = try ManagedPortableRequest(selected)
        #expect(request.targetIdentity == selected.firmwareBuild.id)
        #expect(request.targetIdentityKey == "firmwareBuildID")
        let root = try WireJSON.parse(request.json)
        #expect(try root.required("target").required("firmwareBuild").object().count == 16)
        #expect(!String(decoding: request.json, as: UTF8.self).contains("deviceID"))
    }
    /// Closed, correlated failure envelopes preserve distinct public errors; malformed data cannot claim an outcome.
    @Test(arguments: ["buildID", "outcome", "stage", "message", "code", "sequence", "extra", "diagnosticCode", "diagnosticPosition"])
    func malformedFailures(_ mutation: String) async throws {
        let request = try ManagedPortableRequest(CompilerFixtures.request())
        var root = failure(request)
        var event = try #require(root["event"] as? [String: Any])
        var error = try #require(event["error"] as? [String: Any])
        switch mutation {
        case "buildID": event["buildID"] = "stale"
        case "outcome": event["outcome"] = "succeeded_with_errors"
        case "stage": error["stage"] = "uploading"
        case "message": error["message"] = String(repeating: "x", count: 4097)
        case "code": error["code"] = "CompileFailed"
        case "sequence": event["sequence"] = true
        case "extra": root["untrusted"] = true
        default:
            var diagnostic = try #require((root["diagnostics"] as? [[String: Any]])?.first)
            if mutation == "diagnosticCode" { diagnostic["code"] = "" }
            else { diagnostic["line"] = 0 }
            root["diagnostics"] = [diagnostic]
        }
        event["error"] = error; root["event"] = event
        let json = String(decoding: try ManagedPortableRequest.canonical(root), as: UTF8.self)
        await #expect(throws: FirmingoError.self) { _ = try await ManagedPortableOutput.decode(json, request: request) }
    }
    /// Genuine failure data maps to the existing Swift diagnostic API, without manufacturing an artifact.
    @Test func preservesCompileFailure() async throws {
        let request = try ManagedPortableRequest(CompilerFixtures.request())
        let json = String(decoding: try ManagedPortableRequest.canonical(failure(request)), as: UTF8.self)
        do {
            _ = try await ManagedPortableOutput.decode(json, request: request)
            Issue.record("Compilation failure must never yield an artifact")
        } catch ManagedCompilerError.compilationFailed(let diagnostics) {
            #expect(diagnostics.count == 1)
            #expect(diagnostics.first?.filename == "Sketch.ino")
            #expect(diagnostics.first?.line == 1)
        }
    }
    /// The retired ELF-only bridge schema cannot enter the portable receipt boundary, even when marked successful.
    @Test func rejectsRetiredBridgeEnvelope() async throws {
        let request = try ManagedPortableRequest(CompilerFixtures.request())
        let old: [String: Any] = ["succeeded": true, "status": 0, "canRunAgain": true, "memoryBytes": 65536,
            "diagnostics": [], "timings": [], "elfBase64": Data(repeating: 0, count: 52).base64EncodedString(),
            "moduleMilliseconds": 0, "instantiateMilliseconds": 0]
        let json = String(decoding: try ManagedPortableRequest.canonical(old), as: UTF8.self)
        await #expect(throws: FirmingoError.self) { _ = try await ManagedPortableOutput.decode(json, request: request) }
    }
    /// Portable cancellation and deadline outcomes keep their existing native error categories.
    @Test(arguments: ["cancelled", "timed_out"])
    func interruptionOutcomes(_ outcome: String) async throws {
        let request = try ManagedPortableRequest(CompilerFixtures.request())
        let root: [String: Any] = ["schema": 1, "diagnostics": [], "event": ["interfaceVersion": 1, "kind": "result",
            "buildID": request.buildID, "sequence": 1, "outcome": outcome,
            "error": ["code": outcome, "stage": "verifying", "message": "synthetic interrupted parser input"]]]
        let json = String(decoding: try ManagedPortableRequest.canonical(root), as: UTF8.self)
        if outcome == "cancelled" {
            await #expect(throws: CancellationError.self) { _ = try await ManagedPortableOutput.decode(json, request: request) }
        } else {
            do {
                _ = try await ManagedPortableOutput.decode(json, request: request)
                Issue.record("Deadline outcome must never yield an artifact")
            } catch ManagedCompilerError.timedOut { /* Exact native deadline category is preserved. */ }
        }
    }
    /// Synthetic failure input tests parsing only; it claims no compiler execution or deployable output.
    private func failure(_ request: ManagedPortableRequest) -> [String: Any] {
        ["schema": 1, "event": ["interfaceVersion": 1, "kind": "result", "buildID": request.buildID, "sequence": 5,
            "outcome": "failed", "error": ["code": "compile_failed", "stage": "compiling", "message": "synthetic parser failure"]],
         "diagnostics": [["severity": "error", "stage": "compiling", "code": "compiler_diagnostic", "message": "synthetic parser failure",
            "filename": "Sketch.ino", "line": 1, "column": 1]]]
    }
}
