import Foundation

/// Hash-verified, bounded firmware-build catalogue, with explicit selection and no device or compiler side effect.
/// The trusted hash must come from independently reviewed package/build provenance, not the same untrusted file.
/// This metadata boundary does not load a WASM service or establish publisher, installed-image or hardware proof.
public struct ManagedCompilerCatalogue: Sendable {
    /// Exact input manifest digest; whitespace changes alter this identity, not descriptor content IDs.
    public let manifestSHA256: String
    /// Immutable descriptors in manifest order; no entry is implicitly selected as the latest build.
    public let firmwareBuilds: [ManagedFirmwareBuildDescriptor]

    /// Loads only SDK-owned, inventory/hash-verified descriptor resources off UI execution, without a device or service.
    /// The current bundle intentionally contains an empty catalogue pending trusted firmware-build exports.
    /// Resource/schema/I/O errors propagate; cancellation remains CancellationError. No entry or latest build is
    /// synthesized, and successful metadata loading does not establish compiler availability or hardware support.
    @concurrent public static func loadBundled() async throws -> Self {
        try await VerifiedManagedResources.load().catalogue
    }

    /// Verifies exact bytes before parsing a closed schema-one catalogue off main-actor execution.
    /// Required keys are `schema: 1` and `firmwareBuilds: [...]`; at most 32 descriptors, 128 KiB,
    /// and 8192 JSON tokens are accepted. Empty catalogues honestly expose no firmware builds.
    /// Duplicate descriptor IDs and conflicting metadata for one complete-image hash fail. Cancellation
    /// remains CancellationError. All accepted entries retain experimental status; no resource is shipped here.
    @concurrent public static func load(manifestJSON: Data, expectedSHA256: String) async throws -> Self {
        try Task.checkCancellation()
        guard manifestJSON.count <= 128 * 1024 else { throw ManagedCatalogueError.invalidCatalogue }
        guard NanoManagedContract.isHex(expectedSHA256, bytes: 32), NanoManagedContract.digest(manifestJSON) == expectedSHA256 else {
            throw ManagedCatalogueError.integrityMismatch
        }
        let builds: [ManagedFirmwareBuildDescriptor]
        do {
            let root = try WireJSON.parse(manifestJSON, maximumBytes: 128 * 1024, maximumTokens: 8192)
            guard Set(try root.object().keys) == Set([Data("schema".utf8), Data("firmwareBuilds".utf8)]),
                  try root.required("schema").uint32() == 1 else { throw ManagedCatalogueError.invalidCatalogue }
            let records = try root.required("firmwareBuilds").array()
            guard records.count <= 32 else { throw ManagedCatalogueError.invalidCatalogue }
            var result: [ManagedFirmwareBuildDescriptor] = []
            var ids: Set<String> = []
            var images: [String: ManagedFirmwareBuildDescriptor] = [:]
            for record in records {
                try Task.checkCancellation()
                let descriptor = try ManagedFirmwareBuildDescriptor(value: record)
                guard ids.insert(descriptor.id).inserted else { throw ManagedCatalogueError.invalidCatalogue }
                if let previous = images[descriptor.firmwareImageSHA256], previous != descriptor {
                    throw ManagedCatalogueError.invalidCatalogue
                }
                images[descriptor.firmwareImageSHA256] = descriptor
                result.append(descriptor)
            }
            builds = result
        } catch is CancellationError { throw CancellationError() }
        catch { throw ManagedCatalogueError.invalidCatalogue }
        try Task.checkCancellation()
        return Self(manifestSHA256: expectedSHA256, firmwareBuilds: builds)
    }

    /// Lists explicit target choices without automatically choosing among multiple resident builds.
    /// Pico returns no choices because the SDK has no reviewed Pico managed recipe/firmware target.
    public func builds(for board: FirmingoBoard, profile: ManagedSketchBuildRequest.Profile = .nanoManagedV1) -> [ManagedFirmwareBuildDescriptor] {
        firmwareBuilds.filter { $0.board == board && $0.profile == profile }
    }

    /// Resolves exactly one immutable descriptor identity; a missing/removed build is never rebound to latest.
    public func build(id: String) throws -> ManagedFirmwareBuildDescriptor {
        guard let result = firmwareBuilds.first(where: { $0.id == id }) else { throw ManagedCatalogueError.missingBuild }
        return result
    }

    /// Reports absent target metadata separately from compiler resources or physical execution qualification.
    public func unavailableReason(for board: FirmingoBoard) -> String? {
        if board != .nanoRP2040Connect { return "This board has no reviewed managed firmware target or compiler recipe." }
        if builds(for: board).isEmpty { return "No reviewed resident build is present in this catalogue." }
        return nil
    }
}
