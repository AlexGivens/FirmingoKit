import Foundation
import Testing
@testable import FirmingoKit

/// Independent native bridge vectors exercise exact schemas and fail-closed compile/link semantics.
struct ManagedCompilerBridgeTests {
    /// Constructs a minimal explicit bridge result, independent of any SDK encoder or actual service.
    private func response(succeeded: Bool = true) -> [String: Any] {
        var result: [String: Any] = ["succeeded": succeeded, "status": 0, "canRunAgain": true,
            "memoryBytes": 65536, "moduleMilliseconds": 1.5, "instantiateMilliseconds": 0,
            "diagnostics": [], "timings": [["phase": "compiling", "milliseconds": 1],
                ["phase": "compiling", "milliseconds": 2], ["phase": "linking", "milliseconds": 3]]]
        if succeeded { result["elfBase64"] = Data(repeating: 0, count: 52).base64EncodedString() }
        return result
    }
    /// Encodes test vectors with real JSON scalar types; no production bridge serialization is invoked.
    private func json(_ value: [String: Any]) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self) }
    /// Accepts a well-formed successful envelope but leaves ELF structural checking to the separate parser.
    @Test func successfulEnvelope() async throws {
        let decoded = try await ManagedWorkerOutput.decode(json(response()))
        #expect(decoded.elf == Data(repeating: 0, count: 52))
        #expect(decoded.diagnostics.isEmpty)
        #expect(decoded.memoryBytes == 65536)
    }
    /// A zero service status with error diagnostics is still compilation failure and returns no artifact.
    @Test func zeroStatusError() async throws {
        var result = response(succeeded: false)
        result["timings"] = [["phase": "compiling", "milliseconds": 4]]
        result["diagnostics"] = [["severity": "error", "message": "undeclared identifier", "filename": "Sketch.ino", "line": 1, "column": 16]]
        do {
            _ = try await ManagedWorkerOutput.decode(json(result))
            Issue.record("Expected real compilation failure")
        } catch ManagedCompilerError.compilationFailed(let diagnostics) {
            #expect(diagnostics.count == 1)
            #expect(diagnostics[0].line == 1)
            #expect(diagnostics[0].filename == "Sketch.ino")
        }
    }
    /// Additive fields, scalar coercions, oversized memory, stale re-entry and malformed base64 all fail closed.
    @Test(arguments: ["extra", "booleanStatus", "numericSuccess", "memory", "unsafe", "base64", "timings", "failedWithoutError"])
    func rejectsInvalidEnvelope(_ kind: String) async throws {
        var result = response()
        switch kind {
        case "extra": result["extra"] = 1
        case "booleanStatus": result["status"] = false
        case "numericSuccess": result["succeeded"] = 1
        case "memory": result["memoryBytes"] = 268435457
        case "unsafe": result["canRunAgain"] = false
        case "base64": result["elfBase64"] = "@@@"
        case "timings": result["timings"] = [["phase":"linking", "milliseconds":0]]
        default: result = response(succeeded:false)
        }
        await #expect(throws: (any Error).self) { _ = try await ManagedWorkerOutput.decode(json(result)) }
    }
    /// Malformed diagnostic records never vanish into a falsely successful result.
    @Test(arguments: ["severity", "message", "position", "filename", "extra"])
    func rejectsInvalidDiagnostic(_ kind: String) async throws {
        var record: [String: Any] = ["severity":"note", "message":"context", "filename":NSNull(), "line":NSNull(), "column":NSNull()]
        switch kind {
        case "severity": record["severity"] = "unknown"
        case "message": record["message"] = String(repeating:"x",count:4097)
        case "position": record["line"] = 1
        case "filename": record["filename"] = false
        default: record["extra"] = 1
        }
        var result = response(); result["diagnostics"] = [record]
        await #expect(throws: (any Error).self) { _ = try await ManagedWorkerOutput.decode(json(result)) }
    }
    /// Strict JSON parsing rejects duplicate keys instead of allowing a later success flag to replace failure.
    @Test func duplicateKeys() async throws {
        let text = try json(response()).dropLast() + ",\"succeeded\":false}"
        await #expect(throws: (any Error).self) { _ = try await ManagedWorkerOutput.decode(String(text)) }
    }
    /// A missing entire SwiftPM bundle returns nil rather than invoking SwiftPM's trapping resource accessor.
    @Test func missingBundleIsOptional() {
        #expect(ManagedCompilerBundle.locate(candidates:[]) == nil)
        #expect(ManagedCompilerBundle.locate(candidates:[URL(fileURLWithPath:"/nonexistent-firmingo-bundle-root")]) == nil)
        #expect(ManagedCompilerBundle.root() != nil)
    }
    /// Resource verification rejects an absent service without instantiating WebKit or connecting a board.
    @Test func missingService() async throws {
        await #expect(throws: (any Error).self) {
            _ = try await VerifiedManagedToolchain.load(serviceURL: URL(fileURLWithPath: "/nonexistent-firmingo-service.wasm"))
        }
    }
}

extension ManagedCompilerBridgeTests {
    /// Explicit host records validate schema and metadata syntax without claiming that an image was installed.
    @Test func residentRecord() throws {
        let record: [String: Any] = ["schema":1,"board":"nano_rp2040_connect","profile":"nano-managed-v1", "deviceID":"0102030405060708",
            "residentELFSHA256":String(repeating:"0",count:64),"firmwareImageSHA256":String(repeating:"1",count:64),"apiAddress":0x10022ca0]
        let binding = try ManagedResidentBinding(recordJSON: JSONSerialization.data(withJSONObject:record))
        #expect(binding.apiAddress == 0x10022ca0)
        for (key, invalid) in [("schema",2 as Any), ("board","pico" as Any), ("apiAddress",false as Any), ("unknown",1 as Any)] {
            var mutated = record; mutated[key] = invalid
            #expect(throws: (any Error).self) { _ = try ManagedResidentBinding(recordJSON: JSONSerialization.data(withJSONObject:mutated)) }
        }
    }
}
