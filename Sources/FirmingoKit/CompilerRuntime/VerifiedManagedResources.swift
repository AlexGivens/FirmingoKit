import Foundation

/// SDK-owned immutable verified runtime/catalogue capabilities, independent of device identity or deployment.
struct VerifiedManagedResources: Sendable {
    /// Independently compiled-in anchor changed only with deliberate SDK resource review.
    static let inventorySHA256 = "bed0aecb48fdfa7734be8785f1619f0cc397488b03ff35758f6629c621b8bd14"
    /// Local resource directory; no sibling lookup, network fetch or environment override.
    private let root: URL
    /// Closed metadata verified before resource path construction.
    private let inventory: ManagedCompilerResourceInventory
    /// Exact already verified page bytes passed to a worker, never re-read by WebKit from disk.
    let page: Data
    /// Verified descriptor metadata; it does not establish service approval or installed-image identity.
    let catalogue: ManagedCompilerCatalogue

    /// Verifies thirteen runtime/source/license/catalogue/service-notice/package-provenance roles off UI execution.
    /// Finite root/hash injection is internal for tests; public callers can load only the SDK-owned bundle.
    @concurrent static func load(root: URL? = ManagedCompilerBundle.root(),
                                expectedSHA256: String = inventorySHA256) async throws -> Self {
        try Task.checkCancellation()
        guard let root, root.isFileURL else { throw ManagedCompilerResourceError.missingBundle }
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw ManagedCompilerResourceError.invalidFile("ManagedCompiler")
        }
        let inventoryData = try ManagedCompilerResourceReader.read(root.appendingPathComponent("inventory.json"),
                                                                   maximum: 16_384, role: "inventory.json")
        guard NanoManagedContract.isHex(expectedSHA256, bytes: 32), NanoManagedContract.digest(inventoryData) == expectedSHA256 else {
            throw ManagedCompilerResourceError.inventoryIntegrityMismatch
        }
        let inventory = try ManagedCompilerResourceInventory(data: inventoryData)
        var page = Data()
        var catalogueBytes = Data()
        var catalogueHash = ""
        for file in inventory.files {
            try Task.checkCancellation()
            let bytes = try ManagedCompilerResourceReader.read(root.appendingPathComponent(file.path), maximum: file.bytes, role: file.path)
            guard bytes.count == file.bytes, NanoManagedContract.digest(bytes) == file.sha256 else {
                throw ManagedCompilerResourceError.resourceIntegrityMismatch(file.path)
            }
            if file.path == "host.html" { page = bytes }
            if file.path == "catalogue.json" { catalogueBytes = bytes; catalogueHash = file.sha256 }
        }
        let catalogue = try await ManagedCompilerCatalogue.load(manifestJSON: catalogueBytes, expectedSHA256: catalogueHash)
        guard catalogue.firmwareBuilds.allSatisfy({ $0.recipeIdentifier == ManagedCompilerResourceInventory.recipeIdentifier &&
            $0.recipeSHA256 == ManagedCompilerResourceInventory.recipeSHA256 }) else {
            throw ManagedCompilerResourceError.incompatibleInventory
        }
        try Task.checkCancellation()
        return Self(root: root, inventory: inventory, page: page, catalogue: catalogue)
    }

    /// Loads only an approved, exact service from this verified resource directory; pending review fails before I/O.
    /// No external input or copied unapproved module can change the independently anchored review decision.
    @concurrent func toolchain(profile: ManagedSketchBuildRequest.Profile = .nanoManagedV1) async throws -> VerifiedManagedToolchain {
        try Task.checkCancellation()
        guard inventory.serviceApproved else { throw ManagedCompilerResourceError.serviceApprovalPending }
        let service = try ManagedCompilerResourceReader.read(root.appendingPathComponent(ManagedCompilerResourceInventory.servicePath),
            maximum: VerifiedManagedToolchain.serviceBytes, role: ManagedCompilerResourceInventory.servicePath)
        guard service.count == VerifiedManagedToolchain.serviceBytes,
              NanoManagedContract.digest(service) == VerifiedManagedToolchain.serviceSHA256 else {
            throw ManagedCompilerResourceError.resourceIntegrityMismatch(ManagedCompilerResourceInventory.servicePath)
        }
        try Task.checkCancellation()
        return VerifiedManagedToolchain(page: page, service: service, recipeSHA256: profile.recipeSHA256,
            toolchainSHA256: NanoManagedContract.digest(Data((VerifiedManagedToolchain.manifestSHA256 + ":" + VerifiedManagedToolchain.serviceSHA256).utf8)))
    }
}
