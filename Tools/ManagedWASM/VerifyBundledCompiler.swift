import Foundation
import FirmingoKit

/// A separate public-API consumer proves default resource loading against exact experimental firmware metadata.
/// It has no service URL, device association, upload call or compiler sibling lookup.
@main struct VerifyBundledCompiler {
    /// Explicit build selection from the checked firmware CI export; never a moving latest descriptor.
    private static let buildID = "c44d25efe774eb47b163bc082906cf48b59b6e3dd1d0e19c7822925e6ba8275f"
    /// Fixed source bytes match separately recorded Node output and the independent firmware validator.
    private static let gpio = "void setup() { pinMode(6, 1); }\nvoid loop() { digitalWrite(6, 1); delay(10); }\n"
    /// A distinct console sketch exercises a second supported facade path without contacting a device.
    private static let console = "void setup() { Serial.println(\"ready\"); }\nvoid loop() { int c = Serial.read(); if (c >= 0) Serial.write(uint8_t(c)); }\n"

    /// Captures a new immutable source revision for an exact static catalogue selection.
    private static func request(_ source: String, name: String, revision: UInt64,
                                catalogue: ManagedCompilerCatalogue) throws -> ManagedOfflineBuildRequest {
        let snapshot = try SketchSourceSnapshot(documentID: UUID(), revision: revision, filename: name + ".ino", source: source)
        return try ManagedOfflineBuildRequest(snapshot: snapshot, catalogue: catalogue, firmwareBuildID: buildID)
    }

    /// Builds two capsules, rejects a frontend failure and verifies a fresh default-host build after that failure.
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw CocoaError(.fileReadInvalidFileName) }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let catalogue = try await ManagedCompilerCatalogue.loadBundled()
        guard catalogue.manifestSHA256 == "e341bfc0385fea9b2b026dc624daa26cdeac33286f4bb07243b37c1c31837d0e",
              catalogue.firmwareBuilds.count == 1,
              try catalogue.build(id: buildID).apiAddress == 0x10022c9c else { throw CocoaError(.fileReadCorruptFile) }
        let compiler = ManagedSketchCompiler()
        try await compiler.verifyResources()
        let cases = [("gpio", gpio, "958b861bbc18d4666ed03e6976b39b9fea4812409ad91a3501abbb9685a80d7d"),
                     ("console", console, "b372c00edf4b60c662f73055685ed8764e9f8798fe9efbbafad04302549174c0")]
        for (index, item) in cases.enumerated() {
            let selected = try request(item.1, name: item.0, revision: UInt64(index + 1), catalogue: catalogue)
            let result = try await compiler.build(selected)
            let artifact = result.artifact
            guard artifact.sha256 == item.2, artifact.receipt.firmwareBuildID == buildID,
                  artifact.receipt.catalogueSHA256 == catalogue.manifestSHA256,
                  artifact.compilerReceiptJSON != nil else { throw CocoaError(.fileReadCorruptFile) }
            try artifact.bytes.write(to: output.appendingPathComponent(item.0 + ".fms"), options: .withoutOverwriting)
            try artifact.reportJSON.write(to: output.appendingPathComponent(item.0 + "-report.json"), options: .withoutOverwriting)
            try JSONEncoder().encode(artifact.receipt).write(to: output.appendingPathComponent(item.0 + "-receipt.json"), options: .withoutOverwriting)
            print("Default packaged compiler:", item.0, artifact.sha256, "firmware", buildID)
        }
        do {
            _ = try await compiler.build(request("void setup() { missingFunction(); }\nvoid loop() {}\n",
                                                 name: "Syntax", revision: 3, catalogue: catalogue))
            throw CocoaError(.fileReadCorruptFile)
        } catch ManagedCompilerError.compilationFailed(let diagnostics) {
            guard diagnostics.contains(where: { $0.severity == .error && $0.filename == "Syntax.ino" }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        let fresh = try await compiler.build(request(gpio, name: "Fresh", revision: 4, catalogue: catalogue))
        guard fresh.artifact.sha256 == cases[0].2 else { throw CocoaError(.fileReadCorruptFile) }
        print("Default packaged compiler: syntax rejection and fresh rebuild verified; no device operation")
    }
}
