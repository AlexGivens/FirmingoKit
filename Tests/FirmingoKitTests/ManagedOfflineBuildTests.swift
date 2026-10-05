import Foundation
import Testing
@testable import FirmingoKit

/// Device-independent preparation/packaging/receipt and explicit association boundaries, without compiler or boards.
struct ManagedOfflineBuildTests {
    /// Independent Python capsule/input hashes and fields cover the exact synthetic metadata fixture.
    @Test func goldenOfflineArtifact() async throws {
        let selected = try await OfflineCompilerFixtures.request()
        let prepared = try await ManagedSketchPreprocessor.prepare(selected)
        let artifact = try await ManagedELFConverter.convert(CompilerFixtures.elf(), prepared: prepared,
                                                           provenance: OfflineCompilerFixtures.provenance())
        let expected = try #require(JSONSerialization.jsonObject(with: OfflineCompilerFixtures.json("expectations", folder: "compiler-offline")) as? [String: Any])
        #expect(artifact.sha256 == expected["capsuleSHA256"] as? String)
        #expect(artifact.bytes.count == expected["capsuleBytes"] as? Int)
        #expect(artifact.receipt.buildInputSHA256 == expected["buildInputSHA256"] as? String)
        #expect(artifact.receipt.linkedELFSHA256 == expected["linkedELFSHA256"] as? String)
        #expect(artifact.receipt.firmwareBuildID == selected.firmwareBuild.id)
        #expect(artifact.receipt.catalogueSHA256 == selected.catalogueSHA256)
        #expect(artifact.filename == "Sketch.fms")
        let encoded = try JSONEncoder().encode(artifact.receipt)
        let receipt = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(receipt["deviceID"] == nil)
        #expect(artifact.reportJSON.range(of: Data("deviceID".utf8)) == nil)
        var inputs = receipt
        for field in ["buildInputSHA256", "linkedELFSHA256", "capsuleSHA256"] { inputs.removeValue(forKey: field) }
        let expectedInputs = try #require(expected["inputs"] as? [String: Any])
        #expect(NSDictionary(dictionary: inputs) == NSDictionary(dictionary: expectedInputs))
    }

    /// Shared preprocessing retains legacy normalization, diagnostics and source mapping without creating a device binding.
    @Test func sharedPreparation() async throws {
        let source = "\u{feff}void setup() {}\r\nvoid loop() {}\r"
        let offline = try await ManagedSketchPreprocessor.prepare(OfflineCompilerFixtures.request(source: source))
        let legacy = try await ManagedSketchPreprocessor.prepare(CompilerFixtures.request(source: source))
        #expect(offline.sourceSHA256 == legacy.sourceSHA256)
        #expect(offline.translationUnit == legacy.translationUnit)
        #expect(offline.translationUnitSHA256 == legacy.translationUnitSHA256)
        #expect(offline.sourceLineCount == legacy.sourceLineCount)
        for line in 0...8 { #expect(offline.sourceLine(forGeneratedLine: line) == legacy.sourceLine(forGeneratedLine: line)) }
        do {
            _ = try await ManagedSketchPreprocessor.prepare(OfflineCompilerFixtures.request(source: "#include <Other.h>\nvoid loop() {}"))
            Issue.record("Unsupported libraries must fail")
        } catch SketchBuildError.unsupportedSource(let diagnostics) {
            #expect(diagnostics.first?.filename == "Sketch.ino")
            #expect(diagnostics.first?.line == 1)
        }
    }

    /// An absent/removed exact descriptor cannot become a latest-build fallback or a fabricated resident record.
    @Test func missingSelection() async throws {
        let selected = try await OfflineCompilerFixtures.request()
        let data = Data("{\"schema\":1,\"firmwareBuilds\":[]}".utf8)
        let empty = try await ManagedCompilerCatalogue.load(manifestJSON: data, expectedSHA256: NanoManagedContract.digest(data))
        #expect(throws: ManagedCatalogueError.missingBuild) {
            try ManagedOfflineBuildRequest(snapshot: selected.snapshot, catalogue: empty, firmwareBuildID: selected.firmwareBuild.id)
        }
    }

