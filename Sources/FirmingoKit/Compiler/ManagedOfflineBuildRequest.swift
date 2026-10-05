import Foundation

/// Immutable offline source/catalogue/firmware selection without a physical-device identity or connection.
/// The selected descriptor declares trusted build metadata; it does not attest installed bytes or qualify a recipe.
public struct ManagedOfflineBuildRequest: Equatable, Sendable {
    /// Exact editor snapshot retained throughout preprocessing, compilation and packaging.
    public let snapshot: SketchSourceSnapshot
    /// Exact verified catalogue bytes, retained even when two catalogues contain identical descriptors.
    public let catalogueSHA256: String
    /// Explicit resident build and compatible recipe; no latest-build fallback exists.
    public let firmwareBuild: ManagedFirmwareBuildDescriptor

    /// Resolves an exact descriptor from a verified catalogue, or throws missingBuild without side effects.
    /// No device association is required, created or inferred. Unsupported board/recipe entries have already
    /// failed catalogue validation; trusted provenance remains the caller's responsibility.
    public init(snapshot: SketchSourceSnapshot, catalogue: ManagedCompilerCatalogue, firmwareBuildID: String) throws {
        self.snapshot = snapshot
        catalogueSHA256 = catalogue.manifestSHA256
        firmwareBuild = try catalogue.build(id: firmwareBuildID)
    }
}
