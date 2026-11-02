import Foundation
import FirmingoKit

/// Real public SDK implementation; contains no recipe, parser, packaging or device implementation.
@MainActor public final class SDKWorkbenchCompiler: WorkbenchCompilerBackend {
    /// Same actor for smoke/diagnostic/fresh-build work within a host instance.
    private let compiler = ManagedSketchCompiler()
    /// SDK-verified catalogue retained for explicit request construction.
    private var loaded: ManagedCompilerCatalogue?
    /// Creates no web host, network connection or resource load.
    public init() {}
    /// Acquires current bundled descriptors; success is metadata evidence only.
    public func catalogue() async throws -> WorkbenchCatalogue {
        let catalogue = try await ManagedCompilerCatalogue.loadBundled()
        loaded = catalogue
        return WorkbenchCatalogue(sha256: catalogue.manifestSHA256, builds: catalogue.firmwareBuilds.map {
            .init(id: $0.id, board: $0.board.rawValue, profile: $0.profile.rawValue)
        })
    }
    /// Delegates resource verification without a developer service URL or fallback provider.
    public func verifyResources() async throws { try await compiler.verifyResources() }
    /// Produces exact real bytes with source/recipe/service provenance and independently pinned vector comparison.
    public func compile(_ input: WorkbenchCompilerInput, buildID: String, probe: WorkbenchCompilerProbe) async throws -> WorkbenchReport.Artifact {
        defer { probe.finish() }
        guard let loaded, buildID == WorkbenchCompilerInput.buildID else { throw WorkbenchFailure("This descriptor has no migrated compiler vectors.") }
        let source = try SketchSourceSnapshot(documentID: UUID(), revision: 1, filename: "Workbench-" + input.rawValue + ".ino", source: try input.source)
        let request = try ManagedOfflineBuildRequest(snapshot: source, catalogue: loaded, firmwareBuildID: buildID)
        let result = try await compiler.build(request, progress: { probe.record($0) })
        guard let expected = input.expectedSHA256, result.artifact.sha256 == expected,
              result.artifact.receipt.firmwareBuildID == buildID,
              result.artifact.receipt.catalogueSHA256 == loaded.manifestSHA256,
              result.artifact.compilerReceiptJSON != nil else { throw WorkbenchFailure("Unexpected compiler output; the pinned capsule assertion failed.") }
        return .init(name: input.rawValue + ".fms", sha256: expected, bytes: result.artifact.bytes,
            receiptJSON: try JSONEncoder().encode(result.artifact.receipt), wasmLinearMemoryBytes: result.linearMemoryBytes)
    }
}
