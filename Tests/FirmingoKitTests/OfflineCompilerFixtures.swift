import Foundation
import Testing
@testable import FirmingoKit

/// Synthetic independent catalogue/parser inputs only; neither metadata nor output may reach hardware.
enum OfflineCompilerFixtures {
    /// Loads a finite SDK-local JSON fixture without touching reference checkouts.
    static func json(_ name: String, folder: String = "compiler-catalogue") throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/\(folder)"))
        return try Data(contentsOf: url)
    }
    /// Selects the independent synthetic descriptor through the real hash-verified catalogue boundary.
    static func request(source: String = "void setup() {}\nvoid loop() {}", revision: UInt64 = 7,
                        filename: String = "Sketch.ino", documentID: UUID = CompilerFixtures.documentID,
                        manifest: Data? = nil) async throws -> ManagedOfflineBuildRequest {
        let data = try manifest ?? json("catalogue")
        let catalogue = try await ManagedCompilerCatalogue.load(manifestJSON: data, expectedSHA256: NanoManagedContract.digest(data))
        let selected = try #require(catalogue.firmwareBuilds.first)
        let snapshot = try SketchSourceSnapshot(documentID: documentID, revision: revision, filename: filename, source: source)
        return try ManagedOfflineBuildRequest(snapshot: snapshot, catalogue: catalogue, firmwareBuildID: selected.id)
    }
    /// Declares only parser provenance with the selected fixed recipe; it never claims compiler execution.
    static func provenance(toolchainHash: String = String(repeating: "5", count: 64)) throws -> ManagedELFProvenance {
        try CompilerFixtures.provenance(recipe: "nano-stateless-clang-22.1.8-v1-experimental",
            recipeHash: "b7869f6fc863e1905deb6974408c6e7dc63943a1fb3e342a357fdf757b1e23d9", toolchainHash: toolchainHash)
    }
}