    /// Revision/document/source/name, catalogue bytes, firmware descriptor and toolchain all affect complete input identity.
    @Test func completeOfflineInputIdentity() async throws {
        let original = try await OfflineCompilerFixtures.request()
        let changedCatalogue = try OfflineCompilerFixtures.json("catalogue") + Data(" ".utf8)
        var metadata = try #require(JSONSerialization.jsonObject(with: OfflineCompilerFixtures.json("descriptor")) as? [String: Any])
        metadata["buildReportSHA256"] = String(repeating: "8", count: 64)
        let changedFirmware = try JSONSerialization.data(withJSONObject: ["schema": 1, "firmwareBuilds": [metadata]], options: [.sortedKeys])
        let requests = [original, try await OfflineCompilerFixtures.request(revision: 8),
            try await OfflineCompilerFixtures.request(revision: UInt64.max),
            try await OfflineCompilerFixtures.request(documentID: UUID()),
            try await OfflineCompilerFixtures.request(source: "// changed\nvoid setup() {}\nvoid loop() {}"),
            try await OfflineCompilerFixtures.request(filename: "Other.ino"),
            try await OfflineCompilerFixtures.request(manifest: changedCatalogue),
            try await OfflineCompilerFixtures.request(manifest: changedFirmware)]
        var identities: Set<String> = []
        let elf = try CompilerFixtures.elf()
        for request in requests {
            let prepared = try await ManagedSketchPreprocessor.prepare(request)
            let result = try await ManagedELFConverter.convert(elf, prepared: prepared, provenance: OfflineCompilerFixtures.provenance())
            #expect(identities.insert(result.receipt.buildInputSHA256).inserted)
        }
        let prepared = try await ManagedSketchPreprocessor.prepare(original)
        let otherToolchain = try await ManagedELFConverter.convert(elf, prepared: prepared,
            provenance: OfflineCompilerFixtures.provenance(toolchainHash: String(repeating: "6", count: 64)))
        #expect(identities.insert(otherToolchain.receipt.buildInputSHA256).inserted)
        let repeated = try await ManagedELFConverter.convert(elf, prepared: prepared, provenance: OfflineCompilerFixtures.provenance())
        #expect(identities.contains(repeated.receipt.buildInputSHA256))
    }

    /// Binding reuses bytes across real-shaped device IDs while rejecting mismatched static firmware evidence.
    @Test func explicitDeviceBinding() async throws {
        let selected = try await OfflineCompilerFixtures.request()
        let artifact = try await ManagedELFConverter.convert(CompilerFixtures.elf(),
            prepared: ManagedSketchPreprocessor.prepare(selected), provenance: OfflineCompilerFixtures.provenance())
        for deviceID in ["0102030405060708", "1112131415161718"] {
            let association = try ManagedDeviceAssociation(deviceID: deviceID, firmwareBuildID: selected.firmwareBuild.id,
                                                          evidence: .hostConfirmedExistingFirmware)
            let capsule = try artifact.bind(to: association)
            #expect(capsule.resident.deviceID == deviceID)
            #expect(capsule.resident.residentELFSHA256 == selected.firmwareBuild.residentELFSHA256)
            #expect(capsule.resident.firmwareImageSHA256 == selected.firmwareBuild.firmwareImageSHA256)
            #expect(capsule.bytes == artifact.bytes)
            #expect(capsule.sha256 == artifact.sha256)
            let legacy = try await ManagedELFConverter.convert(CompilerFixtures.elf(),
                prepared: ManagedSketchPreprocessor.prepare(CompilerFixtures.request(resident: capsule.resident)),
                provenance: OfflineCompilerFixtures.provenance())
            #expect(legacy.capsule.bytes == artifact.bytes)
            #expect(legacy.reportJSON == artifact.reportJSON)
        }
        let mismatch = try ManagedDeviceAssociation(deviceID: "0102030405060708", firmwareBuildID: String(repeating: "9", count: 64),
                                                   evidence: .hostConfirmedExistingFirmware)
        #expect(throws: ManagedCatalogueError.associationMismatch) { try artifact.bind(to: mismatch) }
    }

    /// Mismatched recipe metadata and conventional/truncated ELF cannot issue an offline artifact.
    @Test func invalidOutputAndRecipe() async throws {
        let prepared = try await ManagedSketchPreprocessor.prepare(OfflineCompilerFixtures.request())
        do {
            _ = try await ManagedELFConverter.convert(CompilerFixtures.elf(), prepared: prepared, provenance: CompilerFixtures.provenance())
            Issue.record("A different recipe must not issue an offline artifact")
        } catch SketchBuildError.invalidProvenance { /* Exact recipe mismatch, not an ELF parse failure. */ }
        for elf in [Data(), Data("UF2\n".utf8) + Data(repeating: 0, count: 508), try CompilerFixtures.elf().prefix(100)] {
            await #expect(throws: SketchBuildError.self) {
                try await ManagedELFConverter.convert(elf, prepared: prepared, provenance: OfflineCompilerFixtures.provenance())
            }
        }
    }

    /// Both offline preparation and packaging preserve cancellation and never return a former result.
    @Test func cancelledOfflineWork() async throws {
        let selected = try await OfflineCompilerFixtures.request()
        let preparation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ManagedSketchPreprocessor.prepare(selected)
        }
        await #expect(throws: CancellationError.self) { try await preparation.value }
        let prepared = try await ManagedSketchPreprocessor.prepare(selected)
        let packaging = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ManagedELFConverter.convert(CompilerFixtures.elf(), prepared: prepared,
                                                       provenance: OfflineCompilerFixtures.provenance())
        }
        await #expect(throws: CancellationError.self) { try await packaging.value }
    }
}
