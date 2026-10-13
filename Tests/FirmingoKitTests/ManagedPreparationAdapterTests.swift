import Foundation
import Testing
@testable import FirmingoKit

/// Real service-free WebKit preparation and native boundary checks require no compiler binary or device.
@Suite(.serialized)
@MainActor struct ManagedPreparationAdapterTests {
    /// Both request forms preserve identical preparation and the entire revision while distribution remains pending.
    @Test func serviceFreeLegacyAndOfflineParity() async throws {
        let source = "\u{feff}// café 🎵\r\nvoid setup() {}\rvoid loop() {}"
        let legacy = try CompilerFixtures.request(source: source, revision: .max)
        let offline = try await OfflineCompilerFixtures.request(source: source, revision: .max)
        let first = try await ManagedSketchPreprocessor.prepare(legacy)
        let second = try await ManagedSketchPreprocessor.prepare(offline)
        #expect(first.sourceSHA256 == second.sourceSHA256)
        #expect(first.translationUnitSHA256 == second.translationUnitSHA256)
        #expect(first.translationUnit == second.translationUnit)
        #expect(first.request.snapshot.revision == .max)
        #expect(second.request.snapshot.revision == .max)
        await #expect(throws: ManagedCompilerResourceError.serviceApprovalPending) { try await ManagedSketchCompiler().verifyResources() }
    }
    /// Actual prepared data is correlated before publication; altered input/output identities and additive fields fail.
    @Test func nativePreparationBoundary() async throws {
        let request = try ManagedPortableRequest(CompilerFixtures.request(source: "void setup() {}\nvoid loop() {}"))
        let resources = try await VerifiedManagedResources.load()
        let json = try await ManagedWebKitHost().prepare(request: request, page: resources.page)
        let prepared = try await ManagedPortablePreparation.decode(json, request: request)
        #expect(prepared.source.sourceSHA256 == NanoManagedContract.digest(Data(request.snapshot.source.utf8)))
        let original = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        for mutation in ["buildID", "requestSHA256", "operation", "sourceSHA256", "translationUnitSHA256", "translationUnit", "sourceLineCount", "sourceBOMBytes", "extra"] {
            var root = original
            var output = try #require(root["preparation"] as? [String: Any])
            switch mutation {
            case "buildID": root[mutation] = "stale"
            case "requestSHA256": root[mutation] = String(repeating: "0", count: 64)
            case "operation": root[mutation] = "compile"
            case "translationUnit": output[mutation] = "altered"
            case "sourceLineCount": output[mutation] = 0
            case "sourceBOMBytes": output[mutation] = 3
            case "extra": root[mutation] = true
            default: output[mutation] = String(repeating: "0", count: 64)
            }
            root["preparation"] = output
            let changed = String(decoding: try ManagedPortableRequest.canonical(root), as: UTF8.self)
            await #expect(throws: FirmingoError.self) { _ = try await ManagedPortablePreparation.decode(changed, request: request) }
        }
    }
    /// First-line errors include the original three UTF-8 BOM bytes rather than normalized-source columns.
    @Test func originalBOMDiagnosticColumns() async throws {
        do {
            _ = try await ManagedSketchPreprocessor.prepare(CompilerFixtures.request(source: "\u{feff}  #define BAD 1"))
            Issue.record("Unsupported directive must fail")
        } catch SketchBuildError.unsupportedSource(let diagnostics) {
            #expect(diagnostics.count == 1)
            #expect(diagnostics.first?.line == 1)
            #expect(diagnostics.first?.column == 6)
        }
    }
    /// Native startup deadlines dispose the page and a fresh independent service-free operation still succeeds.
    @Test func deadlineAndFreshPreparation() async throws {
        let request = try ManagedPortableRequest(CompilerFixtures.request())
        let resources = try await VerifiedManagedResources.load()
        do {
            _ = try await ManagedWebKitHost().prepare(request: request, page: resources.page, timeout: .milliseconds(1))
            Issue.record("One-millisecond startup deadline must fail")
        } catch ManagedCompilerError.timedOut { /* Exact native deadline outcome, not an artifact. */ }
        let fresh = try await ManagedSketchPreprocessor.prepare(CompilerFixtures.request())
        #expect(!fresh.translationUnit.isEmpty)
    }
    /// A cancelled caller cannot publish prepared output or poison a subsequent service-free operation.
    @Test func cancellationAndFreshPreparation() async throws {
        let request = try CompilerFixtures.request(source: String(repeating: "// bounded input\n", count: 12000) + "void setup() {} void loop() {}")
        let pending = Task { try await ManagedSketchPreprocessor.prepare(request) }
        pending.cancel()
        await #expect(throws: CancellationError.self) { _ = try await pending.value }
        #expect(try await ManagedSketchPreprocessor.prepare(CompilerFixtures.request()).sourceLineCount == 2)
    }
}
